import Foundation
import UIKit
import XCTest
@testable import Leafy

@MainActor
final class CommunityPostDraftAndCardTests: XCTestCase {
    func testDraftRepositoryRestoresMediaSortsAndIsolatesOwners() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let ownerA = UUID()
        let ownerB = UUID()
        let firstID = UUID()
        let secondID = UUID()
        let image = try makeImageUpload()
        let attachment = try makeAttachment(in: fixture.externalDirectory)

        let firstPayload = try fixture.repository.saveDraft(
            id: firstID,
            ownerProfileID: ownerA,
            input: makeInput(title: "第一份"),
            images: [image],
            attachments: [attachment]
        )
        let secondPayload = try fixture.repository.saveDraft(
            id: secondID,
            ownerProfileID: ownerA,
            input: makeInput(title: "第二份"),
            images: [],
            attachments: []
        )

        XCTAssertEqual(
            try fixture.repository.listDrafts(ownerProfileID: ownerA).map(\.id),
            [secondID, firstID]
        )
        XCTAssertTrue(try fixture.repository.listDrafts(ownerProfileID: ownerB).isEmpty)
        XCTAssertLessThan(firstPayload.draft.updatedAt, secondPayload.draft.updatedAt)

        let restartedRepository = LocalCommunityPostDraftRepository(
            rootDirectory: fixture.storageRoot,
            appliesFileProtection: false
        )
        let restored = try restartedRepository.loadDraft(id: firstID, ownerProfileID: ownerA)
        XCTAssertEqual(restored.draft.input.title, "第一份")
        XCTAssertEqual(restored.images.map(\.data), [image.data])
        XCTAssertEqual(restored.attachments.map(\.displayName), [attachment.displayName])
        XCTAssertEqual(
            try restartedRepository.thumbnailData(
                draftID: firstID,
                ownerProfileID: ownerA,
                imageID: image.id
            ).isEmpty,
            false
        )

        XCTAssertThrowsError(
            try restartedRepository.loadDraft(id: firstID, ownerProfileID: ownerB)
        )

