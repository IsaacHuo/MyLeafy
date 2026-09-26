import Foundation
import OSLog

enum CommunityServiceError: LocalizedError {
    case missingAuthenticatedUser
    case schoolSessionMissing
    case imageLimitExceeded
    case postRateLimitExceeded
    case profileCompletionRequired
    case invalidEmail
    case cannotLikeOwnPost
    case userMuted
    case termsAcceptanceRequired
    case contentRejected
    case invalidPoll
    case pollClosed
    case accountDeletionFailed
    case edgeFunctionRejected(String)

    var errorDescription: String? {
        switch self {
        case .missingAuthenticatedUser:
            return "社区身份尚未建立，请稍后重试。"
        case .schoolSessionMissing:
            return "教务学号缺失，请连接校园网后重新登录教务系统。"
        case .imageLimitExceeded:
            return "单条帖子最多上传 \(CommunityImageUpload.postImageLimit) 张图片。"
        case .postRateLimitExceeded:
            return "发帖太频繁了，每小时最多发布 2 篇帖子。"
        case .profileCompletionRequired:
            return "请先完善社区资料后再继续。"
        case .invalidEmail:
            return "请输入有效的邮箱地址。"
        case .cannotLikeOwnPost:
            return "不能点赞自己的帖子。"
        case .userMuted:
            return "账号已被社区禁言，暂时不能发帖或评论。"
        case .termsAcceptanceRequired:
            return "请先阅读并同意社区条款。"
        case .contentRejected:
            return "内容包含可能违规的信息，请修改后再发布。"
        case .invalidPoll:
            return "投票内容不完整，请检查问题和选项。"
        case .pollClosed:
            return "投票已截止。"
        case .accountDeletionFailed:
            return "账户删除失败，线上数据和本机数据均未清除，请稍后重试。"
        case .edgeFunctionRejected(let message):
            return message
        }
    }
}

nonisolated enum LeafyFirstValueMap {
    static func build<Key: Hashable, Value>(_ pairs: [(Key, Value)]) -> [Key: Value] {
        var result: [Key: Value] = [:]
        for (key, value) in pairs where result[key] == nil {
            result[key] = value
        }
        return result
    }
}

nonisolated struct EdgeFunctionErrorPayload: Decodable, Sendable {
    let error: String?
    let errorEnvelope: BackendErrorEnvelope?
}

nonisolated enum CommunityCampusRequestAction: String, Encodable, Sendable {
    case current
    case submitNewSchool = "submit_new_school"
    case selectExisting = "select_existing"
    case requestChange = "request_change"
}

nonisolated struct CommunityCampusSearchParams: Encodable, Sendable {
    let search: String
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case search = "p_search"
        case limit = "p_limit"
    }
}

nonisolated struct CommunityCampusRequestSubmitRequest: Encodable, Sendable {
    let action: CommunityCampusRequestAction
    let schoolName: String?
    let campusID: String?

    init(
        action: CommunityCampusRequestAction,
        schoolName: String? = nil,
        campusID: String? = nil
    ) {
        self.action = action
        self.schoolName = schoolName
        self.campusID = campusID
    }

    enum CodingKeys: String, CodingKey {
        case action
        case schoolName = "school_name"
        case campusID = "campus_id"
    }
}

nonisolated struct CommunityCampusRequestResponse: Decodable, Sendable {
    let profile: CommunityProfile?
    let request: CommunityCampusMembershipRequest?
}

nonisolated struct CommunityBootstrapRequest: Encodable, Sendable {
    let eduID: String
    let displayName: String
    let campusID: String

    enum CodingKeys: String, CodingKey {
        case eduID = "edu_id"
        case displayName = "display_name"
        case campusID = "campus_id"
    }
}

nonisolated struct CommunityBootstrapResponse: Decodable, Sendable {
    let profile: CommunityProfile
    let isNewUser: Bool
    let isProfileComplete: Bool

    enum CodingKeys: String, CodingKey {
        case profile
        case isNewUser = "is_new_user"
        case isProfileComplete = "is_profile_complete"
    }
}

nonisolated struct CommunityAccountDeletionResponse: Decodable, Sendable {
    let deleted: Bool
}

