import Foundation

extension CloudflareCommunityRepository {
    nonisolated struct CatalogRow<Entity: Decodable & Sendable, Rating: Decodable & Sendable>: Decodable, Sendable {
        let entity: Entity
        let rating: Rating?
        enum CodingKeys: String, CodingKey { case rating = "viewer_rating" }
        init(from decoder: Decoder) throws {
            entity = try Entity(from: decoder)
            rating = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(Rating.self, forKey: .rating)
        }
    }
    func fetchTeacherRatingSummaries(search: String, limit: Int, offset: Int) async throws -> [TeacherRatingSummary] {
        let records: [CatalogRow<TeacherProfile, TeacherRating>] = try await get("/v1/catalog/teachers", query(["search":search,"limit":String(limit),"offset":String(offset)]))
        return records.map { TeacherRatingSummary(teacher: $0.entity, myRating: $0.rating) }
    }
    func fetchCourseRatingSummaries(search: String, category: String?, limit: Int, offset: Int) async throws -> [CourseRatingSummary] {
        let records: [CatalogRow<CourseProfile, CourseRating>] = try await get("/v1/catalog/courses", query(["search":search,"category":category,"limit":String(limit),"offset":String(offset)]))
        return records.map { CourseRatingSummary(course: $0.entity, myRating: $0.rating) }
    }
    func fetchDishRatingSummaries(search: String, canteen: String?, location: String?, limit: Int, offset: Int) async throws -> [DishRatingSummary] {
        let records: [CatalogRow<DishProfile, DishRating>] = try await get("/v1/catalog/dishes", query(["search":search,"canteen":canteen,"location":location,"limit":String(limit),"offset":String(offset)]))
        return records.map { DishRatingSummary(dish: $0.entity, myRating: $0.rating) }
    }
    func submitTeacherRating(teacherID: Int64, stars: Int) async throws -> TeacherRatingSummary {
        let result: CatalogRow<TeacherProfile, TeacherRating> = try await request("/v1/catalog/teachers/\(teacherID)/rating", method: "PUT", body: ["stars":stars])
        return TeacherRatingSummary(teacher: result.entity, myRating: result.rating)
    }
    func submitCourseRating(courseID: Int64, stars: Int) async throws -> CourseRatingSummary {
        let result: CatalogRow<CourseProfile, CourseRating> = try await request("/v1/catalog/courses/\(courseID)/rating", method: "PUT", body: ["stars":stars])
        return CourseRatingSummary(course: result.entity, myRating: result.rating)
    }
    func submitDishRating(dishID: Int64, stars: Int) async throws -> DishRatingSummary {
        let result: CatalogRow<DishProfile, DishRating> = try await request("/v1/catalog/dishes/\(dishID)/rating", method: "PUT", body: ["stars":stars])
        return DishRatingSummary(dish: result.entity, myRating: result.rating)
    }
    func submitCatalogSuggestion(input: CatalogSuggestionInput) async throws {
        struct Input: Encodable { let suggestion_type: String; let name: String; let unit: String; let teacher_name: String?; let category: String?; let credit: Double?; let initial_stars: Int?; let note: String? }
        try await perform("/v1/catalog/suggestions", body: Input(suggestion_type: input.type.rawValue, name: input.name, unit: input.unit, teacher_name: input.teacherName, category: input.category, credit: input.credit, initial_stars: input.initialStars, note: input.note))
    }
    func submitFeedback(issueType: String, body: String, contact: String?, deviceInfo: [String: String]) async throws {
        try await ensureAnonymousSession()
        struct Input: Encodable { let issue_type: String; let body: String; let contact: String?; let device_info: [String:String] }
        try await perform("/v1/feedback", body: Input(issue_type: issueType, body: body, contact: contact, device_info: deviceInfo))
    }
    func fetchNotificationSettings() async throws -> CommunityNotificationSettings { try await get("/v1/notifications/settings") }
    func updateNotificationSettings(mutedAll: Bool) async throws -> CommunityNotificationSettings { try await request("/v1/notifications/settings", method: "PUT", body: ["muted_all":mutedAll]) }
    func fetchNotificationFeed(limit: Int) async throws -> [NotificationFeedItem] {
        guard try await !fetchNotificationSettings().mutedAll else { return [] }
        async let notifications: [CommunityNotification] = get("/v1/notifications", query(["limit":String(limit)]))
        async let announcements: [SiteAnnouncement] = get("/v1/announcements", query(["limit":String(limit)]))
        return try await Array((notifications.map(NotificationFeedItem.community) + announcements.map(NotificationFeedItem.announcement)).sorted { $0.sortDate > $1.sortDate }.prefix(limit))
    }
    func fetchUnreadNotificationCount() async throws -> Int {
        guard try await !fetchNotificationSettings().mutedAll else { return 0 }
        async let notifications: [CommunityNotification] = get("/v1/notifications", query(["limit":"100"]))
        async let announcements: [SiteAnnouncement] = get("/v1/announcements", query(["limit":"100"]))
        return try await notifications.filter { !$0.isRead }.count + announcements.filter { !$0.isRead }.count
    }
    func markNotificationFeedRead(announcementLimit: Int) async throws {
        try await perform("/v1/notifications/read-all")
        let announcements: [SiteAnnouncement] = try await get("/v1/announcements", query(["limit":String(announcementLimit)]))
        for announcement in announcements where !announcement.isRead { try await markSiteAnnouncementRead(announcementID: announcement.id) }
    }
    func markNotificationRead(notificationID: UUID) async throws { try await perform("/v1/notifications/\(notificationID)/read") }
    func markSiteAnnouncementRead(announcementID: UUID) async throws { try await perform("/v1/announcements/\(announcementID)/read") }
    func dismissNotificationFeedItem(_ item: NotificationFeedItem) async throws {
        switch item {
        case .community(let item): try await perform("/v1/notifications/\(item.id)/dismiss")
        case .announcement(let item): try await perform("/v1/announcements/\(item.id)/dismiss")
        case .publication: break
        }
    }
}
