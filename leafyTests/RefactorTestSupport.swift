import XCTest
import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers
import Supabase
import SwiftData
@testable import Leafy

final class AuthRecordingURLProtocol: URLProtocol, @unchecked Sendable {
    struct RecordedRequest {
        let method: String
        let path: String
        let body: [String: Any]
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var requests: [RecordedRequest] = []

    static func reset() {
        lock.lock()
        requests.removeAll()
        lock.unlock()
    }

    static func snapshot() -> [RecordedRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let body = requestBodyData().flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        } ?? [:]
        let recorded = RecordedRequest(
            method: request.httpMethod ?? "",
            path: request.url?.path ?? "",
            body: body
        )

        Self.lock.lock()
        Self.requests.append(recorded)
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 400,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(
            self,
            didLoad: Data(#"{"message":"forced test response","error_code":"validation_failed"}"#.utf8)
        )
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func requestBodyData() -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { return nil }
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

final class PerformanceRefactorTests: XCTestCase {
    func jpegData(from image: UIImage, orientation: UInt32) -> Data? {
        guard let cgImage = image.cgImage else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

}

func withTemporaryUserDefaults(_ body: (UserDefaults) -> Void) {
    let suiteName = "TimetableBackgroundTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        return XCTFail("Failed to create isolated UserDefaults suite")
    }
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }
    body(defaults)
}

var reviewTestCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

func makeReviewUserDefaults() -> UserDefaults {
    let suiteName = "leafy.tests.appStoreReview.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

func reviewDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
    reviewTestCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
}

func semesterDate(week: Int, day: Int, hour: Int, minute: Int) -> Date {
    let calendar = Calendar.current
    let dayOffset = (week - 1) * 7 + (day - 1)
    let date = calendar.date(byAdding: .day, value: dayOffset, to: SemesterConfig.startOfSemesterDate)!
    return calendar.date(
        bySettingHour: hour,
        minute: minute,
        second: 0,
        of: date
    )!
}

func seedThreeReviewSyncDays(defaults: UserDefaults) {
    let notificationCenter = NotificationCenter()
    for day in 10...12 {
        AppStoreReviewCoordinator.recordSuccessfulSync(
            kind: .timetable,
            date: reviewDate(2026, 5, day),
            calendar: reviewTestCalendar,
            userDefaults: defaults,
            notificationCenter: notificationCenter
        )
    }
}

final class FakeCommunityFeedCache: CommunityFeedCaching {
    var loadedPosts: [CommunityPost]
    private(set) var savedPostSnapshots: [[CommunityPost]] = []
    private var loadedPostsByKey: [String: [CommunityPost]]

    init(loadedPosts: [CommunityPost] = []) {
        self.loadedPosts = loadedPosts
        self.loadedPostsByKey = [CommunityFeedQuery.default.cacheKey: loadedPosts]
    }

    func load(query: CommunityFeedQuery) -> [CommunityPost] {
        loadedPostsByKey[query.cacheKey] ?? []
    }

