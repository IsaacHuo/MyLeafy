import Foundation

nonisolated struct CommunityUploadCredentials: Sendable {
    let baseURL: URL
    let publishableKey: String
    let accessToken: String
}

nonisolated protocol CommunityPublishBackend: Sendable {
    func pendingPostContext(postID: UUID) async throws -> CommunityPendingPostContext?
    func abortPendingPost(postID: UUID) async throws
    func createPendingPost(
        id: UUID,
        input: CreatePostInput,
        imageCount: Int,
        attachmentCount: Int
    ) async throws -> UUID
    func createPendingPost(
        id: UUID,
        requestID: UUID,
        input: CreatePostInput,
        imageCount: Int,
        attachmentCount: Int
    ) async throws -> UUID
    func fetchPost(postID: UUID) async throws -> CommunityPost?
    func validateAndAttachPostImage(
        postID: UUID,
        imageID: UUID,
        fullPath: String,
        thumbnailPath: String,
        sortOrder: Int
    ) async throws
    func validateAndAttachPostAttachment(
        postID: UUID,
        attachmentID: UUID,
        objectPath: String,
        displayName: String,
        sortOrder: Int
    ) async throws
    func requireCapabilities(for mediaKinds: Set<CommunityPublishMediaKind>) async throws
    func uploadCredentials() async throws -> CommunityUploadCredentials
}

extension CommunityPublishBackend {
    func createPendingPost(
        id: UUID,
        requestID _: UUID,
        input: CreatePostInput,
        imageCount: Int,
        attachmentCount: Int
    ) async throws -> UUID {
        try await createPendingPost(
            id: id,
            input: input,
            imageCount: imageCount,
            attachmentCount: attachmentCount
        )
    }
}