        try restartedRepository.deleteDraft(id: firstID, ownerProfileID: ownerA)
        XCTAssertThrowsError(
            try restartedRepository.loadDraft(id: firstID, ownerProfileID: ownerA)
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: draftDirectory(
                    fixture: fixture,
                    ownerID: ownerA,
                    draftID: firstID
                ).path
            )
        )
    }

    func testDraftRepositoryReportsMissingMediaAndCorruptManifest() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let ownerID = UUID()
        let missingMediaDraftID = UUID()
        let corruptDraftID = UUID()
        let image = try makeImageUpload()
        let payload = try fixture.repository.saveDraft(
            id: missingMediaDraftID,
            ownerProfileID: ownerID,
            input: makeInput(),
            images: [image],
            attachments: []
        )

        let mediaURL = draftDirectory(
            fixture: fixture,
            ownerID: ownerID,
            draftID: missingMediaDraftID
        ).appendingPathComponent(try XCTUnwrap(payload.draft.images.first?.fileName))
        try FileManager.default.removeItem(at: mediaURL)

        XCTAssertThrowsError(
            try fixture.repository.loadDraft(
                id: missingMediaDraftID,
                ownerProfileID: ownerID
            )
        ) { error in
            guard case CommunityPostDraftError.missingImage = error else {
                return XCTFail("Expected missingImage, got \(error)")
            }
        }

        let corruptDirectory = draftDirectory(
            fixture: fixture,
            ownerID: ownerID,
            draftID: corruptDraftID
        )
        try FileManager.default.createDirectory(
            at: corruptDirectory,
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(
            to: corruptDirectory.appendingPathComponent("manifest.json"),
            options: .atomic
        )

        XCTAssertThrowsError(
            try fixture.repository.listDrafts(ownerProfileID: ownerID)
        ) { error in
            guard case CommunityPostDraftError.corruptManifest = error else {
                return XCTFail("Expected corruptManifest, got \(error)")
            }
        }
    }

    func testBlankDraftContentDoesNotQualifyForAutosave() {
        let draft = CommunityPostDraft(
            id: UUID(),
            ownerProfileID: UUID(),
            createdAt: Date(),
            updatedAt: Date(),
            input: makeInput(title: " \n", body: "\t"),
            images: [],
            attachments: []
        )

        XCTAssertFalse(draft.hasMeaningfulContent)
    }

    func testNewComposerRequiresExplicitDraftChoice() {
        XCTAssertEqual(
            CommunityComposerDraftPolicy.closeAction(
                draftExists: false,
                hasMeaningfulContent: false
            ),
            .dismiss
        )
        XCTAssertEqual(
            CommunityComposerDraftPolicy.closeAction(
                draftExists: false,
                hasMeaningfulContent: true
            ),
            .askToSaveNewDraft
        )
        XCTAssertEqual(
            CommunityComposerDraftPolicy.closeAction(
                draftExists: true,
                hasMeaningfulContent: true
            ),
            .saveExistingDraft
        )
    }

    func testOnlyExistingDraftAutosaves() {
        XCTAssertFalse(CommunityComposerDraftPolicy.shouldAutosave(draftExists: false))
        XCTAssertTrue(CommunityComposerDraftPolicy.shouldAutosave(draftExists: true))
    }

    func testPublishHandoffKeepsDraftWhenEnqueueFailsAndDeletesAfterSuccess() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let ownerID = UUID()
        let draftID = UUID()
        _ = try fixture.repository.saveDraft(
            id: draftID,
            ownerProfileID: ownerID,
            input: makeInput(),
            images: [],
            attachments: []
        )

        XCTAssertThrowsError(
            try CommunityPostDraftPublishHandoff.enqueue(
                draftID: draftID,
                ownerProfileID: ownerID,
                repository: fixture.repository
            ) {
                throw TestPublishError.enqueueFailed
            }
        )
        XCTAssertNoThrow(
            try fixture.repository.loadDraft(id: draftID, ownerProfileID: ownerID)
        )

        let taskID = UUID()
        let result = try CommunityPostDraftPublishHandoff.enqueue(
            draftID: draftID,
            ownerProfileID: ownerID,
            repository: fixture.repository
        ) {
            taskID
        }
        XCTAssertEqual(result.publicationTaskID, taskID)
        XCTAssertTrue(result.deletedDraft)
        XCTAssertNil(result.draftCleanupError)
        XCTAssertThrowsError(
            try fixture.repository.loadDraft(id: draftID, ownerProfileID: ownerID)
        )
    }

    func testDraftRepositoryReportsStorageWriteFailure() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        try FileManager.default.createDirectory(
            at: fixture.storageRoot,
            withIntermediateDirectories: true
        )
        let blockedRoot = fixture.storageRoot.appendingPathComponent(
            "CommunityPostDrafts",
            isDirectory: false
        )
        try Data("blocked".utf8).write(to: blockedRoot, options: .atomic)
        let repository = LocalCommunityPostDraftRepository(
            rootDirectory: fixture.storageRoot,
            appliesFileProtection: false
        )

        XCTAssertThrowsError(
            try repository.saveDraft(
                id: UUID(),
                ownerProfileID: UUID(),
                input: makeInput(),
                images: [],
                attachments: []
            )
        ) { error in
            guard case CommunityPostDraftError.storageFailure = error else {
                return XCTFail("Expected storageFailure, got \(error)")
            }
        }
    }

    func testLongCardLayoutPreservesSnapshotContentAndGrowsWithBody() {
        let shortBody = "第一段包含中文、English words 和 Emoji 👨‍👩‍👧‍👦🌿。"
        let longBody = shortBody + String(repeating: "\n长段落🙂abcdef。", count: 80)
        let shortSnapshot = makeCardSnapshot(body: shortBody)
        let longSnapshot = makeCardSnapshot(body: longBody)

        XCTAssertEqual(longSnapshot.body, longBody)
        XCTAssertEqual(
            longSnapshot.attachmentNames,
            ["说明.pdf", "数据.xlsx", "忽略.docx"]
        )
        XCTAssertGreaterThan(
            CommunityPostCardLayout.estimatedHeight(snapshot: longSnapshot, photos: []),
            CommunityPostCardLayout.estimatedHeight(snapshot: shortSnapshot, photos: [])
        )
    }

    func testRendererProducesSingle1080PixelWideLongJPEG() throws {
        let photo = try XCTUnwrap(
            UIGraphicsImageRenderer(size: CGSize(width: 80, height: 120))
                .image { context in
                    UIColor.systemGreen.setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 80, height: 120))
                }
                .jpegData(compressionQuality: 0.9)
        )
        let snapshot = CommunityPostCardSnapshot(
            authorName: "匿名同学",
            avatarData: nil,
            dateText: "7月28日",
            category: "校园生活",
            title: "卡片测试",
            body: String(repeating: "这是一段用于验证长图高度的正文。\n", count: 40),
            attachmentNames: ["附件.pdf"],
            photoData: [photo],
            isAnonymous: true
        )

        let url = try CommunityPostCardGenerator.render(snapshot)
        defer { CommunityPostCardGenerator.deleteRenderedFile(url) }

        let image = try XCTUnwrap(UIImage(contentsOfFile: url.path))
        XCTAssertEqual(image.cgImage?.width, 1_080)
        XCTAssertGreaterThan(image.cgImage?.height ?? 0, 1_920)
        XCTAssertLessThanOrEqual(
            image.cgImage?.height ?? .max,
            CommunityPostCardLayout.maxPixelHeight
        )
        XCTAssertEqual(url.lastPathComponent, "MyLeafy-card.jpg")
    }

    func testRendererRejectsUnsafeLongImageWithoutCreatingFiles() {
        CommunityPostCardGenerator.cleanupStaleRenderedFiles()
        let snapshot = makeCardSnapshot(body: String(repeating: "综", count: 10_000))

        XCTAssertThrowsError(try CommunityPostCardGenerator.render(snapshot)) { error in
            guard case CommunityPostCardGenerationError.contentTooLong = error else {
                return XCTFail("Expected contentTooLong, got \(error)")
            }
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: CommunityPostCardGenerator.temporaryRoot.path
            )
        )
    }

    func testAnonymousPublishedPostSnapshotDoesNotExposeAuthorIdentity() async throws {
        let authorID = UUID()
        let post = CommunityPost(
            id: UUID(),
            authorID: authorID,
            title: "匿名标题",
            body: "匿名正文",
            category: "校园生活",
            isAnonymous: true,
            commentCount: 0,
            likeCount: 0,
            status: "published",
            createdAt: "2026-07-28T12:00:00Z",
            updatedAt: "2026-07-28T12:00:00Z",
            viewerHasLiked: false,
            author: nil,
            images: []
        )

        let snapshot = try await CommunityPostCardGenerator.snapshot(from: post)

        XCTAssertEqual(snapshot.authorName, "匿名同学")
        XCTAssertNil(snapshot.avatarData)
        XCTAssertTrue(snapshot.isAnonymous)
        XCTAssertFalse(String(describing: snapshot).contains(authorID.uuidString))
    }

    private func makeInput(
        title: String = "标题",
        body: String = "正文"
    ) -> CreatePostInput {
        CreatePostInput(
            title: title,
            body: body,
            category: "校园生活",
            isAnonymous: false
        )
    }

    private func makeCardSnapshot(body: String) -> CommunityPostCardSnapshot {
        CommunityPostCardSnapshot(
            authorName: "测试同学",
            avatarData: nil,
            dateText: "7月29日",
            category: "校园生活",
            title: "长图测试",
            body: body,
            attachmentNames: ["说明.pdf", "数据.xlsx", "忽略.docx"],
            photoData: [],
            isAnonymous: false
        )
    }

    private func makeImageUpload() throws -> CommunityImageUpload {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 16)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 16))
        }
        return CommunityImageUpload(
            data: try XCTUnwrap(image.jpegData(compressionQuality: 0.9)),
            mimeType: "image/jpeg",
            fileExtension: "jpg",
            width: 24,
            height: 16
        )
    }

    private func makeAttachment(in directory: URL) throws -> CommunityAttachmentUpload {
        let url = directory.appendingPathComponent("notes.md")
        let data = Data("# Notes".utf8)
        try data.write(to: url, options: .atomic)
        return CommunityAttachmentUpload(
            localURL: url,
            displayName: "notes.md",
            contentType: "text/markdown",
            fileExtension: "md",
            byteSize: data.count
        )
    }

    private func makeFixture() throws -> DraftFixture {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("CommunityDraftTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        let storage = base.appendingPathComponent("Storage", isDirectory: true)
        let external = base.appendingPathComponent("External", isDirectory: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        return DraftFixture(
            baseDirectory: base,
            storageRoot: storage,
            externalDirectory: external,
            repository: LocalCommunityPostDraftRepository(
                rootDirectory: storage,
                appliesFileProtection: false
            )
        )
    }

    private func draftDirectory(
        fixture: DraftFixture,
        ownerID: UUID,
        draftID: UUID
    ) -> URL {
        fixture.storageRoot
            .appendingPathComponent("CommunityPostDrafts", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
            .appendingPathComponent(ownerID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(draftID.uuidString.lowercased(), isDirectory: true)
    }
}

private enum TestPublishError: Error {
    case enqueueFailed
}

private struct DraftFixture {
    let baseDirectory: URL
    let storageRoot: URL
    let externalDirectory: URL
    let repository: LocalCommunityPostDraftRepository

    func cleanup() {
        try? FileManager.default.removeItem(at: baseDirectory)
    }
}
