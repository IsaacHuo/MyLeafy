import Foundation
import OSLog
import Supabase

// MARK: - Notifications

extension CommunityService {
    func fetchNotifications(limit: Int = 50) async throws -> [CommunityNotification] {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        guard let currentProfile = try await fetchCurrentProfile() else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let records: [CommunityNotificationRecord] = try await client
            .from("community_notifications")
            .select()
            .eq("recipient_id", value: currentProfile.id.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        let visibleRecords = records.filter { $0.dismissedAt == nil }
        let blockedIDs = try await fetchBlockedUserIDs(viewerID: currentProfile.id, client: client)
        return try await hydrateNotifications(from: visibleRecords.filter { record in
            guard let actorID = record.actorID else { return true }
            return !blockedIDs.contains(actorID)
        })
    }

    func fetchNotificationFeed(limit: Int = 50) async throws -> [NotificationFeedItem] {
        let settings = try await fetchNotificationSettings()
        guard !settings.mutedAll else { return [] }

        let communityNotifications = try await fetchNotifications(limit: limit)
        let siteAnnouncements = try await fetchSiteAnnouncements(limit: limit)

        return Array(
            (communityNotifications.map(NotificationFeedItem.community) + siteAnnouncements.map(NotificationFeedItem.announcement))
                .sorted { $0.sortDate > $1.sortDate }
                .prefix(limit)
        )
    }

    func fetchSiteAnnouncements(limit: Int = 50) async throws -> [SiteAnnouncement] {
        let client = try LeafySupabase.shared.requireClient()
        guard let currentUser = client.auth.currentUser else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let records: [SiteAnnouncementRecord] = try await client
            .from("site_announcements")
            .select()
            .eq("status", value: "published")
            .order("published_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        let activeRecords = records.filter(isSiteAnnouncementActive)
        let reads = try await fetchSiteAnnouncementReads(
            announcementIDs: activeRecords.map(\.id),
            userID: currentUser.id
        )
        let visibleReads = reads.filter { $0.dismissedAt == nil }
        let dismissedIDs = Set(reads.filter { $0.dismissedAt != nil }.map(\.announcementID))
        let readMap = LeafyFirstValueMap.build(visibleReads.map { ($0.announcementID, $0.readAt) })

        return activeRecords.filter { !dismissedIDs.contains($0.id) }.map { record in
            SiteAnnouncement(
                id: record.id,
                title: record.title,
                body: record.body,
                level: record.level,
                status: record.status,
                publishedAt: record.publishedAt,
                expiresAt: record.expiresAt,
                createdBy: record.createdBy,
                createdAt: record.createdAt,
                readAt: readMap[record.id]
            )
        }
    }

    func fetchUnreadNotificationCount(limit: Int = 100) async throws -> Int {
        let settings = try await fetchNotificationSettings()
        guard !settings.mutedAll else { return 0 }

        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        guard let currentProfile = try await fetchCurrentProfile() else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let records: [CommunityNotificationRecord] = try await client
            .from("community_notifications")
            .select()
            .eq("recipient_id", value: currentProfile.id.uuidString)
            .eq("is_read", value: false)
            .limit(limit)
            .execute()
            .value

        let unreadAnnouncementCount = try await fetchSiteAnnouncements(limit: limit)
            .filter { !$0.isRead }
            .count

        let blockedIDs = try await fetchBlockedUserIDs(viewerID: currentProfile.id, client: client)
        let visibleUnreadCount = records.filter { record in
            guard record.dismissedAt == nil else { return false }
            guard let actorID = record.actorID else { return true }
            return !blockedIDs.contains(actorID)
        }.count

        return visibleUnreadCount + unreadAnnouncementCount
    }

    func fetchNotificationSettings() async throws -> CommunityNotificationSettings {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        guard let currentProfile = try await fetchCurrentProfile() else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let records: [CommunityNotificationSettingsRecord] = try await client
            .from("community_notification_settings")
            .select()
            .eq("user_id", value: currentProfile.id.uuidString)
            .limit(1)
            .execute()
            .value

        guard let record = records.first else {
            return CommunityNotificationSettings(userID: currentProfile.id, mutedAll: false, updatedAt: nil)
        }

        return CommunityNotificationSettings(
            userID: record.userID,
            mutedAll: record.mutedAll,
            updatedAt: record.updatedAt
        )
    }

    func updateNotificationSettings(mutedAll: Bool) async throws -> CommunityNotificationSettings {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        guard let currentProfile = try await fetchCurrentProfile() else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let update = CommunityNotificationSettingsUpsert(
            userID: currentProfile.id,
            mutedAll: mutedAll,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )

        let record: CommunityNotificationSettingsRecord = try await client
            .from("community_notification_settings")
            .upsert(update, onConflict: "user_id")
            .select()
            .single()
            .execute()
            .value

        return CommunityNotificationSettings(
            userID: record.userID,
            mutedAll: record.mutedAll,
            updatedAt: record.updatedAt
        )
    }

    func markNotificationRead(notificationID: UUID) async throws {
        let client = try LeafySupabase.shared.requireClient()
        let update = CommunityNotificationReadUpdate(isRead: true)

        _ = try await client
            .from("community_notifications")
            .update(update)
            .eq("id", value: notificationID.uuidString)
            .execute()
    }

    func markNotificationFeedRead(announcementLimit: Int = 500) async throws {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        guard let currentProfile = try await fetchCurrentProfile() else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let now = ISO8601DateFormatter().string(from: Date())
        let communityUpdate = CommunityNotificationReadUpdate(isRead: true)

        _ = try await client
            .from("community_notifications")
            .update(communityUpdate)
            .eq("recipient_id", value: currentProfile.id.uuidString)
            .eq("is_read", value: false)
            .is("dismissed_at", value: nil)
            .execute()

        let unreadAnnouncements = try await fetchSiteAnnouncements(limit: announcementLimit)
            .filter { !$0.isRead }
        guard !unreadAnnouncements.isEmpty else { return }

        guard let currentUser = client.auth.currentUser else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        let inserts = unreadAnnouncements.map { announcement in
            SiteAnnouncementReadInsert(
                announcementID: announcement.id,
                userID: currentUser.id,
                readAt: now,
                dismissedAt: nil
            )
        }

        _ = try await client
            .from("site_announcement_reads")
            .upsert(
                inserts,
                onConflict: "announcement_id,user_id",
                ignoreDuplicates: true
            )
            .execute()
    }

    func dismissNotificationFeedItem(_ item: NotificationFeedItem) async throws {
        switch item {
        case .community(let notification):
            try await dismissCommunityNotification(notificationID: notification.id)
        case .announcement(let announcement):
            try await dismissSiteAnnouncement(announcementID: announcement.id)
        case .publication:
            return
        }
    }

    func dismissCommunityNotification(notificationID: UUID) async throws {
        let client = try LeafySupabase.shared.requireClient()
        let update = CommunityNotificationDismissUpdate(
            isRead: true,
            dismissedAt: ISO8601DateFormatter().string(from: Date())
        )

        _ = try await client
            .from("community_notifications")
            .update(update)
            .eq("id", value: notificationID.uuidString)
            .execute()
    }

    func markSiteAnnouncementRead(announcementID: UUID) async throws {
        let client = try LeafySupabase.shared.requireClient()
        guard let currentUser = client.auth.currentUser else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let insert = SiteAnnouncementReadInsert(
            announcementID: announcementID,
            userID: currentUser.id,
            readAt: ISO8601DateFormatter().string(from: Date()),
            dismissedAt: nil
        )

        _ = try await client
            .from("site_announcement_reads")
            .upsert(
                insert,
                onConflict: "announcement_id,user_id",
                ignoreDuplicates: true
            )
            .execute()
    }

    func dismissSiteAnnouncement(announcementID: UUID) async throws {
        let client = try LeafySupabase.shared.requireClient()
        guard let currentUser = client.auth.currentUser else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let now = ISO8601DateFormatter().string(from: Date())
        let insert = SiteAnnouncementReadInsert(
            announcementID: announcementID,
            userID: currentUser.id,
            readAt: now,
            dismissedAt: now
        )

        _ = try await client
            .from("site_announcement_reads")
            .upsert(insert, onConflict: "announcement_id,user_id")
            .execute()
    }
}
