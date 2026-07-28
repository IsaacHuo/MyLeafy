import Foundation

@MainActor
protocol CommunityPostDraftRepository {
    func listDrafts(ownerProfileID: UUID) throws -> [CommunityPostDraft]
    func loadDraft(id: UUID, ownerProfileID: UUID) throws -> CommunityPostDraftEditorPayload
    @discardableResult
    func saveDraft(
        id: UUID,
        ownerProfileID: UUID,
        input: CreatePostInput,
        images: [CommunityImageUpload],
        attachments: [CommunityAttachmentUpload]
    ) throws -> CommunityPostDraftEditorPayload
    func deleteDraft(id: UUID, ownerProfileID: UUID) throws
    func thumbnailData(
        draftID: UUID,
        ownerProfileID: UUID,
        imageID: UUID
    ) throws -> Data
}

struct CommunityPostDraftPublishHandoffResult {
    let publicationTaskID: UUID
    let deletedDraft: Bool
    let draftCleanupError: String?
}

@MainActor
enum CommunityPostDraftPublishHandoff {
    static func enqueue(
        draftID: UUID?,
        ownerProfileID: UUID?,
        repository: any CommunityPostDraftRepository,
        operation: () throws -> UUID
    ) throws -> CommunityPostDraftPublishHandoffResult {
        let publicationTaskID = try operation()
        guard let draftID else {
            return CommunityPostDraftPublishHandoffResult(
                publicationTaskID: publicationTaskID,
                deletedDraft: false,
                draftCleanupError: nil
            )
        }
        guard let ownerProfileID else {
            return CommunityPostDraftPublishHandoffResult(
                publicationTaskID: publicationTaskID,
                deletedDraft: false,
                draftCleanupError: L10n.text("当前社区身份不可用，草稿未能删除。")
            )
        }

        do {
            try repository.deleteDraft(id: draftID, ownerProfileID: ownerProfileID)
            return CommunityPostDraftPublishHandoffResult(
                publicationTaskID: publicationTaskID,
                deletedDraft: true,
                draftCleanupError: nil
            )
        } catch {
            return CommunityPostDraftPublishHandoffResult(
                publicationTaskID: publicationTaskID,
                deletedDraft: false,
                draftCleanupError: error.localizedDescription
            )
        }
    }
}
