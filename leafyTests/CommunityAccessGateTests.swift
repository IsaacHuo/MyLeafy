import XCTest
@testable import Leafy

final class CommunityAccessGateTests: XCTestCase {
    private var previousIdentity: CampusIdentity?

    override func setUp() {
        super.setUp()
        previousIdentity = CampusIdentityStore.currentIdentity()
        CampusIdentityStore.activate(makeBJFUIdentity())
    }

    override func tearDown() {
        if let previousIdentity {
            CampusIdentityStore.activate(previousIdentity)
        } else {
            CampusIdentityStore.clear()
        }
        previousIdentity = nil
        super.tearDown()
    }

    @MainActor
    func testCommunityEntryRequiresTermsWhenNotAccepted() async {
        let session = FakeCommunitySession(currentUserID: UUID())
        let terms = FakeTermsChecker(accepted: false)
        let gate = CommunityAccessGate(sessionManager: session, termsChecker: terms)

        let result = await gate.evaluate(.communityEntry)
        let checkCount = await terms.checkCount()

        XCTAssertEqual(result, .requiresTermsAcceptance)
        XCTAssertEqual(checkCount, 1)
    }

    @MainActor
    func testPostCreationRequiresProfileBeforeTermsCheck() async {
        let session = FakeCommunitySession(currentUserID: UUID(), requiresProfileCompletion: true)
        let terms = FakeTermsChecker(accepted: false)
        let gate = CommunityAccessGate(sessionManager: session, termsChecker: terms)

        let result = await gate.evaluate(.postCreation)
        let checkCount = await terms.checkCount()

        XCTAssertEqual(result, .requiresProfileCompletion)
        XCTAssertEqual(checkCount, 0)
    }

    @MainActor
    func testPostCreationRequiresTermsAfterProfileIsComplete() async {
        let session = FakeCommunitySession(currentUserID: UUID())
        let terms = FakeTermsChecker(accepted: false)
        let gate = CommunityAccessGate(sessionManager: session, termsChecker: terms)

        let result = await gate.evaluate(.postCreation)
        let checkCount = await terms.checkCount()

        XCTAssertEqual(result, .requiresTermsAcceptance)
        XCTAssertEqual(checkCount, 1)
    }

    @MainActor
    func testProfileInteractionChecksProfileButNotTerms() async {
        let session = FakeCommunitySession(currentUserID: UUID())
        let terms = FakeTermsChecker(accepted: false)
        let gate = CommunityAccessGate(sessionManager: session, termsChecker: terms)

        let result = await gate.evaluate(.profileInteraction, forceBootstrap: true)
        let checkCount = await terms.checkCount()

        XCTAssertEqual(result, .allowed)
        XCTAssertEqual(checkCount, 0)
        XCTAssertEqual(session.bootstrapForceValues, [true])
    }

    @MainActor
    func testRatingOnlyRequiresEstablishedCommunityIdentity() async {
        let session = FakeCommunitySession(currentUserID: UUID(), requiresProfileCompletion: true)
        let terms = FakeTermsChecker(accepted: false)
        let gate = CommunityAccessGate(sessionManager: session, termsChecker: terms)

        let result = await gate.evaluate(.rating)
        let checkCount = await terms.checkCount()

        XCTAssertEqual(result, .allowed)
        XCTAssertEqual(checkCount, 0)
    }

    @MainActor
    func testBJFUPortalBypassesSchoolCommunityApproval() async {
        await withCampusIdentity(makeBJFUIdentity()) {
            let session = FakeCommunitySession(
                currentUserID: UUID(),
                bootstrapError: "社区身份初始化失败"
            )
            let terms = FakeTermsChecker(accepted: true)
            let gate = CommunityAccessGate(sessionManager: session, termsChecker: terms)

            let result = await gate.evaluate(.communityEntry)
            let checkCount = await terms.checkCount()

            XCTAssertEqual(result, .allowed)
            XCTAssertEqual(checkCount, 1)
        }
    }

