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
