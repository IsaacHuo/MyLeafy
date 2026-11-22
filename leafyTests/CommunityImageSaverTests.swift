import UIKit
import XCTest
@testable import Leafy

@MainActor
final class CommunityImageSaverTests: XCTestCase {
    private let url = URL(string: "https://example.invalid/image")!
    private func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
    }
    private func temporaryFile(_ data: Data) throws -> URL {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: file)
        return file
    }
    private func png() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).pngData { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }
    func testSavingKeepsOriginalFileBytesAndCleansTemporaryFiles() async throws {
        let data = png(), file = try temporaryFile(data)
        var savedURL: URL?
        try await CommunityImageSaver.save(
            url: url,
            download: { _ in (file, self.response(200)) },
            saveFiles: { files in
                XCTAssertEqual(files.count, 1)
                savedURL = files.first
                XCTAssertEqual(files.first?.pathExtension, "png")
                XCTAssertEqual(try Data(contentsOf: XCTUnwrap(files.first)), data)
            }
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(savedURL).path))
    }
    func testHTTPFailureAndNonImageResponsesNeverRequestPhotoAccess() async throws {
        for (status, data) in [(403, png()), (200, Data("not an image".utf8))] {
            let file = try temporaryFile(data)
            do {
                try await CommunityImageSaver.save(url: url, download: { _ in (file, self.response(status)) },
                                                   saveFiles: { _ in
                                                       XCTFail("Invalid downloads must not request photo access") })
                XCTFail("Expected a visible error")
            } catch { XCTAssertTrue(error is CommunityImageSaveError) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        }
    }
    func testPhotoPermissionFailureIsPropagatedAndDownloadIsCleaned() async throws {
        let file = try temporaryFile(png())
        do {
            try await CommunityImageSaver.save(url: url, download: { _ in (file, self.response(200)) },
                                               saveFiles: { _ in throw LeafyPhotoLibrarySaveError.permissionDenied })
            XCTFail("Expected permission failure")
        } catch {
            guard case LeafyPhotoLibrarySaveError.permissionDenied = error
            else { return XCTFail("Unexpected \(error)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
}