    @MainActor
    func testCustomPortalRequiresSchoolCommunityApprovalBeforeTerms() async {
        await withCampusIdentity(makeCustomIdentity()) {
            let session = FakeCommunitySession(
                currentUserID: UUID(),
                communityAccessStatus: .general,
                hasApprovedCommunityAccess: false
            )
            let terms = FakeTermsChecker(accepted: true)
            let gate = CommunityAccessGate(sessionManager: session, termsChecker: terms)

            let result = await gate.evaluate(.communityEntry)
            let checkCount = await terms.checkCount()

            XCTAssertEqual(result, .failed("当前为通用模式，社区功能暂不开放。请先在社区页提交学校申请。"))
            XCTAssertEqual(checkCount, 0)
        }
    }

    @MainActor
    func testBootstrapFailuresAndMissingIdentityReturnFailures() async {
        let failedSession = FakeCommunitySession(
            currentUserID: UUID(),
            bootstrapError: "社区身份初始化失败"
        )
        let failedGate = CommunityAccessGate(
            sessionManager: failedSession,
            termsChecker: FakeTermsChecker(accepted: true)
        )

        let missingSession = FakeCommunitySession(currentUserID: nil)
        let missingGate = CommunityAccessGate(
            sessionManager: missingSession,
            termsChecker: FakeTermsChecker(accepted: true)
        )

        var failedResult: CommunityAccessResult?
        await withCampusIdentity(makeCustomIdentity()) {
            failedResult = await failedGate.evaluate(.communityEntry)
        }
        let missingResult = await missingGate.evaluate(.communityEntry)

        XCTAssertEqual(failedResult, .failed("社区身份初始化失败"))
        XCTAssertEqual(
            missingResult,
            .failed(CommunityServiceError.missingAuthenticatedUser.localizedDescription)
        )
    }

    @MainActor
    func testCommunityFeedIgnoresStaleLoadAfterQueryChanges() async {
        let repository = SuspendingCommunityRepository()
        let viewModel = CommunityFeedViewModel(repository: repository, cache: EmptyCommunityFeedCache())
        let defaultPost = makeTestCommunityPost(title: "默认帖子")
        let searchPost = makeTestCommunityPost(title: "搜索帖子")
        let searchQuery = CommunityFeedQuery(search: "图书馆")

        let defaultLoad = Task { @MainActor in
            await viewModel.load(query: .default)
        }
        await repository.waitForFetch(query: .default)

        let searchLoad = Task { @MainActor in
            await viewModel.load(query: searchQuery)
        }
        await repository.waitForFetch(query: searchQuery)

        await repository.resumeFetch(query: searchQuery, posts: [searchPost])
        await searchLoad.value
        XCTAssertEqual(viewModel.posts, [searchPost])

        await repository.resumeFetch(query: .default, posts: [defaultPost])
        await defaultLoad.value
        XCTAssertEqual(viewModel.posts, [searchPost])
    }

    func testSearchDebounceCanBeCancelled() async {
        let query = CommunityFeedQuery(search: "图书馆")
        let task = Task {
            await CommunityFeedSearchDebounce.waitIfNeeded(for: query)
        }

        task.cancel()
        let completed = await task.value

        XCTAssertFalse(completed)
    }

    func testPollInputValidationRequiresQuestionAndEnoughOptions() {
        let missingQuestion = CreatePollInput(question: " ", detail: nil, options: ["A", "B"], closesAt: nil)
        let missingOption = CreatePollInput(question: "去哪自习？", detail: nil, options: ["A", " "], closesAt: nil)
        let valid = CreatePollInput(question: "去哪自习？", detail: "今晚", options: ["图书馆", "教室"], closesAt: nil)

        XCTAssertEqual(missingQuestion.validationError, "投票问题不能为空。")
        XCTAssertEqual(missingOption.validationError, "至少需要 2 个选项。")
        XCTAssertNil(valid.validationError)
        XCTAssertEqual(valid.normalizedOptions, ["图书馆", "教室"])
    }

