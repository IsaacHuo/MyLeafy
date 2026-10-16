import Foundation
import SwiftData
import UserNotifications

@MainActor
enum TimetableSingleContainerMigration {
    static func run(context: ModelContext, defaults: UserDefaults = .standard) throws {
        let key = CampusScopedDefaults.key("timetable.singleContainer.v1", defaults: defaults)
        guard !defaults.bool(forKey: key) else { return }
        let courses = try context.fetch(FetchDescriptor<Course>())
        let ids = Set(courses.map(\.sourceSemesterID))
        let latest = TimetableCacheMetadata.lastSyncedSemesterID.flatMap { ids.contains($0) ? $0 : nil }
            ?? ids.sorted { $0.compare($1, options: .numeric) == .orderedDescending }.first
        let removed = courses.filter { $0.sourceSemesterID != latest }
        let keys = Set(removed.flatMap { [$0.stableCourseKey, $0.legacyStableCourseKey] })
        let identifiers = removed.flatMap { TimetableNotificationManager.courseReminderIdentifiers(for: $0) }
        do {
            for note in try context.fetch(FetchDescriptor<CourseNote>()) where keys.contains(note.courseKey) {
                note.isUnassociated = true
                note.sourceCourseTitle = removed.first { $0.stableCourseKey == note.courseKey || $0.legacyStableCourseKey == note.courseKey }?.courseName ?? ""
            }
            for note in try context.fetch(FetchDescriptor<CourseOccurrenceNote>()) where keys.contains(note.courseKey) {
                note.isUnassociated = true
                note.sourceCourseTitle = removed.first { $0.stableCourseKey == note.courseKey || $0.legacyStableCourseKey == note.courseKey }?.courseName ?? ""
            }
            for setting in try context.fetch(FetchDescriptor<CourseReminderSetting>()) where keys.contains(setting.courseKey) {
                setting.isUnassociated = true
                setting.sourceCourseTitle = removed.first { $0.stableCourseKey == setting.courseKey || $0.legacyStableCourseKey == setting.courseKey }?.courseName ?? ""
            }
            for course in removed { context.delete(course) }
            try context.save()
            defaults.set(true, forKey: key)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        } catch { context.rollback(); throw error }
    }
}
