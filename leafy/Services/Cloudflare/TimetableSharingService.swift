import Foundation

nonisolated enum TimetableSharingError: LocalizedError {
    case missingProfile
    case profileCompletionRequired
    case emptySnapshot
    case timetableNotPublished
    case invalidInviteCode
    case inviteExpired
    case inviteUsed
    case inviteSelf
    case inviteCollision
    case notShareOwner
    case backend(String)

    var errorDescription: String? {
        switch self {
        case .missingProfile:
            return "共享课表需要先建立社区身份，请稍后重试。"
        case .profileCompletionRequired:
            return "请先完善社区昵称后再使用共享课表。"
        case .emptySnapshot:
            return "本地课表为空，请先在课表页或缓存与同步中同步课表。"
        case .timetableNotPublished:
            return "请先发布或更新你的课表，再生成邀请码。"
        case .invalidInviteCode:
            return "邀请码无效，请检查后重新输入。"
        case .inviteExpired:
            return "邀请码已过期，请让对方重新生成。"
        case .inviteUsed:
            return "邀请码已经被使用，请让对方重新生成。"
        case .inviteSelf:
            return "不能接受自己的共享课表邀请码。"
        case .inviteCollision:
            return "邀请码生成冲突，请重新生成一次。"
        case .notShareOwner:
            return "你没有权限撤销这条共享关系。"
        case .backend(let message):
            return message
        }
    }
}

nonisolated enum TimetableSharingService {
    static let shared: any TimetableSharing = CloudflareTimetableSharingService()
    static func normalizeInviteCode(_ code: String) -> String {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        return code.uppercased().filter { allowed.contains($0) }
    }
}