nonisolated struct CommunityFeedResponse: Decodable, Sendable {
    let generatedAt: String?
    let posts: [CommunityPost]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case posts
    }
}

nonisolated struct CommunityProfileStatsRPCParams: Encodable, Sendable {
    let profileIDs: [UUID]

    enum CodingKeys: String, CodingKey {
        case profileIDs = "p_profile_ids"
    }
}

nonisolated struct CommunityProfileStatsResponse: Decodable, Sendable {
    let generatedAt: String?
    let profiles: [CommunityProfileStats]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case profiles
    }
}

nonisolated struct CommunityProfileAuthLinkRecord: Decodable, Sendable {
    let authUserID: UUID
    let profileID: UUID

    enum CodingKeys: String, CodingKey {
        case authUserID = "auth_user_id"
        case profileID = "profile_id"
    }
}

nonisolated struct CommunityProfileUpdate: Encodable, Sendable {
    let nickname: String
    let avatarPath: String?
    let coverPath: String?
    let bio: String?
    let major: String?
    let grade: String?
    let profileEditedAt: String
    let isProfileComplete: Bool
    let showsEduVerificationBadge: Bool
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case nickname
        case avatarPath = "avatar_path"
        case coverPath = "cover_path"
        case bio
        case major
        case grade
        case profileEditedAt = "profile_edited_at"
        case isProfileComplete = "is_profile_complete"
        case showsEduVerificationBadge = "shows_edu_verification_badge"
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(nickname, forKey: .nickname)
        try container.encodeIfPresent(avatarPath, forKey: .avatarPath)
        if let coverPath {
            try container.encode(coverPath, forKey: .coverPath)
        } else {
            try container.encodeNil(forKey: .coverPath)
        }
        try container.encodeIfPresent(bio, forKey: .bio)
        try container.encodeIfPresent(major, forKey: .major)
        try container.encodeIfPresent(grade, forKey: .grade)
        try container.encode(profileEditedAt, forKey: .profileEditedAt)
        try container.encode(isProfileComplete, forKey: .isProfileComplete)
        try container.encode(showsEduVerificationBadge, forKey: .showsEduVerificationBadge)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

nonisolated struct CommunityPendingEmailUpdate: Encodable, Sendable {
    let pendingBoundEmail: String
    let emailVerificationSentAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case pendingBoundEmail = "pending_bound_email"
        case emailVerificationSentAt = "email_verification_sent_at"
        case updatedAt = "updated_at"
    }
}

nonisolated struct CommunityVerifiedEmailUpdate: Encodable, Sendable {
    let boundEmail: String
    let pendingBoundEmail: String?
    let emailVerificationSentAt: String?
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case boundEmail = "bound_email"
        case pendingBoundEmail = "pending_bound_email"
        case emailVerificationSentAt = "email_verification_sent_at"
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(boundEmail, forKey: .boundEmail)
        try container.encodeNil(forKey: .pendingBoundEmail)
        try container.encodeNil(forKey: .emailVerificationSentAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

nonisolated struct CommunityPostSoftDeleteRPCParams: Encodable, Sendable {
    let targetPostID: UUID

    enum CodingKeys: String, CodingKey {
        case targetPostID = "target_post_id"
    }
}

nonisolated struct CommunityCommentSoftDeleteRPCParams: Encodable, Sendable {
    let targetCommentID: UUID

    enum CodingKeys: String, CodingKey {
        case targetCommentID = "target_comment_id"
    }
}

nonisolated struct CommunityTermsAcceptanceRecord: Decodable, Sendable {
    let userID: UUID
    let termsVersion: String
    let acceptedAt: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case termsVersion = "terms_version"
        case acceptedAt = "accepted_at"
    }
}

nonisolated struct CommunityTermsAcceptanceRPCParams: Encodable, Sendable {
    let termsVersion: String

    enum CodingKeys: String, CodingKey {
        case termsVersion = "p_terms_version"
    }
}

nonisolated struct CommunityPostIDRPCParams: Encodable, Sendable {
    let postID: UUID

    enum CodingKeys: String, CodingKey {
        case postID = "p_post_id"
    }
}

nonisolated struct CommunityPollIDRPCParams: Encodable, Sendable {
    let pollID: UUID

    enum CodingKeys: String, CodingKey {
        case pollID = "p_poll_id"
    }
}

nonisolated struct CommunityPollListRPCParams: Encodable, Sendable {
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case limit = "p_limit"
    }
}