    func testPollOptionPercentageAndClosedState() {
        let option = CommunityPollOption(
            id: UUID(),
            pollID: UUID(),
            text: "图书馆",
            sortOrder: 0,
            voteCount: 1,
            createdAt: "2026-05-28T00:00:00Z"
        )
        let poll = makeTestCommunityPoll(
            options: [option],
            totalVoteCount: 4,
            closesAt: "2026-05-27T00:00:00Z"
        )

        XCTAssertEqual(option.percentageText(totalVotes: poll.totalVoteCount), "25%")
        XCTAssertTrue(poll.isClosed)
        XCTAssertFalse(poll.canVote)
        XCTAssertTrue(poll.shouldRevealResults)
    }

    func testPendingPollAwaitsReviewAndCannotBeVoted() {
        let poll = makeTestCommunityPoll(status: "pending_review")

        XCTAssertTrue(poll.isPendingReview)
        XCTAssertEqual(poll.statusText, "待审核")
        XCTAssertTrue(poll.isClosed)
        XCTAssertFalse(poll.canVote)
        XCTAssertTrue(poll.shouldRevealResults)
    }

    func testPollLifecycleStatusTextIncludesDeletionReviewStates() {
        XCTAssertEqual(makeTestCommunityPoll(status: "pending_review").statusText, "待审核")
        XCTAssertEqual(makeTestCommunityPoll().statusText, "投票中")
        XCTAssertEqual(makeTestCommunityPoll(closesAt: "2026-05-27T00:00:00Z").statusText, "已截止")
        XCTAssertEqual(makeTestCommunityPoll(status: "deleted", deletionStatus: "approved").statusText, "已删除")

        let deletionPending = makeTestCommunityPoll(deletionStatus: "pending")
        XCTAssertEqual(deletionPending.statusText, "删除待审核")
        XCTAssertTrue(deletionPending.isDeletionPending)
        XCTAssertFalse(deletionPending.canRequestDeletion)

        let deletionRejected = makeTestCommunityPoll(deletionStatus: "rejected")
        XCTAssertEqual(deletionRejected.statusText, "删除被拒")
        XCTAssertTrue(deletionRejected.canRequestDeletion)
    }

    func testActivePollHidesResultsUntilViewerVotes() {
        let pendingVotePoll = makeTestCommunityPoll(totalVoteCount: 4)
        let votedPoll = makeTestCommunityPoll(totalVoteCount: 4, viewerOptionID: pendingVotePoll.options.first?.id)

        XCTAssertFalse(pendingVotePoll.shouldRevealResults)
        XCTAssertTrue(votedPoll.shouldRevealResults)
    }

    @MainActor
    func testPollViewModelCreatesAndUpdatesPolls() async {
        let repository = FakePollRepository()
        let viewModel = CommunityPollsViewModel(repository: repository)
        let poll = makeTestCommunityPoll(question: "去哪自习？")
        await repository.setPolls([poll])

        await viewModel.load()
        XCTAssertEqual(viewModel.polls, [poll])

        guard let secondOption = poll.options.dropFirst().first else {
            XCTFail("Expected test poll options")
            return
        }

        let voted = await viewModel.vote(pollID: poll.id, optionID: secondOption.id)
        XCTAssertTrue(voted)
        XCTAssertEqual(viewModel.polls.first?.viewerOptionID, secondOption.id)
        XCTAssertEqual(viewModel.polls.first?.totalVoteCount, 1)

        let created = await viewModel.createPoll(input: CreatePollInput(
            question: "晚饭吃什么？",
            detail: nil,
            options: ["米饭", "面"],
            closesAt: nil
        ))
        XCTAssertTrue(created)
        XCTAssertEqual(viewModel.polls.first?.question, "晚饭吃什么？")
        XCTAssertEqual(viewModel.polls.first?.status, "pending_review")
    }

