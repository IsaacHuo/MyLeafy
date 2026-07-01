import Foundation
import XCTest
@testable import Leafy

final class CommunityAvatarCacheTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CommunityAvatarCacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
        directory = nil
        try super.tearDownWithError()
    }

    func testCacheFileNameIncludesProfileIDAndEscapesAvatarPath() {
        let profileID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

        let fileName = CommunityAvatarCache.cacheFileName(
            profileID: profileID,
            avatarPath: "avatars/\(profileID.uuidString.lowercased())/avatar one.jpg"
        )

        XCTAssertNotNil(fileName)
        XCTAssertTrue(fileName?.hasPrefix("\(profileID.uuidString.lowercased())-") == true)
        XCTAssertTrue(fileName?.hasSuffix(".jpg") == true)
        XCTAssertFalse(fileName?.contains("/") == true)
        XCTAssertNil(CommunityAvatarCache.cacheFileName(profileID: profileID, avatarPath: "   "))
    }

    func testSaveAndReadAvatarData() throws {
        let cache = CommunityAvatarCache(directory: directory)
        let profile = makeProfile(avatarPath: "avatars/profile-a/avatar.jpg")
        let data = Data([1, 2, 3, 4])

        try cache.save(data: data, for: profile)

        XCTAssertEqual(cache.data(for: profile), data)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(cache.cacheURL(for: profile)).path))
    }

    func testSavingNewAvatarRemovesOldProfileAvatar() throws {
        let cache = CommunityAvatarCache(directory: directory)
        let profileID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let oldProfile = makeProfile(id: profileID, avatarPath: "avatars/profile/old.jpg")
        let newProfile = makeProfile(id: profileID, avatarPath: "avatars/profile/new.jpg")

        try cache.save(data: Data([1]), for: oldProfile)
        let oldURL = try XCTUnwrap(cache.cacheURL(for: oldProfile))
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.path))

        try cache.save(data: Data([2]), for: newProfile)

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertEqual(cache.data(for: newProfile), Data([2]))
    }

    private func makeProfile(
        id: UUID = UUID(),
        avatarPath: String?
    ) -> CommunityProfile {
        CommunityProfile(
            id: id,
            eduID: "20260001",
            nickname: "北林同学",
            displayName: nil,
            avatarPath: avatarPath,
            major: nil,
            grade: nil,
            boundEmail: nil,
            pendingBoundEmail: nil,
            emailVerificationSentAt: nil,
            profileEditedAt: nil,
            isProfileComplete: true,
            createdAt: "2026-05-30T00:00:00Z",
            updatedAt: "2026-05-30T00:00:00Z",
            signedAvatarURL: nil,
            avatarURL: nil
        )
    }
}
