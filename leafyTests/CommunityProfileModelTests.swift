import XCTest
import UIKit
@testable import Leafy

final class CommunityProfileModelTests: XCTestCase {
    func testCommunityProfileDecodesLegacyPayloadWithoutHomepageFields() throws {
        let data = Data("""
        {
          "id": "11111111-2222-3333-4444-555555555555",
          "edu_id": "20260001",
          "campus_id": "bjfu",
          "nickname": "北林同学",
          "display_name": null,
          "avatar_path": null,
          "major": null,
          "grade": null,
          "bound_email": null,
          "pending_bound_email": null,
          "email_verification_sent_at": null,
          "profile_edited_at": null,
          "is_profile_complete": true,
          "created_at": "2026-05-30T00:00:00Z",
          "updated_at": "2026-05-30T00:00:00Z"
        }
        """.utf8)

        let profile = try JSONDecoder().decode(CommunityProfile.self, from: data)

        XCTAssertNil(profile.trimmedBio)
        XCTAssertFalse(profile.showsEduVerificationBadge)
    }

    func testCommunityProfileDecodesHomepageFields() throws {
        let data = Data("""
        {
          "id": "11111111-2222-3333-4444-555555555555",
          "edu_id": "20260001",
          "campus_id": "bjfu",
          "nickname": "北林同学",
          "display_name": "同学",
          "avatar_path": null,
          "bio": "  今天也在图书馆  ",
          "major": "信息学院",
          "grade": "2024级",
          "bound_email": null,
          "pending_bound_email": null,
          "email_verification_sent_at": null,
          "profile_edited_at": null,
          "is_profile_complete": true,
          "shows_edu_verification_badge": true,
          "created_at": "2026-05-30T00:00:00Z",
          "updated_at": "2026-05-30T00:00:00Z"
        }
        """.utf8)

        let profile = try JSONDecoder().decode(CommunityProfile.self, from: data)

        XCTAssertEqual(profile.trimmedBio, "今天也在图书馆")
        XCTAssertTrue(profile.showsEduVerificationBadge)
    }

    func testCommunityProfileBioNormalizationLimitsLengthAndEmptyText() {
        XCTAssertNil(CommunityProfileBio.normalized("   "))

        let longBio = String(repeating: "签", count: CommunityProfileBio.maxLength + 4)
        XCTAssertEqual(CommunityProfileBio.normalized(longBio)?.count, CommunityProfileBio.maxLength)
    }

