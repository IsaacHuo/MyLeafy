import XCTest
@testable import Leafy
final class ForegroundActivityTests: XCTestCase {
    func testQueueRetainsRecentOfflineEventsAndAcknowledgesOnlyMatchingIDs() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let old = ForegroundActivityEvent.make(now: now.addingTimeInterval(-8 * 86_400), version: "test")
        let recent = ForegroundActivityEvent.make(now: now.addingTimeInterval(-6 * 86_400), version: "test")
        var queue = ForegroundActivityQueue(events: [old, recent])
        queue.prune(now: now)
        XCTAssertEqual(queue.events, [recent])
        queue.acknowledge([UUID()])
        XCTAssertEqual(queue.events, [recent])
        queue.acknowledge([recent.id])
        XCTAssertTrue(queue.events.isEmpty)
    }
    func testRecreatedProfileDoesNotInheritFormerActivity() {
        let event = ForegroundActivityEvent.make(version: "test")
        let first = UUID()
        var queue = ForegroundActivityQueue(profileID: first, events: [event])
        queue.bind(to: first)
        XCTAssertEqual(queue.events, [event])
        queue.bind(to: UUID())
        XCTAssertTrue(queue.events.isEmpty)
    }
    @MainActor func testGuestAndDemoDoNotPermitRecording() {
        XCTAssertFalse(AppForegroundActivity.permits(identity: nil, isDemo: false))
        let guest = CampusIdentity(campusID: .guest, eduID: "guest", displayName: nil, portal: .undergraduate, kind: .guest)
        XCTAssertFalse(AppForegroundActivity.permits(identity: guest, isDemo: false))
        let student = CampusIdentity(campusID: .bjfu, eduID: "test", displayName: nil, portal: .undergraduate)
        XCTAssertFalse(AppForegroundActivity.permits(identity: student, isDemo: true))
        XCTAssertTrue(AppForegroundActivity.permits(identity: student, isDemo: false))
    }
}
