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

nonisolated struct CommunityProfileStatsResponse: Decodable, Sendable {
    let generatedAt: String?
    let profiles: [CommunityProfileStats]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case profiles
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