    func save(_ posts: [CommunityPost], query: CommunityFeedQuery) {
        savedPostSnapshots.append(posts)
        loadedPosts = posts
        loadedPostsByKey[query.cacheKey] = posts
    }
}

actor FakeCommunityRepository: CommunityRepository {
    private var postResponses: [[CommunityPost]]
    private var pollResponses: [[CommunityPoll]]
    private var fetchError: PerformanceCommunityRepositoryTestError?
    private var shouldSuspendFetch = false
    private var suspendedFetchContinuation: CheckedContinuation<[CommunityPost], Error>?
    private var suspendedFetchWaiters: [CheckedContinuation<Void, Never>] = []
    private var likeResponses: [UUID: CommunityPost] = [:]
    private var favoriteResponses: [UUID: CommunityPost] = [:]
    private var votePollResponses: [UUID: CommunityPoll] = [:]
    private var pollFetchLimits: [Int] = []
    private var postFetchQueries: [CommunityFeedQuery] = []
    private var catalogSuggestionInputs: [CatalogSuggestionInput] = []

    init(postResponses: [[CommunityPost]] = [[]], pollResponses: [[CommunityPoll]] = [[]]) {
        self.postResponses = postResponses
        self.pollResponses = pollResponses
    }

    func setFetchError(_ error: PerformanceCommunityRepositoryTestError?) {
        fetchError = error
    }

    func suspendFetches() {
        shouldSuspendFetch = true
    }

    func waitForSuspendedFetch() async {
        if suspendedFetchContinuation != nil { return }

        await withCheckedContinuation { continuation in
            suspendedFetchWaiters.append(continuation)
        }
    }

    func resumeSuspendedFetch(with posts: [CommunityPost]) {
        shouldSuspendFetch = false
        let continuation = suspendedFetchContinuation
        suspendedFetchContinuation = nil
        continuation?.resume(returning: posts)
    }

    func setLikeResponse(_ post: CommunityPost, for postID: UUID) {
        likeResponses[postID] = post
    }

    func setFavoriteResponse(_ post: CommunityPost, for postID: UUID) {
        favoriteResponses[postID] = post
    }

    func setVotePollResponse(_ poll: CommunityPoll, for pollID: UUID) {
        votePollResponses[pollID] = poll
    }

    func fetchedPollLimits() -> [Int] {
        pollFetchLimits
    }

    func fetchedPostQueries() -> [CommunityFeedQuery] {
        postFetchQueries
    }

    func submittedCatalogSuggestions() -> [CatalogSuggestionInput] {
        catalogSuggestionInputs
    }

    func ensureAnonymousSession() async throws {}

    func fetchPosts(query: CommunityFeedQuery) async throws -> [CommunityPost] {
        postFetchQueries.append(query)
        if let fetchError {
            throw fetchError
        }

        if shouldSuspendFetch {
            return try await withCheckedThrowingContinuation { continuation in
                suspendedFetchContinuation = continuation
                suspendedFetchWaiters.forEach { $0.resume() }
                suspendedFetchWaiters.removeAll()
            }
        }

        guard !postResponses.isEmpty else { return [] }
        guard postResponses.count > 1 else { return postResponses[0] }
        return postResponses.removeFirst()
    }

    func fetchPost(postID: UUID) async throws -> CommunityPost? {
        nil
    }

    func fetchComments(postID: UUID) async throws -> [CommunityComment] {
        []
    }

    func fetchCommentThreads(postID: UUID, cursor: CommunityCommentCursor?, limit: Int) async throws -> CommunityCommentPage {
        CommunityCommentPage(threads: [], nextCursor: nil)
    }

    func createComment(postID: UUID, body: String) async throws -> CommunityComment {
        throw PerformanceCommunityRepositoryTestError.failure("未实现")
    }

    func createComment(postID: UUID, body: String, parentCommentID: UUID?, replyToCommentID: UUID?) async throws -> CommunityComment {
        throw PerformanceCommunityRepositoryTestError.failure("未实现")
    }

    func toggleCommentLike(commentID: UUID) async throws -> CommunityCommentLikeState {
        throw PerformanceCommunityRepositoryTestError.failure("未实现")
    }

    func attachmentDownloadURL(attachmentID: UUID) async throws -> CommunityAttachmentDownload {
        throw PerformanceCommunityRepositoryTestError.failure("未实现")
    }

    func togglePostLike(postID: UUID) async throws -> CommunityPost {
        guard let post = likeResponses[postID] else {
            throw PerformanceCommunityRepositoryTestError.failure("缺少点赞返回")
        }

        return post
    }

    func togglePostFavorite(postID: UUID) async throws -> CommunityPost {
        guard let post = favoriteResponses[postID] else {
            throw PerformanceCommunityRepositoryTestError.failure("缺少收藏返回")
        }

        return post
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
        throw PerformanceCommunityRepositoryTestError.failure("未实现")
    }

    @MainActor
    func enqueuePostPublication(input: CreatePostInput, images: [CommunityImageUpload], attachments: [CommunityAttachmentUpload]) throws -> UUID {
        throw PerformanceCommunityRepositoryTestError.failure("未实现")
    }

    func fetchPolls(limit: Int) async throws -> [CommunityPoll] {
        pollFetchLimits.append(limit)
        guard !pollResponses.isEmpty else { return [] }
        guard pollResponses.count > 1 else { return pollResponses[0] }
        return pollResponses.removeFirst()
    }

    func fetchMyAuthoredPolls(limit: Int) async throws -> [CommunityPoll] {
        []
    }

    func fetchMyVotedPolls(limit: Int) async throws -> [CommunityPoll] {
        []
    }

    func createPoll(input: CreatePollInput) async throws -> CommunityPoll {
        throw PerformanceCommunityRepositoryTestError.failure("未实现")
    }

    func votePoll(pollID: UUID, optionID: UUID) async throws -> CommunityPoll {
        guard let poll = votePollResponses[pollID] else {
            throw PerformanceCommunityRepositoryTestError.failure("缺少投票返回")
        }

        return poll
    }

    func requestPollDeletion(pollID: UUID, reason: String?) async throws -> CommunityPoll {
        throw PerformanceCommunityRepositoryTestError.failure("未实现")
    }

    func deleteOwnPoll(pollID: UUID) async throws {}

    func fetchTeacherRatingSummaries(search: String, limit: Int, offset: Int) async throws -> [TeacherRatingSummary] {
        []
    }

    func fetchCourseRatingSummaries(search: String, category: String?, limit: Int, offset: Int) async throws -> [CourseRatingSummary] {
        []
    }

    func fetchDishRatingSummaries(search: String, canteen: String?, location: String?, limit: Int, offset: Int) async throws -> [DishRatingSummary] {
        []
    }

    func submitCatalogSuggestion(input: CatalogSuggestionInput) async throws {
        catalogSuggestionInputs.append(input)
    }

    func fetchUnreadNotificationCount() async throws -> Int {
        0
    }

    func notificationEvents(profileID: UUID) async -> AsyncThrowingStream<Void, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func fetchNotificationFeed(limit: Int) async throws -> [NotificationFeedItem] { [] }
    func fetchNotificationSettings() async throws -> CommunityNotificationSettings { throw PerformanceCommunityRepositoryTestError.failure("未实现") }
    func updateNotificationSettings(mutedAll: Bool) async throws -> CommunityNotificationSettings { throw PerformanceCommunityRepositoryTestError.failure("未实现") }
    func markNotificationFeedRead(announcementLimit: Int) async throws {}
    func dismissNotificationFeedItem(_ item: NotificationFeedItem) async throws {}
    func markNotificationRead(notificationID: UUID) async throws {}
    func markSiteAnnouncementRead(announcementID: UUID) async throws {}
    func fetchLinkedPost(postID: UUID) async throws -> CommunityPost? { try await fetchPost(postID: postID) }
}

enum PerformanceCommunityRepositoryTestError: LocalizedError, Sendable {
    case failure(String)

