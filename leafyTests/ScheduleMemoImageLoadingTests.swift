import UIKit
import XCTest
@testable import Leafy

@MainActor
final class ScheduleMemoImageLoadingTests: XCTestCase {
    func testSameRequestDoesNotReadAgainButRevisionAndDirectoryInvalidateIt() async {
        let record = ScheduleMemoImage(memoID: UUID(), sortOrder: 0, localFilename: "photo.jpg")
        let date = Date()
        let first = ScheduleMemoImageRequest(
            images: [record],
            revision: date,
            directory: URL(fileURLWithPath: "/identity-a")
        )
        let loader = ScheduleMemoImageLoader()
        let reads = MemoImageReads()
        await loader.load(first, read: { await reads.read($0) })
        await loader.load(first, read: { await reads.read($0) })
        let count = await reads.count
        XCTAssertEqual(count, 1)
        let revised = ScheduleMemoImageRequest(
            images: [record],
            revision: date.addingTimeInterval(1),
            directory: URL(fileURLWithPath: "/identity-a")
        )
        XCTAssertTrue(loader.images(for: revised).isEmpty)
        await loader.load(revised, read: { await reads.read($0) })
        let otherIdentity = ScheduleMemoImageRequest(
            images: [record],
            revision: date,
            directory: URL(fileURLWithPath: "/identity-b")
        )
        XCTAssertTrue(loader.images(for: otherIdentity).isEmpty)
        await loader.load(otherIdentity, read: { await reads.read($0) })
        let paths = await reads.paths
        XCTAssertEqual(paths, ["/identity-a/photo.jpg", "/identity-a/photo.jpg", "/identity-b/photo.jpg"])
    }

    func testCancelledLoadDoesNotPublishAndCanRetry() async throws {
        let record = ScheduleMemoImage(memoID: UUID(), sortOrder: 0, localFilename: "photo.jpg")
        let request = ScheduleMemoImageRequest(images: [record], revision: Date())
        let loader = ScheduleMemoImageLoader()
        let started = expectation(description: "Image read suspended")
        let gate = MemoImageReadGate(started: started)
        let loading = Task { await loader.load(request, read: { await gate.read($0) }) }
        await fulfillment(of: [started], timeout: 3)
        loading.cancel()
        await gate.release()
        await loading.value
        XCTAssertTrue(loader.images(for: request).isEmpty)
        await loader.load(request, read: { _ in UIImage() })
        XCTAssertNotNil(loader.images(for: request)[record.id])
    }

    func testOldLoadCannotReplaceNewRequest() async {
        let record = ScheduleMemoImage(memoID: UUID(), sortOrder: 0, localFilename: "photo.jpg")
        let first = ScheduleMemoImageRequest(
            images: [record],
            revision: Date(),
            directory: URL(fileURLWithPath: "/old")
        )
        let second = ScheduleMemoImageRequest(
            images: [record],
            revision: first.revision,
            directory: URL(fileURLWithPath: "/new")
        )
        let loader = ScheduleMemoImageLoader()
        let started = expectation(description: "Old image read suspended")
        let gate = MemoImageReadGate(started: started)
        let old = Task { await loader.load(first, read: { await gate.read($0) }) }
        await fulfillment(of: [started], timeout: 3)
        await loader.load(second, read: { _ in UIImage() })
        await gate.release()
        await old.value
        XCTAssertNotNil(loader.images(for: second)[record.id])
        XCTAssertTrue(loader.images(for: first).isEmpty)
    }

    func testIdentityChangeDiscardsInFlightImages() async {
        let manager = ActiveCampusContext.networkManager
        manager.persistAuthenticatedIdentity(eduID: "image-a-" + UUID().uuidString)
        defer { manager.clearSession() }
        let record = ScheduleMemoImage(memoID: UUID(), sortOrder: 0, localFilename: "photo.jpg")
        let request = ScheduleMemoImageRequest(images: [record], revision: Date())
        let loader = ScheduleMemoImageLoader()
        let started = expectation(description: "Image read suspended before identity change")
        let gate = MemoImageReadGate(started: started)
        let loading = Task { await loader.load(request, read: { await gate.read($0) }) }
        await fulfillment(of: [started], timeout: 3)
        manager.persistAuthenticatedIdentity(eduID: "image-b-" + UUID().uuidString)
        await gate.release()
        await loading.value
        XCTAssertTrue(loader.images(for: request).isEmpty)
    }

    func testDisappearingViewReleasesImagesAndReloadsOnReturn() async {
        let record = ScheduleMemoImage(memoID: UUID(), sortOrder: 0, localFilename: "photo.jpg")
        let request = ScheduleMemoImageRequest(images: [record], revision: Date())
        let loader = ScheduleMemoImageLoader()
        let reads = MemoImageReads()
        await loader.load(request, read: { await reads.read($0) })
        XCTAssertFalse(loader.isLoading(request))
        loader.reset()
        XCTAssertTrue(loader.images(for: request).isEmpty)
        XCTAssertTrue(loader.isLoading(request))
        await loader.load(request, read: { await reads.read($0) })
        let count = await reads.count
        XCTAssertEqual(count, 2)
        XCTAssertNotNil(loader.images(for: request)[record.id])
    }

    func testMissingAndCorruptImagesRemainUnavailable() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = ScheduleMemoImage(memoID: UUID(), sortOrder: 0, localFilename: "corrupt.jpg")
        let missing = ScheduleMemoImage(memoID: record.memoID, sortOrder: 1, localFilename: "missing.jpg")
        try Data("not an image".utf8).write(to: directory.appendingPathComponent(record.localFilename))
        let request = ScheduleMemoImageRequest(images: [record, missing], revision: Date(), directory: directory)
        let loader = ScheduleMemoImageLoader()
        await loader.load(request)
        XCTAssertTrue(loader.images(for: request).isEmpty)
    }
}

private actor MemoImageReads {
    var paths: [String] = []
    var count: Int { paths.count }
    func read(_ url: URL) -> UIImage? {
        paths.append(url.path)
        return UIImage()
    }
}

private actor MemoImageReadGate {
    let started: XCTestExpectation
    var continuation: CheckedContinuation<UIImage?, Never>?
    init(started: XCTestExpectation) { self.started = started }
    func read(_ url: URL) async -> UIImage? {
        await withCheckedContinuation {
            continuation = $0
            started.fulfill()
        }
    }
    func release() { continuation?.resume(returning: UIImage()); continuation = nil }
}
