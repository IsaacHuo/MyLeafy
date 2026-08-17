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
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey(for: query)) else { return [] }
        do {
            return try JSONDecoder().decode([CommunityPost].self, from: data)
        } catch {
            CommunityDiagnostics.log.error("Community feed cache decode failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func save(_ posts: [CommunityPost], query: CommunityFeedQuery) {
        guard let data = try? JSONEncoder().encode(posts) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheKey(for: query))
    }

    static func cacheKey(for query: CommunityFeedQuery) -> String {
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
    @Published private(set) var isLoadingPolls = false
    @Published private(set) var hasMoreItems = true
    @Published private(set) var activeLikePostIDs: Set<UUID> = []
    @Published private(set) var activeFavoritePostIDs: Set<UUID> = []
    @Published private(set) var activePollIDs: Set<UUID> = []
    @Published var errorMessage: String?
    @Published private(set) var pollErrorMessage: String?

    private static let pageSize = 20
    private static let maximumFeedLimit = 50

    private var currentQuery = CommunityFeedQuery.default
    private var activeLoadID: UUID?
    private var activePollRetryID: UUID?
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
        guard !CommunityDiagnosticsOptions.disablesFeedLoad else {
            CommunityDiagnostics.log.info("CommunityFeedViewModel.load skipped by diagnostics")
            isLoading = false
            isLoadingMore = false
            hasMoreItems = false
            errorMessage = nil
            return
        }

        let loadID = UUID()
        activeLoadID = loadID

        let didChangeQuery = currentQuery != query
        currentQuery = query
        isLoadingMore = false
        hasMoreItems = true
        if didChangeQuery {
            posts = []
            items = []
            pollErrorMessage = nil
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
        let signpostState = LeafyPerformanceSignposter.community.beginInterval("feed-refresh")
        defer { LeafyPerformanceSignposter.community.endInterval("feed-refresh", signpostState) }
        CommunityDiagnostics.log.info("Community feed load started")

        isLoading = true
        activePollRetryID = nil
        isLoadingPolls = query.includesPollsInFeed
        pollErrorMessage = nil
        defer {
            if activeLoadID == loadID {
                isLoading = false
                isLoadingPolls = false
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

            async let postsRequest: [CommunityPost] = loadPostsIfNeeded(query: query)
            async let pollsRequest: [CommunityPoll] = loadPollsIfNeeded(query: query)
            let loadedPosts = try await postsRequest
            let loadedPolls: [CommunityPoll]
            do {
                loadedPolls = try await pollsRequest
            } catch {
                guard !Task.isCancelled else { return }
                guard activeLoadID == loadID, currentQuery == query else { return }
                pollErrorMessage = L10n.text("社区投票加载失败，请重试。")
                CommunityDiagnostics.log.error("Community feed polls load failed: \(error.localizedDescription, privacy: .public)")
                loadedPolls = []
            }
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
            errorMessage = L10n.text("社区内容加载失败，请重试。")
            return
        }

        Task.detached {
            try? await Task.sleep(for: .milliseconds(800))
            await CommunitySessionManager.shared.restoreProfileIfPossible()
        }
    }

    private func loadPollsIfNeeded(query: CommunityFeedQuery) async throws -> [CommunityPoll] {
        guard query.includesPollsInFeed else { return [] }

        return try await CommunityTimeout.run(
            seconds: 10,
            message: L10n.text("社区投票加载超时，请检查网络后重试。")
        ) { [repository] in
            try await repository.fetchPolls(limit: query.limit)
        }
    }

    func retryPolls() async {
        guard currentQuery.includesPollsInFeed, !isLoadingPolls else { return }

        let query = currentQuery
        let loadID = activeLoadID
        let retryID = UUID()
        activePollRetryID = retryID
        isLoadingPolls = true
        pollErrorMessage = nil
        defer {
            if activePollRetryID == retryID {
                activePollRetryID = nil
                isLoadingPolls = false
            }
        }

        do {
            let loadedPolls = try await loadPollsIfNeeded(query: query)
            guard !Task.isCancelled, activeLoadID == loadID, currentQuery == query else { return }
            items = CommunityFeedItemOrdering.ordered(posts: posts, polls: loadedPolls, matching: query)
        } catch {
            guard !Task.isCancelled, activeLoadID == loadID, currentQuery == query else { return }
            CommunityDiagnostics.log.error("Community feed polls retry failed: \(error.localizedDescription, privacy: .public)")
            pollErrorMessage = L10n.text("社区投票加载失败，请重试。")
        }
    }

    private func loadPostsIfNeeded(query: CommunityFeedQuery) async throws -> [CommunityPost] {
        guard query.includesPostsInFeed else { return [] }

        return try await CommunityTimeout.run(
            seconds: 10,
            message: L10n.text("社区帖子加载超时，请检查网络后重试。")
        ) { [repository] in
            try await repository.fetchPosts(query: query)
        }
    }

    func loadMoreIfNeeded() async {
        guard !CommunityDiagnosticsOptions.disablesFeedLoad else {
            CommunityDiagnostics.log.info("CommunityFeedViewModel.loadMore skipped by diagnostics")
            hasMoreItems = false
            return
        }
        guard !isLoading, !isLoadingMore, hasMoreItems else { return }
        guard let nextQuery = nextPageQuery() else {
            hasMoreItems = false
            return
        }

        let baseQuery = currentQuery
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            async let postsRequest: [CommunityPost] = loadPostsIfNeeded(query: nextQuery)
            async let pollsRequest: [CommunityPoll] = loadPollsIfNeeded(query: nextQuery)
            let loadedPosts = try await postsRequest
            let loadedPolls: [CommunityPoll]
            let didLoadPolls: Bool
            let existingPolls = items.compactMap { item -> CommunityPoll? in
                guard case .poll(let poll) = item else { return nil }
                return poll
            }
            do {
                loadedPolls = try await pollsRequest
                didLoadPolls = true
            } catch {
                guard !Task.isCancelled, currentQuery == baseQuery else { return }
                CommunityDiagnostics.log.error("Community feed polls load more failed: \(error.localizedDescription, privacy: .public)")
                pollErrorMessage = L10n.text("社区投票加载失败，请重试。")
                loadedPolls = existingPolls
                didLoadPolls = false
            }
            guard !Task.isCancelled, currentQuery == baseQuery else { return }

            currentQuery = nextQuery
            if didLoadPolls {
                pollErrorMessage = nil
            }
            posts = loadedPosts
            items = CommunityFeedItemOrdering.ordered(posts: loadedPosts, polls: loadedPolls, matching: nextQuery)
            hasMoreItems = canLoadMore(after: loadedPosts, query: nextQuery)
            savePostsToCache()
            errorMessage = nil
            CommunityDiagnostics.log.info("Community feed load more finished with \(loadedPosts.count) posts and \(loadedPolls.count) polls")
        } catch {
            guard !Task.isCancelled else { return }
            CommunityDiagnostics.log.error("Community feed load more failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = L10n.text("社区内容加载失败，请重试。")
            hasMoreItems = false
        }
    }

    private func nextPageQuery() -> CommunityFeedQuery? {
        guard !currentQuery.mode.isHot, currentQuery.includesPostsInFeed else { return nil }
        guard currentQuery.limit < Self.maximumFeedLimit else { return nil }

        return CommunityFeedQuery(
            category: currentQuery.category,
            search: currentQuery.search,
            limit: min(currentQuery.limit + Self.pageSize, Self.maximumFeedLimit),
            mode: currentQuery.mode,
            contentFilter: currentQuery.contentFilter
        )
    }

    private func canLoadMore(after loadedPosts: [CommunityPost], query: CommunityFeedQuery) -> Bool {
        guard query.includesPostsInFeed else { return false }
        return !query.mode.isHot && query.limit < Self.maximumFeedLimit && loadedPosts.count >= query.limit
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
            return actionErrorMessage(for: error)
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
            return actionErrorMessage(for: error)
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
            return actionErrorMessage(for: error)
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
            return actionErrorMessage(for: error)
        }
    }

    func delete(post: CommunityPost) async -> String? {
        do {
            try await repository.deletePost(postID: post.id)
            removePost(post)
            errorMessage = nil
            return nil
        } catch {
            return actionErrorMessage(for: error)
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
            errorMessage = actionErrorMessage(for: error)
            return nil
        }
    }

    private func actionErrorMessage(for error: Error) -> String {
        if let serviceError = error as? CommunityServiceError {
            if case .edgeFunctionRejected = serviceError {
                return L10n.text("社区操作失败，请稍后重试。")
            }
            return L10n.text(serviceError.localizedDescription)
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return L10n.text("网络连接失败，请检查网络后重试。")
        }
        return L10n.text("社区操作失败，请稍后重试。")
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
