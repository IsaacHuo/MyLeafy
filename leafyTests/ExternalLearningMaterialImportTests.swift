import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import Leafy

final class ExternalLearningMaterialImportTests: XCTestCase {
    func testExternalImportSupportsOnlyCommonStudyDocumentTypes() {
        XCTAssertTrue(ExternalLearningMaterialImport.isSupported(filename: "资料.pdf"))
        XCTAssertTrue(ExternalLearningMaterialImport.isSupported(
            filename: "图片.heic",
            contentTypeIdentifier: UTType.heic.identifier
        ))
        XCTAssertTrue(ExternalLearningMaterialImport.isSupported(filename: "课程.docx"))
        XCTAssertTrue(ExternalLearningMaterialImport.isSupported(filename: "答辩.pptx"))

        XCTAssertFalse(ExternalLearningMaterialImport.isSupported(filename: "成绩.xlsx"))
        XCTAssertFalse(ExternalLearningMaterialImport.isSupported(filename: "说明.txt"))
        XCTAssertFalse(ExternalLearningMaterialImport.isSupported(filename: "资料.zip"))
        XCTAssertFalse(ExternalLearningMaterialImport.isSupported(filename: "压缩包.rar"))
    }

    func testExternalImportManifestRoundTripsAndCleansStagingBatch() throws {
        let root = temporaryDirectory()
        let store = ExternalLearningMaterialImportStore(rootDirectory: root)
        let sourceURL = root.appendingPathComponent("source.pdf")
        try Data("pdf".utf8).write(to: sourceURL)
        let batchID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000888"))

        let manifest = try store.makeBatch(from: [sourceURL], source: .shareExtension, id: batchID)

        XCTAssertEqual(manifest.id, batchID)
        XCTAssertEqual(manifest.source, .shareExtension)
        XCTAssertEqual(manifest.items.map(\.originalFilename), ["source.pdf"])
        XCTAssertEqual(try store.loadManifest(id: batchID), manifest)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try store.stagedFileURL(
            for: manifest.items[0],
            in: manifest
        ).path(percentEncoded: false)))

        try store.removeBatch(batchID)

        XCTAssertThrowsError(try store.loadManifest(id: batchID))
    }

    func testExternalImportRejectsMoreThanTenFilesBeforeStaging() {
        let root = temporaryDirectory()
        let store = ExternalLearningMaterialImportStore(rootDirectory: root)
        let urls = (0 ..< 11).map { root.appendingPathComponent("\($0).pdf") }

        XCTAssertThrowsError(try store.makeBatch(from: urls, source: .openIn)) { error in
            XCTAssertEqual(error as? ExternalLearningMaterialImportError, .tooManyFiles)
        }
    }

    func testExternalImportRejectsFileLargerThanTwentyFiveMiB() throws {
        let root = temporaryDirectory()
        let store = ExternalLearningMaterialImportStore(rootDirectory: root)
        let sourceURL = root.appendingPathComponent("large.pdf")
        XCTAssertTrue(FileManager.default.createFile(atPath: sourceURL.path, contents: nil))
        let handle = try FileHandle(forWritingTo: sourceURL)
        try handle.truncate(atOffset: UInt64(ExternalLearningMaterialImport.maximumFileBytes + 1))
        try handle.close()

        XCTAssertThrowsError(try store.makeBatch(from: [sourceURL], source: .openIn)) { error in
            XCTAssertEqual(error as? ExternalLearningMaterialImportError, .fileTooLarge("large.pdf"))
        }
    }

    @MainActor
    func testCoordinatorImportsBatchToFixedAndProjectDestinations() throws {
        let root = temporaryDirectory()
        let store = ExternalLearningMaterialImportStore(rootDirectory: root)
        let sourceURL = root.appendingPathComponent("课件.pdf")
        try Data("pdf".utf8).write(to: sourceURL)
        let manifest = try store.makeBatch(from: [sourceURL], source: .openIn)
        let setup = try AppModelContainerFactory.make()
        let coordinator = ExternalLearningMaterialImportCoordinator(store: store)
        let appNavigation = AppNavigationCoordinator()

        let fixedCount = try coordinator.importBatch(
            manifest,
            to: .fixed(.courseware),
            modelContext: setup.container.mainContext,
            appNavigation: appNavigation
        )

        XCTAssertEqual(fixedCount, 1)
        XCTAssertEqual(appNavigation.selectedRootTab, .academics)
        XCTAssertEqual(appNavigation.selectedAcademicTab, .learning)

        let fixedMaterials = try setup.container.mainContext.fetch(FetchDescriptor<LearningMaterialDocument>())
        XCTAssertEqual(fixedMaterials.count, 1)
        XCTAssertEqual(fixedMaterials[0].projectID, "")
        XCTAssertEqual(fixedMaterials[0].category, .courseware)
        XCTAssertEqual(fixedMaterials[0].originalFilename, "课件.pdf")
        XCTAssertEqual(fixedMaterials[0].contentTypeIdentifier, UTType.pdf.identifier)

        let projectID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000889"))
        let projectSourceURL = root.appendingPathComponent("项目.pptx")
        try Data("ppt".utf8).write(to: projectSourceURL)
        let projectManifest = try store.makeBatch(from: [projectSourceURL], source: .openIn)

        _ = try coordinator.importBatch(
            projectManifest,
            to: .project(projectID),
            modelContext: setup.container.mainContext,
            appNavigation: appNavigation
        )

        let allMaterials = try setup.container.mainContext.fetch(FetchDescriptor<LearningMaterialDocument>())
        let projectMaterial = try XCTUnwrap(allMaterials.first { $0.originalFilename == "项目.pptx" })
        XCTAssertEqual(projectMaterial.projectID, projectID.uuidString)
        XCTAssertEqual(projectMaterial.category, .other)
    }

    func testOnlyUnavailableProviderRepresentationAllowsDataFallback() {
        XCTAssertTrue(ExternalLearningMaterialImport.allowsDataRepresentationFallback(after: NSError(
            domain: NSItemProvider.errorDomain,
            code: -1000
        )))
        XCTAssertTrue(ExternalLearningMaterialImport.allowsDataRepresentationFallback(after: NSError(
            domain: NSItemProvider.errorDomain,
            code: -1200
        )))
        XCTAssertFalse(ExternalLearningMaterialImport
            .allowsDataRepresentationFallback(after: CocoaError(.fileWriteOutOfSpace)))
        XCTAssertFalse(ExternalLearningMaterialImport
            .allowsDataRepresentationFallback(after: ExternalLearningMaterialImportError.fileTooLarge("large.png")))
        XCTAssertFalse(ExternalLearningMaterialImport
            .allowsDataRepresentationFallback(after: URLError(.networkConnectionLost)))
    }

    func testFailedBatchRemovesEarlierCopiesAndKeepsSources() throws {
        let root = temporaryDirectory()
        let store = ExternalLearningMaterialImportStore(rootDirectory: root)
        let first = root.appendingPathComponent("first.pdf")
        let unsupported = root.appendingPathComponent("second.txt")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: unsupported)
        let id = UUID()
        XCTAssertThrowsError(try store.makeBatch(from: [first, unsupported], source: .openIn, id: id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.batchDirectoryURL(for: id).path))
        XCTAssertEqual(try Data(contentsOf: first), Data("first".utf8))
    }

    func testDirectoryCannotBeImportedAsPDF() throws {
        let root = temporaryDirectory()
        let source = root.appendingPathComponent("fake.pdf")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        XCTAssertThrowsError(try ExternalLearningMaterialImportStore(rootDirectory: root).makeBatch(
            from: [source],
            source: .openIn
        ))
    }

    func testManifestRejectsWrongIdentityPathDuplicatesAndNegativeSizes() throws {
        let root = temporaryDirectory()
        let store = ExternalLearningMaterialImportStore(rootDirectory: root)
        let id = UUID(), itemID = UUID()
        let item = ExternalLearningMaterialImportItem(
            id: itemID,
            originalFilename: "source.pdf",
            stagedFilename: "file.pdf",
            contentTypeIdentifier: UTType.pdf.identifier,
            byteCount: 4
        )
        let cases = [
            ExternalLearningMaterialImportManifest(id: UUID(), source: .openIn, items: [item]),
            ExternalLearningMaterialImportManifest(id: id, source: .openIn, items: [item, item]),
            ExternalLearningMaterialImportManifest(
                id: id,
                source: .openIn,
                items: [.init(
                    id: itemID,
                    originalFilename: "source.pdf",
                    stagedFilename: "../outside.pdf",
                    contentTypeIdentifier: UTType.pdf.identifier,
                    byteCount: 4
                )]
            ),
            ExternalLearningMaterialImportManifest(
                id: id,
                source: .openIn,
                items: [.init(
                    id: itemID,
                    originalFilename: "source.pdf",
                    stagedFilename: "file.pdf",
                    contentTypeIdentifier: UTType.pdf.identifier,
                    byteCount: -1
                )]
            )
        ]
        try store.prepareBatchDirectory(id)
        let manifestURL = store.batchDirectoryURL(for: id)
            .appendingPathComponent(ExternalLearningMaterialImport.manifestFilename)
        for manifest in cases {
            try JSONEncoder().encode(manifest).write(to: manifestURL)
            XCTAssertThrowsError(try store.loadManifest(id: id))
        }
    }

    func testPendingDiscoverySurfacesCorruptCommittedManifest() throws {
        let root = temporaryDirectory()
        let store = ExternalLearningMaterialImportStore(rootDirectory: root)
        let batchID = UUID()
        try store.prepareBatchDirectory(batchID)
        // An unfinished provider batch has no manifest and is not presented yet.
        XCTAssertTrue(try store.pendingManifests().isEmpty)
        try Data("corrupt".utf8)
            .write(to: store.batchDirectoryURL(for: batchID)
                .appendingPathComponent(ExternalLearningMaterialImport.manifestFilename))
        XCTAssertThrowsError(try store.pendingManifests())
    }

    func testStagedFileRejectsChangedSizeAndEscapingSymlink() throws {
        let root = temporaryDirectory()
        let store = ExternalLearningMaterialImportStore(rootDirectory: root)
        let source = root.appendingPathComponent("source.pdf")
        try Data("source".utf8).write(to: source)
        let manifest = try store.makeBatch(from: [source], source: .openIn)
        let item = manifest.items[0]
        let staged = store.batchDirectoryURL(for: manifest.id).appendingPathComponent(item.stagedFilename)
        try Data("changed size".utf8).write(to: staged)
        XCTAssertThrowsError(try store.stagedFileURL(for: item, in: manifest))
        try FileManager.default.removeItem(at: staged)
        try FileManager.default.createSymbolicLink(at: staged, withDestinationURL: source)
        XCTAssertThrowsError(try store.stagedFileURL(for: item, in: manifest))
        XCTAssertEqual(try Data(contentsOf: source), Data("source".utf8))
    }

    func testFailedCleanupIsReportedAndExistingExpiryCanRetry() throws {
        let root = temporaryDirectory()
        let id = UUID()
        let blocked = ExternalLearningMaterialImportStore(
            rootDirectory: root,
            fileManager: ImportCleanupFailingFileManager()
        )
        XCTAssertThrowsError(try blocked.makeBatch(
            from: [root.appendingPathComponent("bad.txt")],
            source: .openIn,
            id: id
        )) { error in
            guard case ExternalLearningMaterialImportError.cleanupFailed = error
            else { return XCTFail("Cleanup failure was hidden") }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: blocked.batchDirectoryURL(for: id).path))
        ExternalLearningMaterialImportStore(rootDirectory: root)
            .removeExpiredBatches(now: Date().addingTimeInterval(ExternalLearningMaterialImport.stagingLifetime + 60))
        XCTAssertFalse(FileManager.default.fileExists(atPath: blocked.batchDirectoryURL(for: id).path))
    }

    func testLearningWorkspaceCallbackParsesBatchID() throws {
        let batchID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000777"))
        let url = ExternalLearningMaterialImport.callbackURL(for: batchID)

        XCTAssertEqual(ExternalLearningMaterialImport.batchID(from: url), batchID)
        XCTAssertNil(ExternalLearningMaterialImport
            .batchID(from: URL(string: "leafy://community-post?id=\(batchID.uuidString)")!))
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExternalLearningMaterialImportTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}

private final class ImportCleanupFailingFileManager: FileManager, @unchecked Sendable {
    override func removeItem(at URL: URL) throws { throw CocoaError(.fileWriteNoPermission) }
}