    @MainActor
    func testPollViewModelRequestDeletionKeepsPollAndMarksPending() async {
        let repository = FakePollRepository()
        let viewModel = CommunityPollsViewModel(repository: repository)
        let poll = makeTestCommunityPoll(question: "要不要延长投票？")
        await repository.setPolls([poll])

        await viewModel.load()
        let requested = await viewModel.requestDeletion(poll: poll, reason: "重复发布")

        XCTAssertTrue(requested)
        XCTAssertEqual(viewModel.polls.count, 1)
        XCTAssertEqual(viewModel.polls.first?.id, poll.id)
        XCTAssertEqual(viewModel.polls.first?.status, "published")
        XCTAssertEqual(viewModel.polls.first?.deletionStatus, "pending")
        XCTAssertEqual(viewModel.polls.first?.deletionReason, "重复发布")
    }

    @MainActor
    func testPollViewModelRejectsDuplicateDeletionRequest() async {
        let repository = FakePollRepository()
        let viewModel = CommunityPollsViewModel(repository: repository)
        let poll = makeTestCommunityPoll(deletionStatus: "pending")
        await repository.setPolls([poll])

        await viewModel.load()
        let requested = await viewModel.requestDeletion(poll: poll, reason: nil)

        XCTAssertFalse(requested)
        XCTAssertEqual(viewModel.polls.first, poll)
        XCTAssertEqual(viewModel.errorMessage, "删除申请审核中")
    }

    @MainActor
    func testPollViewModelSurfacesClosedPollFailure() async {
        let repository = FakePollRepository()
        let viewModel = CommunityPollsViewModel(repository: repository)
        let option = CommunityPollOption(
            id: UUID(),
            pollID: UUID(),
            text: "图书馆",
            sortOrder: 0,
            voteCount: 0,
            createdAt: "2026-05-28T00:00:00Z"
        )
        let poll = makeTestCommunityPoll(
            options: [option],
            closesAt: "2026-05-27T00:00:00Z"
        )
        await repository.setPolls([poll])
        await viewModel.load()

        let voted = await viewModel.vote(pollID: poll.id, optionID: option.id)

        XCTAssertFalse(voted)
        XCTAssertEqual(viewModel.errorMessage, CommunityServiceError.pollClosed.localizedDescription)
    }
}

@MainActor
private func withCampusIdentity(
    _ identity: CampusIdentity,
    operation: () async -> Void
) async {
    let previousIdentity = CampusIdentityStore.currentIdentity()
    CampusIdentityStore.activate(identity)
    await operation()
    if let previousIdentity {
        CampusIdentityStore.activate(previousIdentity)
    } else {
        CampusIdentityStore.clear()
    }
}

private func makeBJFUIdentity() -> CampusIdentity {
    CampusIdentity(
        campusID: .bjfu,
        eduID: "20260001",
        displayName: "北林同学",
        portal: .undergraduate
    )
}

private func makeCustomIdentity() -> CampusIdentity {
    CampusIdentity(
        campusID: .custom,
        eduID: UUID().uuidString,
        displayName: "user@example.com",
        portal: .undergraduate,
        kind: .customSupabase
    )
}

@MainActor
private final class FakeCommunitySession: CommunitySessionManaging {
    var currentUserID: UUID?
    var bootstrapError: String?
    var requiresProfileCompletion: Bool
    var communityAccessStatus: CommunityAccessStatus = .general
    var hasApprovedCommunityAccess: Bool = false
    private(set) var bootstrapForceValues: [Bool] = []

