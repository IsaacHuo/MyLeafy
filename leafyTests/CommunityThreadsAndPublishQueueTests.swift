import XCTest
@testable import Leafy

final class CommunityThreadsAndPublishQueueTests: XCTestCase {
    func testCreatePostRPCParamsEncodeNullCategory() throws {
        let params = CommunityCreatePostV4RPCParams(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            requestID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            title: "无分类帖子",
            body: "正文",
            category: nil,
            isAnonymous: false,
            imageCount: 0,
            attachmentCount: 0
        )

        let data = try JSONEncoder().encode(params)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object.count, 8)
        XCTAssertTrue(object["p_category"] is NSNull)
        XCTAssertEqual(object["p_request_id"] as? String, "22222222-2222-2222-2222-222222222222")
    }

    func testNotificationRPCParamsEncodeNullOptionalValues() throws {
        let params = CommunityNotificationRPCParams(
            recipientID: UUID(),
            actorID: UUID(),
            postID: UUID(),
            commentID: nil,
            type: .comment,
            title: "新通知",
            body: nil
        )

        let data = try JSONEncoder().encode(params)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object.count, 7)
        XCTAssertTrue(object["p_comment_id"] is NSNull)
        XCTAssertTrue(object["p_body"] is NSNull)
    }

    func testTopLevelCommentRPCParamsEncodeNullReplyTargets() throws {
        let params = CommunityCreateCommentV2RPCParams(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            requestID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            postID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            body: "一级评论",
            parentCommentID: nil,
            replyToCommentID: nil,
            isAnonymous: false
        )

        let data = try JSONEncoder().encode(params)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object.count, 7)
        XCTAssertTrue(object["p_parent_comment_id"] is NSNull)
        XCTAssertTrue(object["p_reply_to_comment_id"] is NSNull)
        XCTAssertEqual(object["p_request_id"] as? String, "22222222-2222-2222-2222-222222222222")
    }

    func testUnknownCommunityMutationErrorDoesNotExposeBackendDetails() async {
        let backendMessage = "Could not find the function in the schema cache"
        let error = NSError(domain: "PostgREST", code: 202, userInfo: [
            NSLocalizedDescriptionKey: backendMessage
        ])

        let mapped = await CommunityService().mapCommunityMutationError(
            error,
            fallback: "评论发布失败"
        )

        XCTAssertEqual(mapped.localizedDescription, "评论发布失败，请稍后重试。")
        XCTAssertFalse(mapped.localizedDescription.contains(backendMessage))
    }

    func testCommentLikeResponseDecodesSingleRow() throws {
        let commentID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let data = Data(
            """
            [{
              "comment_id": "\(commentID.uuidString)",
              "like_count": 4,
              "viewer_has_liked": true
            }]
            """.utf8
        )

        let records = try JSONDecoder().decode([CommunityCommentLikeStateRecord].self, from: data)
        let state = try CommunityCommentLikeResponseValidator.state(from: records)

        XCTAssertEqual(state.commentID, commentID)
        XCTAssertEqual(state.likeCount, 4)
        XCTAssertTrue(state.viewerHasLiked)
    }

    func testCommentLikeResponseRejectsUnexpectedRowCounts() throws {
        let record = try JSONDecoder().decode(
            CommunityCommentLikeStateRecord.self,
            from: Data(
                """
                {
                  "comment_id": "11111111-1111-1111-1111-111111111111",
                  "like_count": 4,
                  "viewer_has_liked": true
                }
                """.utf8
            )
        )

        for records in [[], [record, record]] {
            XCTAssertThrowsError(try CommunityCommentLikeResponseValidator.state(from: records)) { error in
                XCTAssertEqual(error.localizedDescription, "评论点赞返回数据异常，请稍后重试。")
            }
        }
    }

    func testCommentLikeResponseRejectsInvalidFields() {
        let data = Data(
            """
            [{
              "comment_id": "11111111-1111-1111-1111-111111111111",
              "like_count": 4
            }]
            """.utf8
        )

        XCTAssertThrowsError(
            try JSONDecoder().decode([CommunityCommentLikeStateRecord].self, from: data)
        )
    }

    func testCommentInteractionPolicyAllowsReplyingToOwnVisiblePublishedComment() {
        let viewerID = UUID()
        let otherUserID = UUID()

        XCTAssertTrue(
            CommunityCommentInteractionPolicy.canReply(
                to: makeComment(authorID: otherUserID),
                viewerID: viewerID
            )
        )
        XCTAssertTrue(
            CommunityCommentInteractionPolicy.canLike(
                makeComment(authorID: otherUserID),
                viewerID: viewerID
            )
        )
        XCTAssertTrue(
            CommunityCommentInteractionPolicy.canReply(
                to: makeComment(authorID: viewerID),
                viewerID: viewerID
            )
        )
        XCTAssertFalse(
            CommunityCommentInteractionPolicy.canLike(
                makeComment(authorID: viewerID),
                viewerID: viewerID
            )
        )
        XCTAssertFalse(
            CommunityCommentInteractionPolicy.canReply(
                to: makeComment(authorID: otherUserID, status: "deleted", isDeletedPlaceholder: true),
                viewerID: viewerID
            )
        )
        XCTAssertFalse(
            CommunityCommentInteractionPolicy.canReply(
                to: makeComment(authorID: otherUserID, replyTargetIsVisible: false),
                viewerID: viewerID
            )
        )
        XCTAssertFalse(
            CommunityCommentInteractionPolicy.canReply(
                to: makeComment(authorID: otherUserID),
                viewerID: nil
            )
        )
    }

    func testCommentComposerPrefillsMentionAndStripsItBeforeSubmission() {
        let firstTarget = makeComment(authorID: UUID())
        let secondTarget = makeComment(authorID: UUID())
        let firstDraft = CommunityCommentComposerPolicy.draft(
            bySelecting: firstTarget,
            currentBody: "原有内容",
            previousTarget: nil
        )

        XCTAssertEqual(
            firstDraft,
            CommunityCommentComposerPolicy.mentionPrefix(for: firstTarget) + "原有内容"
        )
        XCTAssertTrue(
            CommunityCommentComposerPolicy.retainsReplyTarget(firstTarget, in: firstDraft)
        )
        XCTAssertEqual(
            CommunityCommentComposerPolicy.submissionBody(
                from: firstDraft,
                replyingTo: firstTarget
            ),
            "原有内容"
        )

        let switchedDraft = CommunityCommentComposerPolicy.draft(
            bySelecting: secondTarget,
            currentBody: firstDraft,
            previousTarget: firstTarget
        )
        XCTAssertEqual(
            switchedDraft,
            CommunityCommentComposerPolicy.mentionPrefix(for: secondTarget) + "原有内容"
        )
    }

    func testCommentComposerClearsReplyWhenMentionIsRemovedAndRejectsPrefixOnlyDraft() {
        let target = makeComment(authorID: UUID())
        let prefix = CommunityCommentComposerPolicy.mentionPrefix(for: target)

        XCTAssertFalse(
            CommunityCommentComposerPolicy.retainsReplyTarget(target, in: "普通评论")
        )
        XCTAssertTrue(
            CommunityCommentComposerPolicy.submissionBody(
                from: prefix,
                replyingTo: target
            ).isEmpty
        )
    }

    func testCommentComposerTreatsReplyMentionAsOneBackspaceToken() {
        let target = makeComment(authorID: UUID())
        let prefix = CommunityCommentComposerPolicy.mentionPrefix(for: target)

        XCTAssertEqual(
            CommunityCommentComposerPolicy.bodyAfterEditingReplyMention(
                previousBody: prefix,
                newBody: String(prefix.dropLast()),
                target: target
            ),
            ""
        )
        XCTAssertEqual(
            CommunityCommentComposerPolicy.bodyAfterEditingReplyMention(
                previousBody: prefix + "正文",
                newBody: String(prefix.dropLast()) + "正文",
                target: target
            ),
            "正文"
        )
        XCTAssertEqual(
            CommunityCommentComposerPolicy.bodyAfterEditingReplyMention(
                previousBody: prefix + "原内容",
                newBody: "替换后的内容",
                target: target
            ),
            "替换后的内容"
        )
    }

    func testCommentRequestTrackerReusesFailedRequestAndRotatesForChangedContent() {
        var tracker = CommunityCommentRequestTracker()
        let parentID = UUID()
        let first = tracker.requestID(body: "同一条评论", parentID: parentID, replyID: parentID)

        XCTAssertEqual(
            tracker.requestID(body: "同一条评论", parentID: parentID, replyID: parentID),
            first
        )
        XCTAssertNotEqual(
            tracker.requestID(body: "修改后的评论", parentID: parentID, replyID: parentID),
            first
        )

        let completed = tracker.requestID(body: "准备完成", parentID: nil, replyID: nil)
        tracker.complete(requestID: completed)
        XCTAssertNotEqual(
            tracker.requestID(body: "准备完成", parentID: nil, replyID: nil),
            completed
        )
    }

    func testCommentRequestTrackerPersistsAcrossRecreationWithoutStoringBody() throws {
        let suiteName = "CommunityCommentRequestTrackerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let postID = UUID()
        let body = "网络超时后的评论正文"

        var firstTracker = CommunityCommentRequestTracker(postID: postID, userDefaults: defaults)
        let firstRequestID = firstTracker.requestID(body: body, parentID: nil, replyID: nil)
        let storedData = defaults.dictionaryRepresentation().values.compactMap { $0 as? Data }
        XCTAssertFalse(storedData.contains { String(data: $0, encoding: .utf8)?.contains(body) == true })

        var restoredTracker = CommunityCommentRequestTracker(postID: postID, userDefaults: defaults)
        XCTAssertEqual(
            restoredTracker.requestID(body: body, parentID: nil, replyID: nil),
            firstRequestID
        )

        restoredTracker.complete(requestID: firstRequestID)
        var completedTracker = CommunityCommentRequestTracker(postID: postID, userDefaults: defaults)
        XCTAssertNotEqual(
            completedTracker.requestID(body: body, parentID: nil, replyID: nil),
            firstRequestID
        )
    }

    func testPublishCapabilityRequirementsAreMediaSpecific() throws {
        let staleCapabilities = try decodeCapabilities(
            rpcs: ["create_community_post_v4_idempotent": true],
            edgeFunctions: []
        )
        let textKinds: Set<CommunityPublishMediaKind> = []
        let imageKinds: Set<CommunityPublishMediaKind> = [.image]
        let attachmentKinds: Set<CommunityPublishMediaKind> = [.attachment]

        XCTAssertTrue(
            CommunityPublishCapabilityRequirements.isSatisfied(
                by: staleCapabilities,
                mediaKinds: textKinds
            )
        )
        XCTAssertEqual(
            CommunityPublishCapabilityRequirements.missingRPCs(
                in: staleCapabilities,
                mediaKinds: imageKinds
            ),
            ["attach_community_post_image_v1"]
        )
        XCTAssertEqual(
            CommunityPublishCapabilityRequirements.missingEdgeFunctions(
                in: staleCapabilities,
                mediaKinds: imageKinds
            ),
            ["community-validate-upload"]
        )
        XCTAssertEqual(
            CommunityPublishCapabilityRequirements.missingRPCs(
                in: staleCapabilities,
                mediaKinds: attachmentKinds
            ),
            ["attach_community_post_attachment_v1"]
        )
        XCTAssertEqual(
            CommunityPublishCapabilityRequirements.missingEdgeFunctions(
                in: staleCapabilities,
                mediaKinds: attachmentKinds
            ),
            ["community-validate-attachment"]
        )
    }

    func testPublishCapabilitiesRefreshOnlyWhenCachedValueIsMissingRequirements() async throws {
        let mediaKinds: Set<CommunityPublishMediaKind> = [.attachment]
        let staleCapabilities = try decodeCapabilities(
            rpcs: ["create_community_post_v4_idempotent": true],
            edgeFunctions: []
        )
        let currentCapabilities = try decodeCapabilities(
            rpcs: Dictionary(
                uniqueKeysWithValues: CommunityPublishCapabilityRequirements
                    .requiredRPCs(for: mediaKinds)
                    .map { ($0, true) }
            ),
            edgeFunctions: CommunityPublishCapabilityRequirements.requiredEdgeFunctions(for: mediaKinds)
        )

        let refreshed = await CommunityPublishCapabilityRequirements.refreshingIfNeeded(
            staleCapabilities,
            mediaKinds: mediaKinds
        ) {
            currentCapabilities
        }
        XCTAssertTrue(
            CommunityPublishCapabilityRequirements.isSatisfied(
                by: refreshed,
                mediaKinds: mediaKinds
            )
        )

        let preserved = await CommunityPublishCapabilityRequirements.refreshingIfNeeded(
            currentCapabilities,
            mediaKinds: mediaKinds
        ) {
            XCTFail("满足要求的 capability 不应重复刷新")
            return staleCapabilities
        }
        XCTAssertTrue(
            CommunityPublishCapabilityRequirements.isSatisfied(
                by: preserved,
                mediaKinds: mediaKinds
            )
        )
    }

    @MainActor
    func testCommentLikeSuccessUsesServerState() async {
        let comment = makeComment(authorID: UUID(), likeCount: 0, viewerHasLiked: false)
        let expectedState = CommunityCommentLikeState(
            commentID: comment.id,
            likeCount: 3,
            viewerHasLiked: true
        )
        let repository = CommunityPostDetailRepositoryStub(
            post: makePost(),
            page: CommunityCommentPage(
                threads: [CommunityCommentThread(root: comment, replies: [])],
                nextCursor: nil
            ),
            toggleOutcome: .success(expectedState)
        )
        let viewModel = CommunityPostDetailViewModel(post: repository.post, repository: repository)

        await viewModel.load()
        await viewModel.toggleCommentLike(comment)

        XCTAssertEqual(viewModel.comments.first?.likeCount, 3)
        XCTAssertEqual(viewModel.comments.first?.viewerHasLiked, true)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testCommentLikeFailureRollsBackOptimisticState() async {
        let comment = makeComment(authorID: UUID(), likeCount: 2, viewerHasLiked: false)
        let repository = CommunityPostDetailRepositoryStub(
            post: makePost(),
            page: CommunityCommentPage(
                threads: [CommunityCommentThread(root: comment, replies: [])],
                nextCursor: nil
            ),
            toggleOutcome: .failure
        )
        let viewModel = CommunityPostDetailViewModel(post: repository.post, repository: repository)

        await viewModel.load()
        await viewModel.toggleCommentLike(comment)

        XCTAssertEqual(viewModel.comments.first?.likeCount, 2)
        XCTAssertEqual(viewModel.comments.first?.viewerHasLiked, false)
        XCTAssertEqual(viewModel.errorMessage, "测试点赞失败")
    }

    func testCommentDecodesThreadAndLikeState() throws {
        let data = Data(
            """
            {
              "id": "11111111-1111-1111-1111-111111111112",
              "post_id": "22222222-2222-2222-2222-222222222222",
              "author_id": "33333333-3333-3333-3333-333333333333",
              "body": "二级回复",
              "is_anonymous": false,
              "status": "published",
              "created_at": "2026-07-25T10:00:00Z",
              "updated_at": "2026-07-25T10:00:00Z",
              "thread_root_id": "11111111-1111-1111-1111-111111111111",
              "parent_comment_id": "11111111-1111-1111-1111-111111111111",
              "reply_to_comment_id": "11111111-1111-1111-1111-111111111111",
              "reply_to_author_id": "44444444-4444-4444-4444-444444444444",
              "reply_target_is_visible": true,
              "like_count": 3,
              "viewer_has_liked": true,
              "is_deleted_placeholder": false
            }
            """.utf8
        )

        let comment = try JSONDecoder().decode(CommunityComment.self, from: data)

        XCTAssertTrue(comment.isReply)
        XCTAssertEqual(
            comment.threadRootID,
            UUID(uuidString: "11111111-1111-1111-1111-111111111111")
        )
        XCTAssertEqual(comment.likeCount, 3)
        XCTAssertTrue(comment.viewerHasLiked)
    }

    func testDeletedCommentDecodesAsPlaceholder() throws {
        let data = Data(
            """
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "post_id": "22222222-2222-2222-2222-222222222222",
              "author_id": "33333333-3333-3333-3333-333333333333",
              "body": "",
              "is_anonymous": false,
              "status": "deleted",
              "created_at": "2026-07-25T10:00:00Z",
              "updated_at": "2026-07-25T11:00:00Z"
            }
            """.utf8
        )

        let comment = try JSONDecoder().decode(CommunityComment.self, from: data)

        XCTAssertTrue(comment.isDeletedPlaceholder)
        XCTAssertFalse(comment.isReply)
    }

    func testPublishTaskProgressUsesPerFileProgress() {
        let media = CommunityPublishMediaItem(
            id: UUID(),
            kind: .attachment,
            displayName: "资料.pdf",
            contentType: "application/pdf",
            fileExtension: "pdf",
            byteSize: 1_024,
            sortOrder: 0,
            localRelativePath: "file.pdf",
            thumbnailRelativePath: nil,
            remotePath: nil,
            thumbnailRemotePath: nil,
            fullUploaded: false,
            thumbnailUploaded: true,
            validated: false,
            progress: 0.5,
            tusUploadURL: nil,
            tusOffset: 512,
            errorMessage: nil
        )
        let task = CommunityPublishTask(
            id: UUID(),
            input: CreatePostInput(
                title: "测试后台发布",
                body: "正文",
                category: "学习交流",
                isAnonymous: false
            ),
            createdAt: Date(),
            updatedAt: Date(),
            state: .uploading,
            media: [media],
            authorID: nil,
            errorMessage: nil,
            completedAt: nil
        )

        XCTAssertEqual(task.progress, 0.425, accuracy: 0.001)
        XCTAssertEqual(task.progressDetail, "上传 1/1")
    }

    func testPublishedTaskImmediatelyLeavesFeedTaskStrip() {
        var task = CommunityPublishTask(
            id: UUID(),
            input: CreatePostInput(
                title: "测试发布状态条",
                body: "正文",
                category: "学习交流",
                isAnonymous: false
            ),
            createdAt: Date(),
            updatedAt: Date(),
            state: .publishing,
            media: [],
            authorID: UUID(),
            errorMessage: nil,
            completedAt: nil
        )

        XCTAssertTrue(task.isVisibleInFeedTaskStrip)

        task.state = .published
        task.completedAt = Date()

        XCTAssertFalse(task.isVisibleInFeedTaskStrip)

        task.state = .failed

        XCTAssertTrue(task.isVisibleInFeedTaskStrip)
    }

    func testPostDecodesLegacyPayloadWithoutAttachments() throws {
        let data = Data(
            """
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "campus_id": "bjfu",
              "author_id": "22222222-2222-2222-2222-222222222222",
              "title": "旧帖子",
              "body": "正文",
              "category": "学习交流",
              "is_anonymous": false,
              "comment_count": 0,
              "like_count": 0,
              "status": "published",
              "created_at": "2026-07-25T10:00:00Z",
              "updated_at": "2026-07-25T10:00:00Z"
            }
            """.utf8
        )

        let post = try JSONDecoder().decode(CommunityPost.self, from: data)

        XCTAssertTrue(post.attachments.isEmpty)
    }

    private func makeComment(
        authorID: UUID,
        status: String = "published",
        replyTargetIsVisible: Bool = true,
        likeCount: Int = 0,
        viewerHasLiked: Bool = false,
        isDeletedPlaceholder: Bool = false
    ) -> CommunityComment {
        CommunityComment(
            id: UUID(),
            postID: UUID(),
            authorID: authorID,
            body: "测试评论",
            isAnonymous: false,
            status: status,
            createdAt: "2026-07-26T10:00:00Z",
            updatedAt: "2026-07-26T10:00:00Z",
            replyTargetIsVisible: replyTargetIsVisible,
            likeCount: likeCount,
            viewerHasLiked: viewerHasLiked,
            isDeletedPlaceholder: isDeletedPlaceholder,
            author: nil
        )
    }

    private func makePost() -> CommunityPost {
        CommunityPost(
            id: UUID(),
            authorID: UUID(),
            title: "测试帖子",
            body: "正文",
            category: "学习交流",
            isAnonymous: false,
            commentCount: 1,
            likeCount: 0,
            status: "published",
            createdAt: "2026-07-26T10:00:00Z",
            updatedAt: "2026-07-26T10:00:00Z",
            viewerHasLiked: false,
            author: nil,
            images: []
        )
    }

    private func decodeCapabilities(
        rpcs: [String: Bool],
        edgeFunctions: [String]
    ) throws -> BackendCapabilities {
        let payload: [String: Any] = [
            "version": 2,
            "features": [:],
            "rpcs": rpcs,
            "edge_functions": edgeFunctions
        ]
        return try JSONDecoder().decode(
            BackendCapabilities.self,
            from: JSONSerialization.data(withJSONObject: payload)
        )
    }
}