    var errorDescription: String? {
        switch self {
        case .failure(let message):
            return message
        }
    }
}

func makeWidgetSignatureArchive(
    generatedAt: Date = Date(timeIntervalSince1970: 1)
) -> LeafyWidgetSnapshotArchive {
    LeafyWidgetSnapshotArchive(
        generatedAt: generatedAt,
        snapshots: [
            LeafyWidgetDaySnapshot(
                dayOffset: 0,
                snapshot: LeafyWidgetSnapshot(
                    generatedAt: generatedAt,
                    status: .ready,
                    displayDate: "Today",
                    weekText: "Week",
                    dayText: "Mon",
                    headline: "今日课表",
                    subtitle: "下一节：A",
                    syncText: "最近同步：12:00",
                    lastFailureText: nil,
                    nextExamText: nil,
                    courses: [
                        LeafyWidgetCourse(
                            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                            title: "A",
                            timeText: "08:00",
                            periodText: "第 1 节",
                            locationText: "101",
                            teacherText: nil,
                            noteText: nil,
                            reminderText: nil,
                            accentIndex: 0,
                            isActive: false
                        )
                    ]
                )
            )
        ]
    )
}

func timetableMetrics(
    width: CGFloat,
    height: CGFloat,
    dayCount: Int,
    controlScale: CGFloat = 1,
    allowsAgendaList: Bool = true
) -> TimetableResponsiveLayout.Metrics {
    TimetableResponsiveLayout.metrics(
        for: CGSize(width: width, height: height),
        dayCount: dayCount,
        totalClasses: 13,
        axisWidth: 34 * controlScale,
        headerHeight: 52 * controlScale,
        horizontalPadding: 4 * controlScale,
        daySpacing: 5 * controlScale,
        weekSpacing: 6 * controlScale,
        rowSpacing: 1.5 * controlScale,
        minimumRowHeight: 26 * controlScale,
        cardInset: 1.5 * controlScale,
        laneSpacing: 2 * controlScale,
        bottomClearance: 16 * controlScale,
        controlScale: controlScale,
        interPaneSpacing: 8,
        allowsAgendaList: allowsAgendaList
    )
}

func makePaletteTestImage(colors: [UIColor], size: CGSize = CGSize(width: 80, height: 80)) -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { context in
        guard !colors.isEmpty else {
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            return
        }

        let stripeWidth = size.width / CGFloat(colors.count)
        for (index, color) in colors.enumerated() {
            color.setFill()
            context.fill(CGRect(
                x: CGFloat(index) * stripeWidth,
                y: 0,
                width: index == colors.count - 1 ? size.width - CGFloat(index) * stripeWidth : stripeWidth,
                height: size.height
            ))
        }
    }
}

func makeCommunityPost(
    id: UUID = UUID(),
    authorID: UUID = UUID(),
    title: String = "帖子",
    body: String = "正文",
    category: String? = "学习交流",
    commentCount: Int = 0,
    likeCount: Int = 0,
    status: String = "active",
    createdAt: String = "2026-05-14T00:00:00Z",
    viewerHasLiked: Bool = false,
    viewerHasFavorited: Bool = false,
    pin: CommunityPostPin? = nil
) -> CommunityPost {
    CommunityPost(
        id: id,
        authorID: authorID,
        title: title,
        body: body,
        category: category,
        isAnonymous: false,
        commentCount: commentCount,
        likeCount: likeCount,
        status: status,
        createdAt: createdAt,
        updatedAt: createdAt,
        viewerHasLiked: viewerHasLiked,
        viewerHasFavorited: viewerHasFavorited,
        pin: pin,
        author: nil,
        images: []
    )
}

func makeCommunityPostPin(
    id: UUID = UUID(),
    postID: UUID,
    scope: CommunityPostPinScope = .global,
    category: String? = nil,
    priority: Int = 0,
    startsAt: String = "2026-05-14T00:00:00Z",
    endsAt: String? = nil,
    status: String = "active"
) -> CommunityPostPin {
    CommunityPostPin(
        id: id,
        postID: postID,
        scope: scope,
        category: category,
        priority: priority,
        startsAt: startsAt,
        endsAt: endsAt,
        status: status,
        reason: nil,
        createdAt: startsAt
    )
}

func makeCommunityPoll(
    id: UUID = UUID(),
    authorID: UUID = UUID(),
    question: String = "投票",
    detail: String? = nil,
    status: String = "published",
    totalVoteCount: Int = 0,
    viewerOptionID: UUID? = nil,
    closesAt: String? = nil,
    createdAt: String = "2026-05-14T00:00:00Z",
    deletionStatus: String = "none",
    options: [CommunityPollOption]? = nil
) -> CommunityPoll {
    let resolvedOptions = options ?? [
        makeCommunityPollOption(pollID: id, text: "选项 A"),
        makeCommunityPollOption(pollID: id, text: "选项 B", sortOrder: 1)
    ]
    return CommunityPoll(
        id: id,
        authorID: authorID,
        question: question,
        detail: detail,
        status: status,
        totalVoteCount: totalVoteCount,
        viewerOptionID: viewerOptionID,
        closesAt: closesAt,
        deletionStatus: deletionStatus,
        createdAt: createdAt,
        updatedAt: createdAt,
        author: nil,
        options: resolvedOptions
    )
}

func makeCommunityPollOption(
    id: UUID = UUID(),
    pollID: UUID = UUID(),
    text: String = "选项",
    sortOrder: Int = 0,
    voteCount: Int = 0,
    createdAt: String = "2026-05-14T00:00:00Z"
) -> CommunityPollOption {
    CommunityPollOption(
        id: id,
        pollID: pollID,
        text: text,
        sortOrder: sortOrder,
        voteCount: voteCount,
        createdAt: createdAt
    )
}