    init(
        currentUserID: UUID?,
        bootstrapError: String? = nil,
        requiresProfileCompletion: Bool = false,
        communityAccessStatus: CommunityAccessStatus = .general,
        hasApprovedCommunityAccess: Bool = false
    ) {
        self.currentUserID = currentUserID
        self.bootstrapError = bootstrapError
        self.requiresProfileCompletion = requiresProfileCompletion
        self.communityAccessStatus = communityAccessStatus
        self.hasApprovedCommunityAccess = hasApprovedCommunityAccess
    }

    func restoreProfileIfPossible() async {}

    func bootstrapCommunityUser(force: Bool) async {
        bootstrapForceValues.append(force)
    }
}

private actor FakeTermsChecker: CommunityTermsChecking {
    private let accepted: Bool
    private var checks = 0

    init(accepted: Bool) {
        self.accepted = accepted
    }

    func hasAcceptedCurrentTerms() async throws -> Bool {
        checks += 1
        return accepted
    }

    func checkCount() -> Int {
        checks
    }
}

private struct EmptyCommunityFeedCache: CommunityFeedCaching {
    func load(query: CommunityFeedQuery) -> [CommunityPost] {
        []
    }

    func save(_ posts: [CommunityPost], query: CommunityFeedQuery) {}
}

private actor SuspendingCommunityRepository: CommunityRepository {
    private var fetchContinuations: [String: CheckedContinuation<[CommunityPost], Error>] = [:]
    private var fetchWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    func waitForFetch(query: CommunityFeedQuery) async {
        let key = query.cacheKey
        if fetchContinuations[key] != nil { return }

        await withCheckedContinuation { continuation in
            fetchWaiters[key, default: []].append(continuation)
        }
    }

    func resumeFetch(query: CommunityFeedQuery, posts: [CommunityPost]) {
        let key = query.cacheKey
        let continuation = fetchContinuations.removeValue(forKey: key)
        continuation?.resume(returning: posts)
    }

    func ensureAnonymousSession() async throws {}

    func fetchPosts(query: CommunityFeedQuery) async throws -> [CommunityPost] {
        try await withCheckedThrowingContinuation { continuation in
            let key = query.cacheKey
            fetchContinuations[key] = continuation
            fetchWaiters.removeValue(forKey: key)?.forEach { $0.resume() }
        }
    }

    func fetchPost(postID: UUID) async throws -> CommunityPost? {
        nil
    }

    func fetchComments(postID: UUID) async throws -> [CommunityComment] {
        []
    }

    func createComment(postID: UUID, body: String) async throws -> CommunityComment {
        throw CommunityRepositoryTestError.failure("未实现")
    }

    func togglePostLike(postID: UUID) async throws -> CommunityPost {
        throw CommunityRepositoryTestError.failure("未实现")
    }

    func togglePostFavorite(postID: UUID) async throws -> CommunityPost {
        throw CommunityRepositoryTestError.failure("未实现")
    }

    func reportPost(postID: UUID, reason: String) async throws {}

    func reportComment(commentID: UUID, reason: String) async throws {}

    func blockUser(userID: UUID, reason: String?) async throws {}

    func deletePost(postID: UUID) async throws {}

    func deleteComment(commentID: UUID) async throws {}

    func hasAcceptedCurrentTerms() async throws -> Bool {
        true
    }

    func createPost(input: CreatePostInput, images: [CommunityImageUpload]) async throws -> CommunityPost {
        throw CommunityRepositoryTestError.failure("未实现")
    }

    func fetchPolls(limit: Int) async throws -> [CommunityPoll] {
        []
    }

    func fetchMyAuthoredPolls(limit: Int) async throws -> [CommunityPoll] {
        []
    }

    func fetchMyVotedPolls(limit: Int) async throws -> [CommunityPoll] {
        []
    }

    func createPoll(input: CreatePollInput) async throws -> CommunityPoll {
        throw CommunityRepositoryTestError.failure("未实现")
    }

    func votePoll(pollID: UUID, optionID: UUID) async throws -> CommunityPoll {
        throw CommunityRepositoryTestError.failure("未实现")
    }

    func requestPollDeletion(pollID: UUID, reason: String?) async throws -> CommunityPoll {
        throw CommunityRepositoryTestError.failure("未实现")
    }

    func deleteOwnPoll(pollID: UUID) async throws {
        _ = try await requestPollDeletion(pollID: pollID, reason: nil)
    }

    func fetchTeacherRatingSummaries(search: String, limit: Int, offset: Int) async throws -> [TeacherRatingSummary] {
        []
    }

    func fetchCourseRatingSummaries(search: String, category: String?, limit: Int, offset: Int) async throws -> [CourseRatingSummary] {
        []
    }

    func fetchDishRatingSummaries(search: String, canteen: String?, location: String?, limit: Int, offset: Int) async throws -> [DishRatingSummary] {
        []
    }

    func submitCatalogSuggestion(input: CatalogSuggestionInput) async throws {}

    func fetchUnreadNotificationCount() async throws -> Int {
        0
    }
}

