import Foundation

nonisolated protocol CommunityDirectMediaUploading: Sendable {
    func uploadMedia(kind: String, taskID: UUID, mediaID: UUID, name: String, contentType: String, fileURL: URL, descriptor: CommunityBackgroundTransferDescriptor) async throws -> String
}

extension CloudflareCommunityRepository: CommunityDirectMediaUploading {
    func pendingPostContext(postID: UUID) async throws -> CommunityPendingPostContext? {
        struct Context: Decodable { let id: UUID; let author_id: UUID; let status: String }
        let result: Context? = try await get("/v1/community/posts/\(postID)/pending")
        return result.map { CommunityPendingPostContext(postID: $0.id, authorID: $0.author_id, status: $0.status) }
    }
    func abortPendingPost(postID: UUID) async throws { try await perform("/v1/community/posts/\(postID)/abort") }
    func createPendingPost(id: UUID, input: CreatePostInput, imageCount: Int, attachmentCount: Int) async throws -> UUID { try await createPendingPost(id: id, requestID: id, input: input, imageCount: imageCount, attachmentCount: attachmentCount) }
    func createPendingPost(id: UUID, requestID: UUID, input: CreatePostInput, imageCount: Int, attachmentCount: Int) async throws -> UUID {
        struct Input: Encodable { let id: UUID; let request_id: UUID; let title: String; let body: String; let category: String?; let is_anonymous: Bool; let image_count: Int; let attachment_count: Int }
        struct Result: Decodable { let id: UUID }
        let result: Result = try await request("/v1/community/posts", body: Input(id: id, request_id: requestID, title: input.title, body: input.body, category: input.category, is_anonymous: input.isAnonymous, image_count: imageCount, attachment_count: attachmentCount))
        return result.id
    }
    func validateAndAttachPostImage(postID: UUID, imageID: UUID, fullPath: String, thumbnailPath: String, sortOrder: Int) async throws {
        struct Receipt: Decodable { let receipt_id: UUID }
        struct Attach: Encodable { let receipt_id: UUID; let id: UUID; let sort_order: Int }
        let receipt: Receipt = try await request("/v1/files/validate-images", body: ["post_id":postID.uuidString,"full_path":fullPath,"thumbnail_path":thumbnailPath])
        try await perform("/v1/files/attach-image", body: Attach(receipt_id: receipt.receipt_id, id: imageID, sort_order: sortOrder))
    }
    func validateAndAttachPostAttachment(postID: UUID, attachmentID: UUID, objectPath: String, displayName: String, sortOrder: Int) async throws {
        struct Receipt: Decodable { let receipt_id: UUID }
        struct Attach: Encodable { let receipt_id: UUID; let id: UUID; let sort_order: Int }
        let receipt: Receipt = try await request("/v1/files/validate-attachment", body: ["post_id":postID.uuidString,"object_path":objectPath,"display_name":displayName])
        try await perform("/v1/files/attach-attachment", body: Attach(receipt_id: receipt.receipt_id, id: attachmentID, sort_order: sortOrder))
    }
    func attachmentDownloadURL(attachmentID: UUID) async throws -> CommunityAttachmentDownload {
        let response: CommunityAttachmentDownloadResponse = try await request("/v1/files/attachment-download", body: ["attachment_id":attachmentID.uuidString])
        return CommunityAttachmentDownload(url: response.url, displayName: response.displayName, contentType: response.contentType, byteSize: response.byteSize)
    }
    func requireCapabilities(for mediaKinds: Set<CommunityPublishMediaKind>) async throws {
        // Versioned API contract owns media support; profile authorization is
        // checked before creating any background upload task.
        guard let profile = try await fetchCurrentProfile(), profile.isProfileComplete else { throw CommunityServiceError.profileCompletionRequired }
        guard try await hasAcceptedCurrentTerms() else { throw CommunityServiceError.termsAcceptanceRequired }
    }
    func uploadCredentials() async throws -> CommunityUploadCredentials {
        let backend = try client()
        return try await CommunityUploadCredentials(baseURL: backend.baseURL, publishableKey: nil, accessToken: backend.requireBearerToken())
    }
    func uploadMedia(kind: String, taskID: UUID, mediaID: UUID, name: String, contentType: String, fileURL: URL, descriptor: CommunityBackgroundTransferDescriptor) async throws -> String {
        let request = try await client().uploadRequest(kind: kind, uploadID: mediaID, postID: taskID, name: name, contentType: contentType)
        let response = try await CommunityBackgroundTransferManager.shared.upload(request: request, fileURL: fileURL, descriptor: descriptor)
        struct Uploaded: Decodable { let path: String }
        return try JSONDecoder().decode(Uploaded.self, from: response.data).path
    }
    @MainActor
    func enqueuePostPublication(input: CreatePostInput, images: [CommunityImageUpload], attachments: [CommunityAttachmentUpload]) throws -> UUID {
        try CommunityPublishCoordinator.shared.enqueue(input: input, images: images, attachments: attachments)
    }
}