nonisolated struct CommunityRequestPollDeletionRPCParams: Encodable, Sendable {
    let pollID: UUID
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case pollID = "p_poll_id"
        case reason = "p_reason"
    }
}

nonisolated struct CommunityVotePollRPCParams: Encodable, Sendable {
    let pollID: UUID
    let optionID: UUID

    enum CodingKeys: String, CodingKey {
        case pollID = "p_poll_id"
        case optionID = "p_option_id"
    }
}

nonisolated struct CommunityCreatePollRPCParams: Encodable, Sendable {
    let question: String
    let detail: String?
    let options: [String]
    let closesAt: String?

    init(input: CreatePollInput) {
        question = String(input.normalizedQuestion.prefix(CommunityPollRules.maxQuestionLength))
        detail = input.normalizedDetail.map { String($0.prefix(CommunityPollRules.maxDetailLength)) }
        options = input.normalizedOptions
            .prefix(CommunityPollRules.maxOptions)
            .map { String($0.prefix(CommunityPollRules.maxOptionLength)) }
        closesAt = input.closesAt
    }

    enum CodingKeys: String, CodingKey {
        case question = "p_question"
        case detail = "p_detail"
        case options = "p_options"
        case closesAt = "p_closes_at"
    }
}

nonisolated struct CommunityBlockRecord: Decodable, Sendable {
    let blockerID: UUID
    let blockedID: UUID
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case blockerID = "blocker_id"
        case blockedID = "blocked_id"
        case createdAt = "created_at"
    }
}

nonisolated struct CommunityReportContentRPCParams: Encodable, Sendable {
    let targetType: CommunityReportTargetType
    let postID: UUID?
    let commentID: UUID?
    let reportedUserID: UUID?
    let reason: String
    let detail: String?

    enum CodingKeys: String, CodingKey {
        case targetType = "p_target_type"
        case postID = "p_post_id"
        case commentID = "p_comment_id"
        case reportedUserID = "p_reported_user_id"
        case reason = "p_reason"
        case detail = "p_detail"
    }
}

nonisolated struct CommunityBlockUserRPCParams: Encodable, Sendable {
    let blockedID: UUID
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case blockedID = "p_blocked_id"
        case reason = "p_reason"
    }
}

nonisolated struct CommunityUnblockUserRPCParams: Encodable, Sendable {
    let blockedID: UUID

    enum CodingKeys: String, CodingKey {
        case blockedID = "p_blocked_id"
    }
}

nonisolated struct CommunityPostRecord: Decodable, Sendable {
    let id: UUID
    let authorID: UUID
    let title: String
    let body: String
    let category: String?
    let isAnonymous: Bool
    let commentCount: Int
    let status: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case authorID = "author_id"
        case title
        case body
        case category
        case isAnonymous = "is_anonymous"
        case commentCount = "comment_count"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

nonisolated struct CommunityPendingPostContextRecord: Decodable, Sendable {
    let id: UUID
    let authorID: UUID
    let status: String

    enum CodingKeys: String, CodingKey {
        case id
        case authorID = "author_id"
        case status
    }
}

nonisolated struct CommunityPostRateLimitRecord: Decodable, Sendable {
    let id: UUID
}

nonisolated struct CommunityPollRecord: Decodable, Sendable {
    let id: UUID
    let authorID: UUID
    let question: String
    let detail: String?
    let status: String
    let totalVoteCount: Int
    let closesAt: String?
    let deletionStatus: String
    let deletionRequestedAt: String?
    let deletionReason: String?
    let deletionReviewedAt: String?
    let deletionReviewReason: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case authorID = "author_id"
        case question
        case detail
        case status
        case totalVoteCount = "total_vote_count"
        case closesAt = "closes_at"
        case deletionStatus = "deletion_status"
        case deletionRequestedAt = "deletion_requested_at"
        case deletionReason = "deletion_reason"
        case deletionReviewedAt = "deletion_reviewed_at"
        case deletionReviewReason = "deletion_review_reason"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        authorID = try container.decode(UUID.self, forKey: .authorID)
        question = try container.decode(String.self, forKey: .question)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        status = try container.decode(String.self, forKey: .status)
        totalVoteCount = try container.decode(Int.self, forKey: .totalVoteCount)
        closesAt = try container.decodeIfPresent(String.self, forKey: .closesAt)
        deletionStatus = try container.decodeIfPresent(String.self, forKey: .deletionStatus) ?? "none"
        deletionRequestedAt = try container.decodeIfPresent(String.self, forKey: .deletionRequestedAt)
        deletionReason = try container.decodeIfPresent(String.self, forKey: .deletionReason)
        deletionReviewedAt = try container.decodeIfPresent(String.self, forKey: .deletionReviewedAt)
        deletionReviewReason = try container.decodeIfPresent(String.self, forKey: .deletionReviewReason)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
    }
}