    func testCommunityProfileStatsDecodesRPCProfilePayload() throws {
        let data = Data("""
        {
          "profile_id": "11111111-2222-3333-4444-555555555555",
          "public_post_count": 42,
          "received_like_count": 30,
          "activity_score": 156,
          "title": "山水知己",
          "first_post_at": "2026-05-30T00:00:00Z",
          "latest_post_at": "2026-06-12T00:00:00Z"
        }
        """.utf8)

        let stats = try JSONDecoder().decode(CommunityProfileStats.self, from: data)

        XCTAssertEqual(stats.profileID.uuidString.lowercased(), "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(stats.publicPostCount, 42)
        XCTAssertEqual(stats.receivedLikeCount, 30)
        XCTAssertEqual(stats.activityScore, 156)
        XCTAssertEqual(stats.title, "山水知己")
        XCTAssertEqual(stats.firstPostAt, "2026-05-30T00:00:00Z")
        XCTAssertEqual(stats.latestPostAt, "2026-06-12T00:00:00Z")
    }

    func testCommunityProfileTitleNamesUseServerThresholds() {
        XCTAssertEqual(CommunityProfileTitleName.title(activityScore: 0), "初入林园")
        XCTAssertEqual(CommunityProfileTitleName.title(activityScore: 5), "林下伙伴")
        XCTAssertEqual(CommunityProfileTitleName.title(activityScore: 20), "绿野熟人")
        XCTAssertEqual(CommunityProfileTitleName.title(activityScore: 60), "松下常客")
        XCTAssertEqual(CommunityProfileTitleName.title(activityScore: 150), "山水知己")
    }

    func testCustomApprovedProfileSubtitleUsesCommunitySchoolName() {
        let profile = CommunityProfile(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            eduID: "custom-user",
            campusID: "tsinghua",
            communityCampusID: "tsinghua",
            communityAccessStatusRaw: "approved",
            communitySchoolName: "清华大学",
            communityRejectionReason: nil,
            nickname: "Leafy",
            displayName: nil,
            avatarPath: nil,
            major: nil,
            grade: nil,
            boundEmail: nil,
            pendingBoundEmail: nil,
            emailVerificationSentAt: nil,
            profileEditedAt: nil,
            isProfileComplete: true,
            createdAt: "2026-06-23T00:00:00Z",
            updatedAt: "2026-06-23T00:00:00Z",
            signedAvatarURL: nil,
            avatarURL: nil
        )

        XCTAssertEqual(profile.subtitleText(language: .zhHans), "清华大学 社区")
    }

    func testCampusMembershipRequestDecodesSchoolChangePayload() throws {
        let data = Data("""
        {
          "id": "11111111-2222-3333-4444-555555555555",
          "requester_profile_id": "22222222-3333-4444-5555-666666666666",
          "school_name": "北京大学",
          "normalized_school_name": "北京大学",
          "status": "pending",
          "approved_campus_id": null,
          "request_type": "school_change",
          "requested_campus_id": "pku",
          "from_campus_id": "tsinghua",
          "admin_note": null,
          "created_at": "2026-06-23T00:00:00Z",
          "updated_at": "2026-06-23T00:00:00Z"
        }
        """.utf8)

        let request = try JSONDecoder().decode(CommunityCampusMembershipRequest.self, from: data)

        XCTAssertEqual(request.requestType, .schoolChange)
        XCTAssertTrue(request.isPending)
        XCTAssertEqual(request.requestedCampusID, "pku")
        XCTAssertEqual(request.fromCampusID, "tsinghua")
    }

    func testCommunityProfileUpdateEncodesNilCoverPathAsNull() throws {
        let update = CommunityProfileUpdate(
            nickname: "Leafy",
            avatarPath: "profile-avatars/user/avatar.jpg",
            coverPath: nil,
            bio: nil,
            major: nil,
            grade: nil,
            profileEditedAt: "2026-06-12T00:00:00Z",
            isProfileComplete: true,
            showsEduVerificationBadge: false,
            updatedAt: "2026-06-12T00:00:00Z"
        )

        let data = try JSONEncoder().encode(update)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertTrue(object.keys.contains("cover_path"))
        XCTAssertTrue(object["cover_path"] is NSNull)
    }

    func testCommunityProfileUpdateDoesNotEncodeCampusMembershipFields() throws {
        let update = CommunityProfileUpdate(
            nickname: "Leafy",
            avatarPath: nil,
            coverPath: nil,
            bio: "你好",
            major: "信息学院",
            grade: "2024级",
            profileEditedAt: "2026-06-23T00:00:00Z",
            isProfileComplete: true,
            showsEduVerificationBadge: false,
            updatedAt: "2026-06-23T00:00:00Z"
        )

        let data = try JSONEncoder().encode(update)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertFalse(object.keys.contains("campus_id"))
        XCTAssertFalse(object.keys.contains("community_campus_id"))
        XCTAssertFalse(object.keys.contains("community_access_status"))
        XCTAssertFalse(object.keys.contains("community_school_name"))
        XCTAssertFalse(object.keys.contains("community_request_id"))
    }

    func testCommunityNotificationMarkingReadPreservesPayload() {
        let notification = CommunityNotification(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            recipientID: UUID(uuidString: "22222222-3333-4444-5555-666666666666")!,
            actorID: UUID(uuidString: "33333333-4444-5555-6666-777777777777")!,
            postID: UUID(uuidString: "44444444-5555-6666-7777-888888888888")!,
            commentID: UUID(uuidString: "55555555-6666-7777-8888-999999999999")!,
            type: .comment,
            title: "回复了你的帖子",
            body: "这个导出日历很好用",
            isRead: false,
            createdAt: "2026-06-23T08:20:00Z",
            actor: nil
        )

        let marked = notification.markingRead()

        XCTAssertTrue(marked.isRead)
        XCTAssertEqual(marked.id, notification.id)
        XCTAssertEqual(marked.recipientID, notification.recipientID)
        XCTAssertEqual(marked.actorID, notification.actorID)
        XCTAssertEqual(marked.postID, notification.postID)
        XCTAssertEqual(marked.commentID, notification.commentID)
        XCTAssertEqual(marked.type, notification.type)
        XCTAssertEqual(marked.title, notification.title)
        XCTAssertEqual(marked.body, notification.body)
        XCTAssertEqual(marked.createdAt, notification.createdAt)
    }

    func testNotificationFeedItemMarkingReadPreservesDisplayIdentity() {
        let timestamp = "2026-06-23T09:00:00Z"
        let communityItem = NotificationFeedItem.community(
            CommunityNotification(
                id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
                recipientID: UUID(uuidString: "22222222-3333-4444-5555-666666666666")!,
                actorID: nil,
                postID: UUID(uuidString: "44444444-5555-6666-7777-888888888888")!,
                commentID: nil,
                type: .like,
                title: "点赞了你的帖子",
                body: "打个小广告",
                isRead: false,
                createdAt: "2026-06-22T12:00:00Z",
                actor: nil
            )
        )
        let announcementItem = NotificationFeedItem.announcement(
            SiteAnnouncement(
                id: UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA")!,
                title: "全站通知",
                body: "社区体验优化中",
                level: .info,
                status: "published",
                publishedAt: "2026-06-23T08:00:00Z",
                expiresAt: nil,
                createdBy: UUID(uuidString: "77777777-8888-9999-AAAA-BBBBBBBBBBBB")!,
                createdAt: "2026-06-23T07:30:00Z",
                readAt: nil
            )
        )

        for item in [communityItem, announcementItem] {
            let marked = item.markingRead(at: timestamp)

            XCTAssertTrue(marked.isRead)
            XCTAssertEqual(marked.id, item.id)
            XCTAssertEqual(marked.title, item.title)
            XCTAssertEqual(marked.body, item.body)
            XCTAssertEqual(marked.systemImage, item.systemImage)
            XCTAssertEqual(marked.sortDate, item.sortDate)
        }
    }

    func testCoverCropProducesFixedAspectRatioImageForWideSource() {
        let source = makeTestImage(size: CGSize(width: 640, height: 120))
        let aspectRatio: CGFloat = 320 / 142

        let cropped = source.leafyCoverImage(
            width: CommunityImageUpload.profileCoverImageMaxPixelDimension,
            aspectRatio: aspectRatio,
            viewSize: CGSize(width: 320, height: 142),
            scale: 1,
            offset: .zero
        )

        XCTAssertEqual(cropped.size.width, CommunityImageUpload.profileCoverImageMaxPixelDimension, accuracy: 0.5)
        XCTAssertEqual(cropped.size.height, (CommunityImageUpload.profileCoverImageMaxPixelDimension / aspectRatio).rounded(), accuracy: 0.5)
    }

    private func makeTestImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