private enum CommunityRepositoryTestError: LocalizedError, Sendable {
    case failure(String)

    var errorDescription: String? {
        switch self {
        case .failure(let message):
            return message
        }
    }
}

private func makeTestCommunityPost(title: String) -> CommunityPost {
    CommunityPost(
        id: UUID(),
        authorID: UUID(),
        title: title,
        body: "正文",
        category: "学习交流",
        isAnonymous: false,
        commentCount: 0,
        likeCount: 0,
        status: "active",
        createdAt: "2026-05-14T00:00:00Z",
        updatedAt: "2026-05-14T00:00:00Z",
        viewerHasLiked: false,
        viewerHasFavorited: false,
        pin: nil,
        author: nil,
        images: []
    )
}

private actor FakePollRepository: CommunityRepository {
    private var polls: [CommunityPoll] = []

    func setPolls(_ polls: [CommunityPoll]) {
        self.polls = polls
    }

    func ensureAnonymousSession() async throws {}

    func fetchPosts(query: CommunityFeedQuery) async throws -> [CommunityPost] {
        []
    }

    func fetchPost(postID: UUID) async throws -> CommunityPost? {
        nil
    }

    func fetchComments(postID: UUID) async throws -> [CommunityComment] {
        []
    }

    func createComment(postID: UUID, body: String) async throws -> CommunityComment {
        throw CommunityRepositoryTestError.failure("未实现")
    }

    func togglePostLike(postID: UUID) async throws -> CommunityPost {
        throw CommunityRepositoryTestError.failure("未实现")
    }

    func togglePostFavorite(postID: UUID) async throws -> CommunityPost {
        throw CommunityRepositoryTestError.failure("未实现")
    }

    func reportPost(postID: UUID, reason: String) async throws {}

    func reportComment(commentID: UUID, reason: String) async throws {}

    func blockUser(userID: UUID, reason: String?) async throws {}

    func deletePost(postID: UUID) async throws {}

    func deleteComment(commentID: UUID) async throws {}

    func hasAcceptedCurrentTerms() async throws -> Bool {
        true
    }

    func createPost(input: CreatePostInput, images: [CommunityImageUpload]) async throws -> CommunityPost {
        throw CommunityRepositoryTestError.failure("未实现")
    }

    func fetchPolls(limit: Int) async throws -> [CommunityPoll] {
        Array(polls.prefix(limit))
    }

    func fetchMyAuthoredPolls(limit: Int) async throws -> [CommunityPoll] {
        Array(polls.prefix(limit))
    }

    func fetchMyVotedPolls(limit: Int) async throws -> [CommunityPoll] {
        Array(polls.filter { $0.viewerOptionID != nil }.prefix(limit))
    }

    func createPoll(input: CreatePollInput) async throws -> CommunityPoll {
        guard input.validationError == nil else {
            throw CommunityServiceError.invalidPoll
        }

        let pollID = UUID()
        let options = input.normalizedOptions.enumerated().map { index, text in
            CommunityPollOption(
                id: UUID(),
                pollID: pollID,
                text: text,
                sortOrder: index,
                voteCount: 0,
                createdAt: "2026-05-28T00:00:00Z"
            )
        }
        let poll = makePoll(
            id: pollID,
            question: input.normalizedQuestion,
            detail: input.normalizedDetail,
            status: "pending_review",
            options: options,
            closesAt: input.closesAt
        )
        polls.insert(poll, at: 0)
        return poll
    }

    func votePoll(pollID: UUID, optionID: UUID) async throws -> CommunityPoll {
        guard let pollIndex = polls.firstIndex(where: { $0.id == pollID }) else {
            throw CommunityRepositoryTestError.failure("投票不存在")
        }
        let poll = polls[pollIndex]
        guard poll.canVote else {
            throw CommunityServiceError.pollClosed
        }
        guard poll.options.contains(where: { $0.id == optionID }) else {
            throw CommunityRepositoryTestError.failure("选项不存在")
        }

        let nextTotal = poll.viewerOptionID == nil ? poll.totalVoteCount + 1 : poll.totalVoteCount
        let updatedOptions = poll.options.map { option in
            let decrement = poll.viewerOptionID == option.id && option.id != optionID ? 1 : 0
            let increment = option.id == optionID && poll.viewerOptionID != optionID ? 1 : 0
            return CommunityPollOption(
                id: option.id,
                pollID: option.pollID,
                text: option.text,
                sortOrder: option.sortOrder,
                voteCount: max(0, option.voteCount - decrement + increment),
                createdAt: option.createdAt
            )
        }
        let updatedPoll = CommunityPoll(
            id: poll.id,
            authorID: poll.authorID,
            question: poll.question,
            detail: poll.detail,
            status: poll.status,
            totalVoteCount: nextTotal,
            viewerOptionID: optionID,
            closesAt: poll.closesAt,
            deletionStatus: poll.deletionStatus,
            deletionRequestedAt: poll.deletionRequestedAt,
            deletionReason: poll.deletionReason,
            deletionReviewedAt: poll.deletionReviewedAt,
            deletionReviewReason: poll.deletionReviewReason,
            createdAt: poll.createdAt,
            updatedAt: "2026-05-28T00:01:00Z",
            author: poll.author,
            options: updatedOptions
        )
        polls[pollIndex] = updatedPoll
        return updatedPoll
    }

    func requestPollDeletion(pollID: UUID, reason: String?) async throws -> CommunityPoll {
        guard let pollIndex = polls.firstIndex(where: { $0.id == pollID }) else {
            throw CommunityRepositoryTestError.failure("投票不存在")
        }
        let poll = polls[pollIndex]
        guard !poll.isDeletionPending else {
            throw CommunityRepositoryTestError.failure("删除申请审核中")
        }

        let updatedPoll = CommunityPoll(
            id: poll.id,
            authorID: poll.authorID,
            question: poll.question,
            detail: poll.detail,
            status: poll.status,
            totalVoteCount: poll.totalVoteCount,
            viewerOptionID: poll.viewerOptionID,
            closesAt: poll.closesAt,
            deletionStatus: "pending",
            deletionRequestedAt: "2026-05-28T00:02:00Z",
            deletionReason: reason,
            deletionReviewedAt: nil,
            deletionReviewReason: nil,
            createdAt: poll.createdAt,
            updatedAt: "2026-05-28T00:02:00Z",
            author: poll.author,
            options: poll.options
        )
        polls[pollIndex] = updatedPoll
        return updatedPoll
    }

    func deleteOwnPoll(pollID: UUID) async throws {
        _ = try await requestPollDeletion(pollID: pollID, reason: nil)
    }

    func fetchTeacherRatingSummaries(search: String, limit: Int, offset: Int) async throws -> [TeacherRatingSummary] {
        []
    }

    func fetchCourseRatingSummaries(search: String, category: String?, limit: Int, offset: Int) async throws -> [CourseRatingSummary] {
        []
    }

    func fetchDishRatingSummaries(search: String, canteen: String?, location: String?, limit: Int, offset: Int) async throws -> [DishRatingSummary] {
        []
    }

    func submitCatalogSuggestion(input: CatalogSuggestionInput) async throws {}

    func fetchUnreadNotificationCount() async throws -> Int {
        0
    }

    private func makePoll(
        id: UUID = UUID(),
        question: String = "去哪自习？",
        detail: String? = nil,
        status: String = "published",
        options: [CommunityPollOption]? = nil,
        totalVoteCount: Int = 0,
        viewerOptionID: UUID? = nil,
        closesAt: String? = nil,
        deletionStatus: String = "none",
        deletionRequestedAt: String? = nil,
        deletionReason: String? = nil,
        deletionReviewedAt: String? = nil,
        deletionReviewReason: String? = nil
    ) -> CommunityPoll {
        let resolvedOptions = options ?? [
            CommunityPollOption(
                id: UUID(),
                pollID: id,
                text: "图书馆",
                sortOrder: 0,
                voteCount: 0,
                createdAt: "2026-05-28T00:00:00Z"
            ),
            CommunityPollOption(
                id: UUID(),
                pollID: id,
                text: "教学楼",
                sortOrder: 1,
                voteCount: 0,
                createdAt: "2026-05-28T00:00:00Z"
            )
        ]

        return CommunityPoll(
            id: id,
            authorID: UUID(),
            question: question,
            detail: detail,
            status: status,
            totalVoteCount: totalVoteCount,
            viewerOptionID: viewerOptionID,
            closesAt: closesAt,
            deletionStatus: deletionStatus,
            deletionRequestedAt: deletionRequestedAt,
            deletionReason: deletionReason,
            deletionReviewedAt: deletionReviewedAt,
            deletionReviewReason: deletionReviewReason,
            createdAt: "2026-05-28T00:00:00Z",
            updatedAt: "2026-05-28T00:00:00Z",
            author: nil,
            options: resolvedOptions
        )
    }
}