nonisolated struct CommunityPollVoteRecord: Decodable, Sendable {
    let pollID: UUID
    let optionID: UUID
    let userID: UUID
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case pollID = "poll_id"
        case optionID = "option_id"
        case userID = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

nonisolated struct CommunityPostLikeRecord: Decodable, Sendable {
    let postID: UUID
    let userID: UUID
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case userID = "user_id"
        case createdAt = "created_at"
    }
}

nonisolated struct CommunityPostFavoriteRecord: Decodable, Sendable {
    let postID: UUID
    let userID: UUID
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case userID = "user_id"
        case createdAt = "created_at"
    }
}

nonisolated struct CommunityNotificationRecord: Decodable, Sendable {
    let id: UUID
    let recipientID: UUID
    let actorID: UUID?
    let postID: UUID?
    let commentID: UUID?
    let type: CommunityNotificationType
    let title: String
    let body: String?
    let isRead: Bool
    let createdAt: String
    let dismissedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case recipientID = "recipient_id"
        case actorID = "actor_id"
        case postID = "post_id"
        case commentID = "comment_id"
        case type
        case title
        case body
        case isRead = "is_read"
        case createdAt = "created_at"
        case dismissedAt = "dismissed_at"
    }
}

nonisolated struct CommunityNotificationSettingsRecord: Decodable, Sendable {
    let userID: UUID
    let mutedAll: Bool
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case mutedAll = "muted_all"
        case updatedAt = "updated_at"
    }
}

nonisolated struct SiteAnnouncementRecord: Decodable, Sendable {
    let id: UUID
    let title: String
    let body: String
    let level: SiteAnnouncementLevel
    let status: String
    let publishedAt: String?
    let expiresAt: String?
    let createdBy: UUID
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case body
        case level
        case status
        case publishedAt = "published_at"
        case expiresAt = "expires_at"
        case createdBy = "created_by"
        case createdAt = "created_at"
    }
}

nonisolated struct SiteAnnouncementReadRecord: Decodable, Sendable {
    let announcementID: UUID
    let userID: UUID
    let readAt: String
    let dismissedAt: String?

    enum CodingKeys: String, CodingKey {
        case announcementID = "announcement_id"
        case userID = "user_id"
        case readAt = "read_at"
        case dismissedAt = "dismissed_at"
    }
}

nonisolated struct CommunityNotificationReadUpdate: Encodable, Sendable {
    let isRead: Bool

    enum CodingKeys: String, CodingKey {
        case isRead = "is_read"
    }
}

nonisolated struct CommunityNotificationDismissUpdate: Encodable, Sendable {
    let isRead: Bool
    let dismissedAt: String

    enum CodingKeys: String, CodingKey {
        case isRead = "is_read"
        case dismissedAt = "dismissed_at"
    }
}

nonisolated struct CommunityNotificationSettingsUpsert: Encodable, Sendable {
    let userID: UUID
    let mutedAll: Bool
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case mutedAll = "muted_all"
        case updatedAt = "updated_at"
    }
}

