import Combine
import Foundation
import OSLog

nonisolated protocol CommunityFeedCaching {
    func load(query: CommunityFeedQuery) -> [CommunityPost]
    func save(_ posts: [CommunityPost], query: CommunityFeedQuery)
}

nonisolated struct CommunityFeedCache: CommunityFeedCaching {
    private static let key = "community.feed.placeholderCache"

    func load(query: CommunityFeedQuery) -> [CommunityPost] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey(for: query)) else { return [] }
        return (try? JSONDecoder().decode([CommunityPost].self, from: data)) ?? []
    }

    func save(_ posts: [CommunityPost], query: CommunityFeedQuery) {
        guard let data = try? JSONEncoder().encode(posts) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey(for: query))
    }

    private func cacheKey(for query: CommunityFeedQuery) -> String {
        CampusScopedDefaults.key("\(CommunityFeedCache.key).\(query.cacheKey)")
    }
}

enum CommunityFeedLoadMode {
    case cacheFirst
    case refresh
}

nonisolated enum CommunityFeedSearchDebounce {
    static let delay: Duration = .milliseconds(320)

    static func waitIfNeeded(for query: CommunityFeedQuery) async -> Bool {
        guard query.hasSearch else { return true }

        do {
            try await Task.sleep(for: delay)
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}

@MainActor
final class CommunityFeedViewModel: ObservableObject {
    @Published private(set) var posts: [CommunityPost] = []
    @Published private(set) var items: [CommunityFeedItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMoreItems = true
    @Published private(set) var activeLikePostIDs: Set<UUID> = []
    @Published private(set) var activeFavoritePostIDs: Set<UUID> = []
    @Published private(set) var activePollIDs: Set<UUID> = []
    @Published var errorMessage: String?

    private static let pageSize = 20
    private static let maximumFeedLimit = 50

    private var currentQuery = CommunityFeedQuery.default
    private var activeLoadID: UUID?
    private let repository: any CommunityFeedRepository
    private let cache: any CommunityFeedCaching

    init(
        repository: any CommunityFeedRepository = LiveCommunityRepository(),
        cache: any CommunityFeedCaching = CommunityFeedCache()
    ) {
        self.repository = repository
        self.cache = cache
    }

    func load(mode: CommunityFeedLoadMode = .cacheFirst, query: CommunityFeedQuery = .default) async {
        let loadID = UUID()
        activeLoadID = loadID

        let didChangeQuery = currentQuery != query
        currentQuery = query
        isLoadingMore = false
        hasMoreItems = true
        if didChangeQuery {
            posts = []
            items = []
        }

        switch mode {
        case .cacheFirst:
            loadCachedPostsIfAvailable(query: query)
            await refreshFromNetwork(query: query, loadID: loadID)
        case .refresh:
            await refreshFromNetwork(query: query, loadID: loadID)
        }
    }

    private func loadCachedPostsIfAvailable(query: CommunityFeedQuery) {
        guard posts.isEmpty else { return }
        let cachedPosts = cache.load(query: query)
        if !cachedPosts.isEmpty {
            posts = cachedPosts
            items = CommunityFeedItemOrdering.ordered(posts: cachedPosts, polls: [], matching: query)
        }
    }

    private func refreshFromNetwork(query: CommunityFeedQuery, loadID: UUID) async {
        CommunityDiagnostics.log.info("Community feed load started")

        isLoading = true
        defer {
            if activeLoadID == loadID {
                isLoading = false
            }
        }

        do {
            try await CommunityTimeout.run(
                seconds: 10,
                message: L10n.text("社区会话建立超时，请检查网络后重试。")
            ) { [repository] in
                try await repository.ensureAnonymousSession()
            }
            guard !Task.isCancelled else { return }

            async let postsRequest: [CommunityPost] = CommunityTimeout.run(
                seconds: 10,
                message: L10n.text("社区帖子加载超时，请检查网络后重试。")
            ) { [repository] in
                try await repository.fetchPosts(query: query)
            }
            async let pollsRequest: [CommunityPoll] = loadPollsIfNeeded(query: query)
            let (loadedPosts, loadedPolls) = try await (postsRequest, pollsRequest)
            guard !Task.isCancelled else { return }
            guard activeLoadID == loadID, currentQuery == query else { return }

            posts = loadedPosts
            items = CommunityFeedItemOrdering.ordered(posts: loadedPosts, polls: loadedPolls, matching: query)
            hasMoreItems = canLoadMore(after: loadedPosts, query: query)
            savePostsToCache()
            errorMessage = nil
            CommunityDiagnostics.log.info("Community feed load finished with \(loadedPosts.count) posts and \(loadedPolls.count) polls")
        } catch {
            guard !Task.isCancelled else { return }
            guard activeLoadID == loadID else { return }
            CommunityDiagnostics.log.error("Community feed load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            return
        }

        Task.detached {
            try? await Task.sleep(for: .milliseconds(800))
            await CommunitySessionManager.shared.restoreProfileIfPossible()
        }
    }

    private func loadPollsIfNeeded(query: CommunityFeedQuery) async -> [CommunityPoll] {
        guard query.includesPollsInFeed else { return [] }

        do {
            return try await CommunityTimeout.run(
                seconds: 10,
                message: L10n.text("社区投票加载超时，请检查网络后重试。")
            ) { [repository] in
                try await repository.fetchPolls(limit: query.limit)
            }
        } catch {
            CommunityDiagnostics.log.error("Community feed polls load failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func loadMoreIfNeeded() async {
        guard !isLoading, !isLoadingMore, hasMoreItems else { return }
        guard let nextQuery = nextPageQuery() else {
            hasMoreItems = false
            return
        }

        let baseQuery = currentQuery
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            async let postsRequest: [CommunityPost] = CommunityTimeout.run(
                seconds: 10,
                message: L10n.text("社区帖子加载超时，请检查网络后重试。")
            ) { [repository] in
                try await repository.fetchPosts(query: nextQuery)
            }
            async let pollsRequest: [CommunityPoll] = loadPollsIfNeeded(query: nextQuery)
            let (loadedPosts, loadedPolls) = try await (postsRequest, pollsRequest)
            guard !Task.isCancelled, currentQuery == baseQuery else { return }

            currentQuery = nextQuery
            posts = loadedPosts
            items = CommunityFeedItemOrdering.ordered(posts: loadedPosts, polls: loadedPolls, matching: nextQuery)
            hasMoreItems = canLoadMore(after: loadedPosts, query: nextQuery)
            savePostsToCache()
            errorMessage = nil
            CommunityDiagnostics.log.info("Community feed load more finished with \(loadedPosts.count) posts and \(loadedPolls.count) polls")
        } catch {
            guard !Task.isCancelled else { return }
            CommunityDiagnostics.log.error("Community feed load more failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            hasMoreItems = false
        }
    }

    private func nextPageQuery() -> CommunityFeedQuery? {
        guard !currentQuery.mode.isHot else { return nil }
        guard currentQuery.limit < Self.maximumFeedLimit else { return nil }

        return CommunityFeedQuery(
            category: currentQuery.category,
            search: currentQuery.search,
            limit: min(currentQuery.limit + Self.pageSize, Self.maximumFeedLimit),
            mode: currentQuery.mode
        )
    }

    private func canLoadMore(after loadedPosts: [CommunityPost], query: CommunityFeedQuery) -> Bool {
        !query.mode.isHot && query.limit < Self.maximumFeedLimit && loadedPosts.count >= query.limit
    }

    func toggleLike(postID: UUID) async -> String? {
        guard !activeLikePostIDs.contains(postID) else { return nil }
        activeLikePostIDs.insert(postID)
        defer { activeLikePostIDs.remove(postID) }

        do {
            let updatedPost = try await repository.togglePostLike(postID: postID)
            if let index = posts.firstIndex(where: { $0.id == postID }) {
                posts[index] = updatedPost
                replacePostInItems(updatedPost)
                savePostsToCache()
            }
            errorMessage = nil
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func toggleFavorite(postID: UUID) async -> String? {
        guard !activeFavoritePostIDs.contains(postID) else { return nil }
        activeFavoritePostIDs.insert(postID)
        defer { activeFavoritePostIDs.remove(postID) }

        do {
            let updatedPost = try await repository.togglePostFavorite(postID: postID)
            if let index = posts.firstIndex(where: { $0.id == postID }) {
                posts[index] = updatedPost
                replacePostInItems(updatedPost)
                savePostsToCache()
            }
            errorMessage = nil
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func removePost(_ post: CommunityPost) {
        posts.removeAll { $0.id == post.id }
        items.removeAll { item in
            if case .post(let existingPost) = item {
                return existingPost.id == post.id
            }
            return false
        }
        savePostsToCache()
    }

    func report(post: CommunityPost, reason: String) async -> String? {
        do {
            try await repository.reportPost(postID: post.id, reason: reason)
            removePost(post)
            errorMessage = nil
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func blockAuthor(of post: CommunityPost) async -> String? {
        do {
            try await repository.blockUser(userID: post.authorID, reason: "用户主动屏蔽")
            posts.removeAll { $0.authorID == post.authorID }
            items.removeAll { item in
                if case .post(let existingPost) = item {
                    return existingPost.authorID == post.authorID
                }
                return false
            }
            savePostsToCache()
            errorMessage = nil
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func delete(post: CommunityPost) async -> String? {
        do {
            try await repository.deletePost(postID: post.id)
            removePost(post)
            errorMessage = nil
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func votePoll(pollID: UUID, optionID: UUID) async -> CommunityPoll? {
        guard !activePollIDs.contains(pollID) else { return nil }
        activePollIDs.insert(pollID)
        defer { activePollIDs.remove(pollID) }

        do {
            let updatedPoll = try await repository.votePoll(pollID: pollID, optionID: optionID)
            replacePollInItems(updatedPoll)
            errorMessage = nil
            return updatedPoll
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func savePostsToCache() {
        cache.save(posts, query: currentQuery)
    }

    private func replacePostInItems(_ updatedPost: CommunityPost) {
        items = items.map { item in
            if case .post(let existingPost) = item, existingPost.id == updatedPost.id {
                return .post(updatedPost)
            }
            return item
        }
    }

    private func replacePollInItems(_ updatedPoll: CommunityPoll) {
        items = items.map { item in
            if case .poll(let existingPoll) = item, existingPoll.id == updatedPoll.id {
                return .poll(updatedPoll)
            }
            return item
        }
    }
}