private enum CommunityCommentLikeToggleOutcome: Sendable {
    case success(CommunityCommentLikeState)
    case failure
}

private struct CommunityPostDetailRepositoryStub: CommunityPostDetailRepository {
    let post: CommunityPost
    let page: CommunityCommentPage
    let toggleOutcome: CommunityCommentLikeToggleOutcome

    func ensureAnonymousSession() async throws {}

    func hasAcceptedCurrentTerms() async throws -> Bool {
        true
    }

    func fetchPost(postID _: UUID) async throws -> CommunityPost? {
        post
    }

    func fetchComments(postID _: UUID) async throws -> [CommunityComment] {
        page.threads.flatMap { [$0.root] + $0.replies }
    }

    func fetchCommentThreads(
        postID _: UUID,
        cursor _: CommunityCommentCursor?,
        limit _: Int
    ) async throws -> CommunityCommentPage {
        page
    }

    func createComment(postID _: UUID, body _: String) async throws -> CommunityComment {
        page.threads[0].root
    }

    func createComment(
        postID _: UUID,
        body _: String,
        parentCommentID _: UUID?,
        replyToCommentID _: UUID?
    ) async throws -> CommunityComment {
        page.threads[0].root
    }

    func toggleCommentLike(commentID _: UUID) async throws -> CommunityCommentLikeState {
        switch toggleOutcome {
        case .success(let state):
            return state
        case .failure:
            throw CommunityServiceError.edgeFunctionRejected("测试点赞失败")
        }
    }

    func attachmentDownloadURL(attachmentID _: UUID) async throws -> CommunityAttachmentDownload {
        throw CommunityServiceError.edgeFunctionRejected("测试未实现")
    }

    func togglePostLike(postID _: UUID) async throws -> CommunityPost {
        post
    }

    func togglePostFavorite(postID _: UUID) async throws -> CommunityPost {
        post
    }

    func reportPost(postID _: UUID, reason _: String) async throws {}

    func reportComment(commentID _: UUID, reason _: String) async throws {}

    func blockUser(userID _: UUID, reason _: String?) async throws {}

    func deletePost(postID _: UUID) async throws {}

    func deleteComment(commentID _: UUID) async throws {}
}