nonisolated struct CommunityNotificationRPCParams: Encodable, Sendable {
    let recipientID: UUID
    let actorID: UUID
    let postID: UUID
    let commentID: UUID?
    let type: CommunityNotificationType
    let title: String
    let body: String?

    enum CodingKeys: String, CodingKey {
        case recipientID = "p_recipient_id"
        case actorID = "p_actor_id"
        case postID = "p_post_id"
        case commentID = "p_comment_id"
        case type = "p_type"
        case title = "p_title"
        case body = "p_body"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(recipientID, forKey: .recipientID)
        try container.encode(actorID, forKey: .actorID)
        try container.encode(postID, forKey: .postID)
        if let commentID {
            try container.encode(commentID, forKey: .commentID)
        } else {
            try container.encodeNil(forKey: .commentID)
        }
        try container.encode(type, forKey: .type)
        try container.encode(title, forKey: .title)
        if let body {
            try container.encode(body, forKey: .body)
        } else {
            try container.encodeNil(forKey: .body)
        }
    }
}

nonisolated struct SiteAnnouncementReadInsert: Encodable, Sendable {
    let announcementID: UUID
    let userID: UUID
    let readAt: String
    let dismissedAt: String?

    enum CodingKeys: String, CodingKey {
        case announcementID = "announcement_id"
        case userID = "user_id"
        case readAt = "read_at"
        case dismissedAt = "dismissed_at"
    }
}

nonisolated struct FeedbackSubmissionInsert: Encodable, Sendable {
    let userID: UUID?
    let issueType: String
    let body: String
    let contact: String?
    let deviceInfo: [String: String]

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case issueType = "issue_type"
        case body
        case contact
        case deviceInfo = "device_info"
    }
}

nonisolated struct CatalogSuggestionInsert: Encodable, Sendable {
    let suggestionType: String
    let userID: UUID?
    let name: String
    let unit: String
    let teacherName: String?
    let category: String?
    let credit: Double?
    let initialStars: Int?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case suggestionType = "suggestion_type"
        case userID = "user_id"
        case name
        case unit
        case teacherName = "teacher_name"
        case category
        case credit
        case initialStars = "initial_stars"
        case note
    }
}

nonisolated struct TeacherRatingInsert: Encodable, Sendable {
    let teacherID: Int64
    let userID: UUID
    let stars: Int

    enum CodingKeys: String, CodingKey {
        case teacherID = "teacher_id"
        case userID = "user_id"
        case stars
    }
}

nonisolated struct TeacherRatingStarsUpdate: Encodable, Sendable {
    let stars: Int
}

nonisolated struct CourseRatingInsert: Encodable, Sendable {
    let courseID: Int64
    let userID: UUID
    let stars: Int

    enum CodingKeys: String, CodingKey {
        case courseID = "course_id"
        case userID = "user_id"
        case stars
    }
}

nonisolated struct DishRatingInsert: Encodable, Sendable {
    let dishID: Int64
    let userID: UUID
    let stars: Int

    enum CodingKeys: String, CodingKey {
        case dishID = "dish_id"
        case userID = "user_id"
        case stars
    }
}

nonisolated struct CommunityCreatePostV4RPCParams: Encodable, Sendable {
    let id: UUID
    let requestID: UUID
    let title: String
    let body: String
    let category: String?
    let isAnonymous: Bool
    let imageCount: Int
    let attachmentCount: Int

    enum CodingKeys: String, CodingKey {
        case id = "p_id"
        case requestID = "p_request_id"
        case title = "p_title"
        case body = "p_body"
        case category = "p_category"
        case isAnonymous = "p_is_anonymous"
        case imageCount = "p_image_count"
        case attachmentCount = "p_attachment_count"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(title, forKey: .title)
        try container.encode(body, forKey: .body)
        if let category {
            try container.encode(category, forKey: .category)
        } else {
            try container.encodeNil(forKey: .category)
        }
        try container.encode(isAnonymous, forKey: .isAnonymous)
        try container.encode(imageCount, forKey: .imageCount)
        try container.encode(attachmentCount, forKey: .attachmentCount)
    }
}

