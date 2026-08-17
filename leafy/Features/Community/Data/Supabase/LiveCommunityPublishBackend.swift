import Foundation
import os
import Supabase

nonisolated struct LiveCommunityPublishBackend: CommunityPublishBackend {
    private let service = CommunityService.shared

    func pendingPostContext(postID: UUID) async throws -> CommunityPendingPostContext? {
        try await service.pendingPostContext(postID: postID)
    }

    func abortPendingPost(postID: UUID) async throws {
        try await service.abortPendingPost(postID: postID)
    }

    func createPendingPost(
        id: UUID,
        input: CreatePostInput,
        imageCount: Int,
        attachmentCount: Int
    ) async throws -> UUID {
        try await service.createPendingPost(
            id: id,
            input: input,
            imageCount: imageCount,
            attachmentCount: attachmentCount
        )
    }

    func createPendingPost(
        id: UUID,
        requestID: UUID,
        input: CreatePostInput,
        imageCount: Int,
        attachmentCount: Int
    ) async throws -> UUID {
        try await service.createPendingPost(
            id: id,
            requestID: requestID,
            input: input,
            imageCount: imageCount,
            attachmentCount: attachmentCount
        )
    }

    func fetchPost(postID: UUID) async throws -> CommunityPost? {
        try await service.fetchPost(postID: postID)
    }

    func validateAndAttachPostImage(
        postID: UUID,
        imageID: UUID,
        fullPath: String,
        thumbnailPath: String,
        sortOrder: Int
    ) async throws {
        try await service.validateAndAttachPostImage(
            postID: postID,
            imageID: imageID,
            fullPath: fullPath,
            thumbnailPath: thumbnailPath,
            sortOrder: sortOrder
        )
    }

    func validateAndAttachPostAttachment(
        postID: UUID,
        attachmentID: UUID,
        objectPath: String,
        displayName: String,
        sortOrder: Int
    ) async throws {
        try await service.validateAndAttachPostAttachment(
            postID: postID,
            attachmentID: attachmentID,
            objectPath: objectPath,
            displayName: displayName,
            sortOrder: sortOrder
        )
    }

    func requireCapabilities(for mediaKinds: Set<CommunityPublishMediaKind>) async throws {
        let cachedCapabilities = try await SupabaseBackendClient.shared.capabilities()
        let capabilities = try await CommunityPublishCapabilityRequirements.refreshingIfNeeded(
            cachedCapabilities,
            mediaKinds: mediaKinds
        ) {
            try await SupabaseBackendClient.shared.capabilities(forceRefresh: true)
        }
        let missingRPCs = CommunityPublishCapabilityRequirements.missingRPCs(
            in: capabilities,
            mediaKinds: mediaKinds
        )
        let missingEdgeFunctions = CommunityPublishCapabilityRequirements.missingEdgeFunctions(
            in: capabilities,
            mediaKinds: mediaKinds
        )
        guard missingRPCs.isEmpty, missingEdgeFunctions.isEmpty else {
            CommunityDiagnostics.log.error(
                """
                Community publish capabilities unavailable after refresh. \
                version=\(capabilities.version, privacy: .public) \
                media_kinds=\(mediaKinds.map(\.rawValue).sorted().joined(separator: ","), privacy: .public) \
                missing_rpcs=\(missingRPCs.joined(separator: ","), privacy: .public) \
                missing_edge_functions=\(missingEdgeFunctions.joined(separator: ","), privacy: .public)
                """
            )
            throw CommunityServiceError.edgeFunctionRejected("社区服务需要更新后才能发布，请稍后重试。")
        }
    }

    func uploadCredentials() async throws -> CommunityUploadCredentials {
        let client = try LeafySupabase.shared.requireClient()
        let session = try await client.auth.session
        let config = try LeafySupabase.shared.requireConfig()
        return CommunityUploadCredentials(
            baseURL: config.url,
            publishableKey: config.publishableKey,
            accessToken: session.accessToken
        )
    }
}
