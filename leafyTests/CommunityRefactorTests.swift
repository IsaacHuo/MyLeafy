import XCTest
import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers
import Supabase
import SwiftData
@testable import Leafy

extension PerformanceRefactorTests {
    func testCommunityTimeoutReturnsCompletedOperation() async throws {
        let value = try await CommunityTimeout.run(seconds: 1, message: "超时") {
            42
        }

        XCTAssertEqual(value, 42)
    }

    func testCommunityTimeoutThrowsConfiguredTimeout() async {
        do {
            _ = try await CommunityTimeout.run(seconds: 0.01, message: "测试超时") {
                try await Task.sleep(for: .seconds(1))
                return 42
            }
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error.localizedDescription, "测试超时")
        }
    }

    func testCommunityTimeoutPropagatesCancellation() async {
        let task = Task {
            try await CommunityTimeout.run(seconds: 10, message: "超时") {
                try await Task.sleep(for: .seconds(10))
                return 42
            }
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    @MainActor
    func testCommunityFeedInitialLoadFetchesAndCachesPosts() async {
        let post = makeCommunityPost(title: "初始帖子")
        let repository = FakeCommunityRepository(postResponses: [[post]])
        let cache = FakeCommunityFeedCache()
        let viewModel = CommunityFeedViewModel(repository: repository, cache: cache)

        await viewModel.load()

        XCTAssertEqual(viewModel.posts, [post])
        XCTAssertEqual(cache.savedPostSnapshots.last, [post])
    }

    @MainActor
    func testCommunityFeedCacheFirstKeepsCachedPostsDuringRefresh() async {
        let cachedPost = makeCommunityPost(title: "缓存帖子")
        let freshPost = makeCommunityPost(title: "最新帖子")
        let repository = FakeCommunityRepository()
        let cache = FakeCommunityFeedCache(loadedPosts: [cachedPost])
        let viewModel = CommunityFeedViewModel(repository: repository, cache: cache)

        await repository.suspendFetches()
        let loadTask = Task {
            await viewModel.load()
        }
        await repository.waitForSuspendedFetch()

        XCTAssertEqual(viewModel.posts, [cachedPost])

        await repository.resumeSuspendedFetch(with: [freshPost])
        await loadTask.value

        XCTAssertEqual(viewModel.posts, [freshPost])
        XCTAssertEqual(cache.savedPostSnapshots.last, [freshPost])
    }

    @MainActor
    func testCommunityFeedRefreshFailurePreservesExistingPosts() async {
        let post = makeCommunityPost(title: "保留帖子")
        let repository = FakeCommunityRepository(postResponses: [[post]])
        let cache = FakeCommunityFeedCache()
        let viewModel = CommunityFeedViewModel(repository: repository, cache: cache)

        await viewModel.load()
        await repository.setFetchError(.failure("刷新失败"))
        await viewModel.load(mode: .refresh)

        XCTAssertEqual(viewModel.posts, [post])
        XCTAssertEqual(viewModel.errorMessage, "刷新失败")
    }

    @MainActor
    func testCommunityFeedInitialFailureSurfacesRecoverableError() async {
        let repository = FakeCommunityRepository()
        let viewModel = CommunityFeedViewModel(repository: repository, cache: FakeCommunityFeedCache())

        await repository.setFetchError(.failure("初次加载失败"))
        await viewModel.load()

        XCTAssertTrue(viewModel.posts.isEmpty)
        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, "初次加载失败")
    }

    func testCommunityFeedCacheDropsCorruptPayload() {
        let query = CommunityFeedQuery(search: "corrupt-\(UUID().uuidString)")
        let key = CommunityFeedCache.cacheKey(for: query)
        UserDefaults.standard.set(Data("not-json".utf8), forKey: key)
        defer {
            UserDefaults.standard.removeObject(forKey: key)
        }

        XCTAssertEqual(CommunityFeedCache().load(query: query), [])
    }

    @MainActor
    func testCommunityFeedMutationsUpdatePostsAndCache() async {
        let authorID = UUID()
        let firstPin = makeCommunityPostPin(postID: UUID(), priority: 7)
        let firstPost = makeCommunityPost(id: firstPin.postID, authorID: authorID, title: "第一条", pin: firstPin)
        let secondPost = makeCommunityPost(title: "第二条")
        let likedFirstPost = makeCommunityPost(
            id: firstPost.id,
            authorID: authorID,
            title: "第一条",
            likeCount: 1,
            viewerHasLiked: true,
            pin: firstPin
        )
        let repository = FakeCommunityRepository(postResponses: [[firstPost, secondPost]])
        let cache = FakeCommunityFeedCache()
        let viewModel = CommunityFeedViewModel(repository: repository, cache: cache)

        await viewModel.load()
        await repository.setLikeResponse(likedFirstPost, for: firstPost.id)

        let likeError = await viewModel.toggleLike(postID: firstPost.id)
        XCTAssertNil(likeError)
        XCTAssertEqual(viewModel.posts, [likedFirstPost, secondPost])
        XCTAssertEqual(cache.savedPostSnapshots.last, [likedFirstPost, secondPost])

        let deleteError = await viewModel.delete(post: secondPost)
        XCTAssertNil(deleteError)
        XCTAssertEqual(viewModel.posts, [likedFirstPost])
        XCTAssertEqual(cache.savedPostSnapshots.last, [likedFirstPost])

        let blockError = await viewModel.blockAuthor(of: likedFirstPost)
        XCTAssertNil(blockError)
        XCTAssertTrue(viewModel.posts.isEmpty)
        XCTAssertEqual(cache.savedPostSnapshots.last, [])
    }

    @MainActor
    func testCommunityFeedFavoriteMutationUpdatesPostsAndCache() async {
        let pin = makeCommunityPostPin(postID: UUID(), priority: 3)
        let post = makeCommunityPost(id: pin.postID, title: "待收藏", pin: pin)
        let favoritedPost = makeCommunityPost(
            id: post.id,
            authorID: post.authorID,
            title: "待收藏",
            viewerHasFavorited: true,
            pin: pin
        )
        let repository = FakeCommunityRepository(postResponses: [[post]])
        let cache = FakeCommunityFeedCache()
        let viewModel = CommunityFeedViewModel(repository: repository, cache: cache)

        await viewModel.load()
        await repository.setFavoriteResponse(favoritedPost, for: post.id)

        let favoriteError = await viewModel.toggleFavorite(postID: post.id)
        XCTAssertNil(favoriteError)
        XCTAssertEqual(viewModel.posts, [favoritedPost])
        XCTAssertEqual(viewModel.posts.first?.pin, pin)
        XCTAssertEqual(cache.savedPostSnapshots.last, [favoritedPost])
    }

    @MainActor
    func testCommunityFeedCacheIsScopedByQuery() async {
        let cachedDefaultPost = makeCommunityPost(title: "默认缓存")
        let categoryPost = makeCommunityPost(title: "分类帖子", category: "问答互助")
        let query = CommunityFeedQuery(category: "问答互助")
        let repository = FakeCommunityRepository(postResponses: [[categoryPost]])
        let cache = FakeCommunityFeedCache(loadedPosts: [cachedDefaultPost])
        let viewModel = CommunityFeedViewModel(repository: repository, cache: cache)

        await viewModel.load(query: query)

        XCTAssertEqual(viewModel.posts, [categoryPost])
        XCTAssertEqual(cache.savedPostSnapshots.last, [categoryPost])
    }

    @MainActor
    func testCommunityFeedDefaultQueryIncludesPublishedPollItems() async {
        let post = makeCommunityPost(title: "普通帖子", createdAt: "2026-05-14T00:00:00Z")
        let publishedPoll = makeCommunityPoll(question: "大家想在哪里自习？", createdAt: "2026-05-15T00:00:00Z")
        let pendingPoll = makeCommunityPoll(
            question: "待审核投票",
            status: "pending_review",
            createdAt: "2026-05-16T00:00:00Z"
        )
        let repository = FakeCommunityRepository(
            postResponses: [[post]],
            pollResponses: [[pendingPoll, publishedPoll]]
        )
        let viewModel = CommunityFeedViewModel(repository: repository, cache: FakeCommunityFeedCache())

        await viewModel.load()

        XCTAssertEqual(viewModel.posts, [post])
        XCTAssertEqual(viewModel.items, [.poll(publishedPoll), .post(post)])
    }

    @MainActor
    func testCommunityFeedKeepsPublishedPollWhileDeletionIsPending() async {
        let poll = makeCommunityPoll(
            question: "删除审核中仍展示吗？",
            deletionStatus: "pending"
        )
        let repository = FakeCommunityRepository(postResponses: [[]], pollResponses: [[poll]])
        let viewModel = CommunityFeedViewModel(repository: repository, cache: FakeCommunityFeedCache())

        await viewModel.load()

        XCTAssertEqual(viewModel.items, [.poll(poll)])
    }

    @MainActor
    func testCommunityFeedCategoryQueryDoesNotFetchPolls() async {
        let post = makeCommunityPost(title: "分类帖子", category: "问答互助")
        let poll = makeCommunityPoll(question: "不应混入分类")
        let repository = FakeCommunityRepository(postResponses: [[post]], pollResponses: [[poll]])
        let viewModel = CommunityFeedViewModel(repository: repository, cache: FakeCommunityFeedCache())

        await viewModel.load(query: CommunityFeedQuery(category: "问答互助"))

        let fetchedPollLimits = await repository.fetchedPollLimits()
        XCTAssertEqual(viewModel.items, [.post(post)])
        XCTAssertEqual(fetchedPollLimits, [])
    }

    @MainActor
    func testCommunityFeedPollVoteUpdatesFeedItem() async {
        let pollID = UUID()
        let optionID = UUID()
        let initialOption = makeCommunityPollOption(id: optionID, pollID: pollID, text: "图书馆")
        let updatedOption = makeCommunityPollOption(id: optionID, pollID: pollID, text: "图书馆", voteCount: 1)
        let poll = makeCommunityPoll(id: pollID, question: "今天去哪自习？", options: [initialOption])
        let updatedPoll = makeCommunityPoll(
            id: pollID,
            question: "今天去哪自习？",
            totalVoteCount: 1,
            viewerOptionID: optionID,
            options: [updatedOption]
        )
        let repository = FakeCommunityRepository(postResponses: [[]], pollResponses: [[poll]])
        await repository.setVotePollResponse(updatedPoll, for: pollID)
        let viewModel = CommunityFeedViewModel(repository: repository, cache: FakeCommunityFeedCache())

        await viewModel.load()
        let result = await viewModel.votePoll(pollID: pollID, optionID: optionID)

        XCTAssertEqual(result, updatedPoll)
        XCTAssertEqual(viewModel.items, [.poll(updatedPoll)])
    }

    func testCommunityFeedHotQueryHasSeparateCacheKeyAndFixedLimit() {
        let hotQuery = CommunityFeedQuery(category: "问答互助", search: "图书馆", limit: 50, mode: .hot(days: 7))

        XCTAssertNil(hotQuery.category)
        XCTAssertNil(hotQuery.search)
        XCTAssertEqual(hotQuery.limit, 10)
        XCTAssertNotEqual(hotQuery.cacheKey, CommunityFeedQuery.default.cacheKey)
        XCTAssertNotEqual(hotQuery.cacheKey, CommunityFeedQuery(category: "问答互助").cacheKey)
        XCTAssertNotEqual(hotQuery.cacheKey, CommunityFeedQuery(search: "图书馆").cacheKey)
    }

    @MainActor
    func testCommunityFeedPollFilterSkipsPostsAndOnlyReturnsPublishedPolls() async {
        let publishedPoll = makeCommunityPoll(question: "去哪里自习？")
        let pendingPoll = makeCommunityPoll(question: "待审核", status: "pending_review")
        let repository = FakeCommunityRepository(
            postResponses: [[makeCommunityPost(title: "不应请求")]],
            pollResponses: [[pendingPoll, publishedPoll]]
        )
        let viewModel = CommunityFeedViewModel(repository: repository, cache: FakeCommunityFeedCache())
        let query = CommunityFeedQuery(contentFilter: .polls)

        await viewModel.load(query: query)

        let fetchedPostQueries = await repository.fetchedPostQueries()
        XCTAssertEqual(fetchedPostQueries, [])
        XCTAssertEqual(viewModel.posts, [])
        XCTAssertEqual(viewModel.items, [.poll(publishedPoll)])
        XCTAssertFalse(viewModel.hasMoreItems)
        XCTAssertNotEqual(query.cacheKey, CommunityFeedQuery.default.cacheKey)
    }

    func testCommunityFeedOrderingPrioritizesPinnedPosts() {
        let lowID = UUID()
        let highID = UUID()
        let normalPost = makeCommunityPost(title: "普通", category: "学习交流")
        let lowPinnedPost = makeCommunityPost(
            id: lowID,
            title: "低优先级置顶",
            category: "学习交流",
            pin: makeCommunityPostPin(postID: lowID, priority: 1, startsAt: "2026-05-15T00:00:00Z")
        )
        let highPinnedPost = makeCommunityPost(
            id: highID,
            title: "高优先级置顶",
            category: "学习交流",
            pin: makeCommunityPostPin(postID: highID, priority: 10, startsAt: "2026-05-14T00:00:00Z")
        )

        let orderedPosts = CommunityFeedOrdering.ordered(
            [normalPost, lowPinnedPost, highPinnedPost],
            matching: .default
        )

        XCTAssertEqual(orderedPosts.map(\.id), [highPinnedPost.id, lowPinnedPost.id, normalPost.id])
    }

    func testCommunityFeedOrderingFiltersCategoryAndSearch() {
        let globalID = UUID()
        let matchingPost = makeCommunityPost(
            id: globalID,
            title: "图书馆座位提醒",
            category: "问答互助",
            pin: makeCommunityPostPin(postID: globalID, priority: 5)
        )
        let unrelatedPinnedID = UUID()
        let unrelatedPinnedPost = makeCommunityPost(
            id: unrelatedPinnedID,
            title: "食堂窗口推荐",
            category: "校园生活",
            pin: makeCommunityPostPin(postID: unrelatedPinnedID, priority: 9)
        )

        let orderedPosts = CommunityFeedOrdering.ordered(
            [unrelatedPinnedPost, matchingPost],
            matching: CommunityFeedQuery(category: "问答互助", search: "图书馆")
        )

        XCTAssertEqual(orderedPosts, [matchingPost])
    }

    func testCommunityFeedOrderingHotFiltersWindowAndSortsByScore() {
        let now = ISO8601DateFormatter().date(from: "2026-05-27T12:00:00Z")!
        let highScorePost = makeCommunityPost(
            title: "高分",
            commentCount: 3,
            likeCount: 2,
            status: "published",
            createdAt: "2026-05-26T00:00:00Z"
        )
        let tieNewerPost = makeCommunityPost(
            title: "同分较新",
            commentCount: 1,
            likeCount: 2,
            status: "published",
            createdAt: "2026-05-27T00:00:00Z"
        )
        let tieOlderPost = makeCommunityPost(
            title: "同分较旧",
            commentCount: 1,
            likeCount: 2,
            status: "published",
            createdAt: "2026-05-25T00:00:00Z"
        )
        let oldPost = makeCommunityPost(
            title: "过期",
            commentCount: 100,
            likeCount: 100,
            status: "published",
            createdAt: "2026-05-10T00:00:00Z"
        )
        let hiddenPost = makeCommunityPost(
            title: "不可见",
            commentCount: 100,
            likeCount: 100,
            status: "hidden",
            createdAt: "2026-05-27T00:00:00Z"
        )

        let orderedPosts = CommunityFeedOrdering.hot(
            [tieOlderPost, oldPost, hiddenPost, tieNewerPost, highScorePost],
            days: 7,
            limit: 10,
            now: now
        )

        XCTAssertEqual(orderedPosts.map(\.id), [highScorePost.id, tieNewerPost.id, tieOlderPost.id])
    }

    func testCommunityPostPinActiveWindow() {
        let activePin = makeCommunityPostPin(postID: UUID(), endsAt: "2099-01-01T00:00:00Z")
        let expiredPin = makeCommunityPostPin(postID: UUID(), endsAt: "2020-01-01T00:00:00Z")
        let futurePin = makeCommunityPostPin(postID: UUID(), startsAt: "2099-01-01T00:00:00Z")
        let inactivePin = makeCommunityPostPin(postID: UUID(), status: "inactive")

        XCTAssertTrue(activePin.isCurrentlyActive)
        XCTAssertFalse(expiredPin.isCurrentlyActive)
        XCTAssertFalse(futurePin.isCurrentlyActive)
        XCTAssertFalse(inactivePin.isCurrentlyActive)
    }

    func testCommunityPostDeepLinkParsesSupportedURLs() throws {
        let postID = UUID()
        let universalLink = URL(string: "https://myleafy.space/share/community/post/\(postID.uuidString)")!
        let customScheme = URL(string: "leafy://community-post?id=\(postID.uuidString)")!

        XCTAssertEqual(CommunityPostDeepLink(url: universalLink)?.postID, postID)
        XCTAssertEqual(CommunityPostDeepLink(url: customScheme)?.postID, postID)
        XCTAssertNil(CommunityPostDeepLink(url: URL(string: "https://myleafy.space/share/community/post/not-a-uuid")!))
    }

    func testRootTabVisibleCasesHideCommunityWhenDisabled() {
        XCTAssertEqual(RootTab.visibleCases(isCommunityEnabled: true), [.timetable, .community, .schedule, .academics, .profile])
        XCTAssertEqual(RootTab.visibleCases(isCommunityEnabled: false), [.timetable, .schedule, .academics, .profile])
    }

    func testCatalogSuggestionInputKeepsTeacherNameInRepository() async throws {
        let repository = FakeCommunityRepository()
        let input = CatalogSuggestionInput(
            type: .course,
            name: "森林生态学导论",
            unit: "林学院",
            teacherName: "王老师",
            category: "公选课",
            credit: 2,
            initialStars: 4,
            note: "建议补充"
        )

        try await repository.submitCatalogSuggestion(input: input)

        let submittedSuggestions = await repository.submittedCatalogSuggestions()
        XCTAssertEqual(submittedSuggestions, [input])
        XCTAssertEqual(submittedSuggestions.first?.teacherName, "王老师")
        XCTAssertEqual(submittedSuggestions.first?.initialStars, 4)
    }

    func testFavoritedProfileListRemovesPostWhenUnfavorited() {
        let favoritedPost = makeCommunityPost(viewerHasFavorited: true)
        let otherPost = makeCommunityPost(title: "其他收藏", viewerHasFavorited: true)
        let unfavoritedPost = makeCommunityPost(
            id: favoritedPost.id,
            authorID: favoritedPost.authorID,
            viewerHasFavorited: false
        )

        let updatedPosts = ProfileCommunityPostListReducer.applyingPostChange(
            unfavoritedPost,
            to: [favoritedPost, otherPost],
            kind: .favorited
        )

        XCTAssertEqual(updatedPosts, [otherPost])
    }
}