nonisolated struct CommunityPostImageRecord: Decodable, Sendable {
    let id: UUID
    let postID: UUID
    let path: String
    let thumbnailPath: String?
    let sortOrder: Int
    let width: Int?
    let height: Int?
    let thumbnailWidth: Int?
    let thumbnailHeight: Int?
    let fullWidth: Int?
    let fullHeight: Int?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case path
        case thumbnailPath = "thumbnail_path"
        case sortOrder = "sort_order"
        case width
        case height
        case thumbnailWidth = "thumbnail_width"
        case thumbnailHeight = "thumbnail_height"
        case fullWidth = "full_width"
        case fullHeight = "full_height"
        case createdAt = "created_at"
    }
}

nonisolated struct CommunityPostAttachmentRecord: Decodable, Sendable {
    let id: UUID
    let postID: UUID
    let path: String
    let displayName: String
    let contentType: String
    let fileExtension: String
    let byteSize: Int
    let sha256: String
    let sortOrder: Int
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case path
        case displayName = "display_name"
        case contentType = "content_type"
        case fileExtension = "file_extension"
        case byteSize = "byte_size"
        case sha256
        case sortOrder = "sort_order"
        case createdAt = "created_at"
    }
}

nonisolated struct CommunityUploadValidationRequest: Encodable, Sendable {
    let postID: String
    let fullPath: String
    let thumbnailPath: String

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case fullPath = "full_path"
        case thumbnailPath = "thumbnail_path"
    }
}

nonisolated struct CommunityAttachmentValidationRequest: Encodable, Sendable {
    let postID: String
    let objectPath: String
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case objectPath = "object_path"
        case displayName = "display_name"
    }
}

nonisolated struct CommunityAttachmentValidationResponse: Decodable, Sendable {
    let receiptID: UUID

    enum CodingKeys: String, CodingKey {
        case receiptID = "receipt_id"
    }
}

nonisolated struct CommunityAttachPostAttachmentRPCParams: Encodable, Sendable {
    let receiptID: UUID
    let attachmentID: UUID
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case receiptID = "p_receipt_id"
        case attachmentID = "p_attachment_id"
        case sortOrder = "p_sort_order"
    }
}

nonisolated struct CommunityAttachmentDownloadRequest: Encodable, Sendable {
    let attachmentID: UUID

    enum CodingKeys: String, CodingKey {
        case attachmentID = "attachment_id"
    }
}

nonisolated struct CommunityAttachmentDownloadResponse: Decodable, Sendable {
    let url: URL
    let displayName: String
    let contentType: String
    let byteSize: Int

    enum CodingKeys: String, CodingKey {
        case url
        case displayName = "display_name"
        case contentType = "content_type"
        case byteSize = "byte_size"
    }
}

nonisolated struct CommunityProfileUploadValidationRequest: Encodable, Sendable {
    let kind: String
    let objectPath: String

    enum CodingKeys: String, CodingKey {
        case kind
        case objectPath = "object_path"
    }
}

nonisolated struct CommunityProfileUploadValidationResponse: Decodable, Sendable {
    let validated: Bool
}

nonisolated struct CommunityUploadValidationResponse: Decodable, Sendable {
    let receiptID: UUID

    enum CodingKeys: String, CodingKey {
        case receiptID = "receipt_id"
    }
}

nonisolated struct CommunityAttachPostImageRPCParams: Encodable, Sendable {
    let receiptID: UUID
    let imageID: UUID
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case receiptID = "p_receipt_id"
        case imageID = "p_image_id"
        case sortOrder = "p_sort_order"
    }
}

nonisolated struct CommunityCommentRecord: Decodable, Sendable {
    let id: UUID
    let postID: UUID
    let authorID: UUID
    let body: String
    let isAnonymous: Bool
    let status: String
    let createdAt: String
    let updatedAt: String
    let parentCommentID: UUID?
    let replyToCommentID: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case authorID = "author_id"
        case body
        case isAnonymous = "is_anonymous"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case parentCommentID = "parent_comment_id"
        case replyToCommentID = "reply_to_comment_id"
    }
}

