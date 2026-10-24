import Foundation
import XCTest
@testable import Leafy

final class ProfileSharingStatusTests: XCTestCase {
    private let owner = UUID()
    private let now = Date(timeIntervalSince1970: 100)

    func testActiveOwnMemberIsSharedButAnotherOwnersMemberIsNot() {
        XCTAssertTrue(status(members: [member(owner: owner)]))
        XCTAssertFalse(status(members: [member(owner: UUID())]))
    }

    func testUsableOwnInviteIsSharedBeforeAcceptance() {
        XCTAssertTrue(status(invites: [invite(owner: owner, expires: now.addingTimeInterval(1))]))
        XCTAssertFalse(status(invites: [invite(owner: UUID(), expires: now.addingTimeInterval(1))]))
    }

    func testStoppedSharingAndUsedOrExpiredInvitesAreNotShared() {
        XCTAssertFalse(status(members: [member(owner: owner, revoked: true)],
                              invites: [invite(owner: owner, expires: now)]))
        XCTAssertFalse(status(invites: [invite(owner: owner, expires: now.addingTimeInterval(60), accepted: true)]))
        XCTAssertFalse(status())
    }

    private func status(members: [TimetableShareMember] = [], invites: [TimetableInvite] = []) -> Bool {
        TimetableSharingService.hasActiveSharing(members: members, invites: invites, ownerID: owner, now: now)
    }

    private func member(owner: UUID, revoked: Bool = false) -> TimetableShareMember {
        TimetableShareMember(id: UUID(), ownerID: owner, viewerID: UUID(), createdAt: "", updatedAt: "",
                             revokedAt: revoked ? "revoked" : nil, viewer: nil)
    }

    private func invite(owner: UUID, expires: Date, accepted: Bool = false) -> TimetableInvite {
        TimetableInvite(id: UUID(), ownerID: owner, semesterID: "2026-2027-1", code: nil,
                        expiresAt: ISO8601DateFormatter().string(from: expires), acceptedBy: accepted ? UUID() : nil,
                        acceptedAt: nil, createdAt: "")
    }
}
