import Foundation

nonisolated struct CommunityPostDraftImageRecord: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let fileName: String
    let thumbnailFileName: String
    let mimeType: String
    let fileExtension: String
    let width: Int?
    let height: Int?
    let sortOrder: Int
}

nonisolated struct CommunityPostDraftAttachmentRecord: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let fileName: String
    let displayName: String
    let contentType: String
    let fileExtension: String
    let byteSize: Int
    let sortOrder: Int
}

nonisolated struct CommunityPostDraft: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let ownerProfileID: UUID
    let createdAt: Date
    let updatedAt: Date
    let input: CreatePostInput
    let images: [CommunityPostDraftImageRecord]
    let attachments: [CommunityPostDraftAttachmentRecord]

    var displayTitle: String {
        let value = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? L10n.text("无标题草稿") : value
    }

    var bodyPreview: String {
        let value = input.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? L10n.text("暂无正文") : String(value.prefix(120))
    }

    var hasMeaningfulContent: Bool {
        !input.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !input.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !images.isEmpty
            || !attachments.isEmpty
    }
}

nonisolated struct CommunityPostDraftEditorPayload: Sendable {
    let draft: CommunityPostDraft
    let images: [CommunityImageUpload]
    let attachments: [CommunityAttachmentUpload]
}

nonisolated enum CommunityPostDraftError: LocalizedError, Sendable {
    case draftNotFound
    case ownerMismatch
    case corruptManifest
    case missingImage(String)
    case missingAttachment(String)
    case invalidImage(String)
    case storageFailure(String)

    var errorDescription: String? {
        switch self {
        case .draftNotFound:
            return L10n.text("草稿已不存在。")
        case .ownerMismatch:
            return L10n.text("这份草稿不属于当前社区账号。")
        case .corruptManifest:
            return L10n.text("草稿数据已损坏，无法读取。")
        case .missingImage(let name):
            return L10n.text("草稿图片“%@”已丢失，请移除后重试。", name)
        case .missingAttachment(let name):
            return L10n.text("草稿附件“%@”已丢失，请重新添加。", name)
        case .invalidImage(let name):
            return L10n.text("草稿图片“%@”无法读取，请移除后重试。", name)
        case .storageFailure(let message):
            return L10n.text("草稿保存失败：%@", message)
        }
    }
}