nonisolated struct CommunityCreateCommentV2RPCParams: Encodable, Sendable {
    let id: UUID
    let requestID: UUID
    let postID: UUID
    let body: String
    let parentCommentID: UUID?
    let replyToCommentID: UUID?
    let isAnonymous: Bool

    enum CodingKeys: String, CodingKey {
        case id = "p_id"
        case requestID = "p_request_id"
        case postID = "p_post_id"
        case body = "p_body"
        case parentCommentID = "p_parent_comment_id"
        case replyToCommentID = "p_reply_to_comment_id"
        case isAnonymous = "p_is_anonymous"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(postID, forKey: .postID)
        try container.encode(body, forKey: .body)
        if let parentCommentID {
            try container.encode(parentCommentID, forKey: .parentCommentID)
        } else {
            try container.encodeNil(forKey: .parentCommentID)
        }
        if let replyToCommentID {
            try container.encode(replyToCommentID, forKey: .replyToCommentID)
        } else {
            try container.encodeNil(forKey: .replyToCommentID)
        }
        try container.encode(isAnonymous, forKey: .isAnonymous)
    }
}

nonisolated struct CommunityCommentThreadPageRPCParams: Encodable, Sendable {
    let postID: UUID
    let afterCreatedAt: String?
    let afterID: UUID?
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case postID = "p_post_id"
        case afterCreatedAt = "p_after_created_at"
        case afterID = "p_after_id"
        case limit = "p_limit"
    }
}

nonisolated struct CommunityCommentThreadPageRecord: Decodable, Sendable {
    let comments: [CommunityThreadCommentRecord]
    let hasMore: Bool
    let nextCursorCreatedAt: String?
    let nextCursorID: UUID?

    enum CodingKeys: String, CodingKey {
        case comments
        case hasMore = "has_more"
        case nextCursorCreatedAt = "next_cursor_created_at"
        case nextCursorID = "next_cursor_id"
    }
}

nonisolated struct CommunityThreadCommentRecord: Decodable, Sendable {
    let threadRootID: UUID
    let id: UUID
    let postID: UUID
    let authorID: UUID
    let body: String
    let isAnonymous: Bool
    let status: String
    let createdAt: String
    let updatedAt: String
    let parentCommentID: UUID?
    let replyToCommentID: UUID?
    let replyToAuthorID: UUID?
    let replyTargetIsVisible: Bool
    let likeCount: Int
    let viewerHasLiked: Bool
    let isDeletedPlaceholder: Bool

    enum CodingKeys: String, CodingKey {
        case threadRootID = "thread_root_id"
        case id
        case postID = "post_id"
        case authorID = "author_id"
        case body
        case isAnonymous = "is_anonymous"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case parentCommentID = "parent_comment_id"
        case replyToCommentID = "reply_to_comment_id"
        case replyToAuthorID = "reply_to_author_id"
        case replyTargetIsVisible = "reply_target_is_visible"
        case likeCount = "like_count"
        case viewerHasLiked = "viewer_has_liked"
        case isDeletedPlaceholder = "is_deleted_placeholder"
    }
}

nonisolated struct CommunityCommentIDRPCParams: Encodable, Sendable {
    let commentID: UUID
    let requestID: UUID

    enum CodingKeys: String, CodingKey {
        case commentID = "p_comment_id"
        case requestID = "p_request_id"
    }
}

nonisolated struct CommunityCommentLikeStateRecord: Decodable, Sendable {
    let commentID: UUID
    let likeCount: Int
    let viewerHasLiked: Bool

    enum CodingKeys: String, CodingKey {
        case commentID = "comment_id"
        case likeCount = "like_count"
        case viewerHasLiked = "viewer_has_liked"
    }
}

nonisolated enum CommunityCommentLikeResponseValidator {
    static func state(
        from records: [CommunityCommentLikeStateRecord]
    ) throws -> CommunityCommentLikeState {
        guard records.count == 1, let record = records.first else {
            throw CommunityServiceError.edgeFunctionRejected("评论点赞返回数据异常，请稍后重试。")
        }
        return CommunityCommentLikeState(
            commentID: record.commentID,
            likeCount: record.likeCount,
            viewerHasLiked: record.viewerHasLiked
        )
    }
}