private func makeTestCommunityPoll(
    id: UUID = UUID(),
    question: String = "去哪自习？",
    detail: String? = nil,
    status: String = "published",
    options: [CommunityPollOption]? = nil,
    totalVoteCount: Int = 0,
    viewerOptionID: UUID? = nil,
    closesAt: String? = nil,
    deletionStatus: String = "none",
    deletionRequestedAt: String? = nil,
    deletionReason: String? = nil,
    deletionReviewedAt: String? = nil,
    deletionReviewReason: String? = nil
) -> CommunityPoll {
    let resolvedOptions = options ?? [
        CommunityPollOption(
            id: UUID(),
            pollID: id,
            text: "图书馆",
            sortOrder: 0,
            voteCount: 0,
            createdAt: "2026-05-28T00:00:00Z"
        ),
        CommunityPollOption(
            id: UUID(),
            pollID: id,
            text: "教学楼",
            sortOrder: 1,
            voteCount: 0,
            createdAt: "2026-05-28T00:00:00Z"
        )
    ]

    return CommunityPoll(
        id: id,
        authorID: UUID(),
        question: question,
        detail: detail,
        status: status,
        totalVoteCount: totalVoteCount,
        viewerOptionID: viewerOptionID,
        closesAt: closesAt,
        deletionStatus: deletionStatus,
        deletionRequestedAt: deletionRequestedAt,
        deletionReason: deletionReason,
        deletionReviewedAt: deletionReviewedAt,
        deletionReviewReason: deletionReviewReason,
        createdAt: "2026-05-28T00:00:00Z",
        updatedAt: "2026-05-28T00:00:00Z",
        author: nil,
        options: resolvedOptions
    )
}
