import Foundation
import SwiftData

/// Released personal records used a building-only key. Upgrade only unambiguous associations;
/// run on incoming iCloud records too, since an older device can still send the released format.
@MainActor
enum TimetableArrangementIdentityMigration {
    @discardableResult
    static func apply(courses: [Course], context: ModelContext) throws -> Bool {
        let currentKeys = Set(courses.map(\.stableCourseKey))
        var aliases: [String: [Course]] = [:]
        for course in courses {
            for alias in [course.previousStableCourseKey, course.legacyStableCourseKey] {
                aliases[alias, default: []].append(course)
            }
        }
        func candidates(key: String, week: Int? = nil) -> [Course]? {
            guard !currentKeys.contains(key), let matches = aliases[key] else { return nil }
            return matches.filter { course in week.map { course.weeks.contains($0) } ?? true }
        }
        let notes = try context.fetch(FetchDescriptor<CourseNote>())
        let occurrences = try context.fetch(FetchDescriptor<CourseOccurrenceNote>())
        let reminders = try context.fetch(FetchDescriptor<CourseReminderSetting>())
        var changed = false
        var migratedKeys = Set<String>()
        for note in notes {
            guard let matches = candidates(key: note.courseKey) else { continue }
            if Set(matches.map(\.stableCourseKey)).count == 1, let match = matches.first {
                note.courseKey = match.stableCourseKey
                migratedKeys.insert(match.stableCourseKey)
                changed = true
            } else if !note.isUnassociated {
                note.isUnassociated = true
                note.sourceCourseTitle = matches.first?.courseName ?? note.sourceCourseTitle
                changed = true
            }
        }
        for note in occurrences {
            guard let matches = candidates(key: note.courseKey, week: note.week) else { continue }
            if Set(matches.map(\.stableCourseKey)).count == 1, let match = matches.first {
                note.courseKey = match.stableCourseKey
                note.occurrenceKey = match.occurrenceKey(week: note.week)
                note.dayOfWeek = match.dayOfWeek
                migratedKeys.insert(match.stableCourseKey)
                changed = true
            } else if !note.isUnassociated {
                note.isUnassociated = true
                note.sourceCourseTitle = matches.first?.courseName ?? note.sourceCourseTitle
                changed = true
            }
        }
        for reminder in reminders {
            guard let matches = candidates(key: reminder.courseKey) else { continue }
            if Set(matches.map(\.stableCourseKey)).count == 1, let match = matches.first {
                reminder.courseKey = match.stableCourseKey
                migratedKeys.insert(match.stableCourseKey)
                changed = true
            } else if !reminder.isUnassociated {
                reminder.isUnassociated = true
                reminder.sourceCourseTitle = matches.first?.courseName ?? reminder.sourceCourseTitle
                changed = true
            }
        }
        // Preserve both texts/settings when released and current records disagree. Never choose a winner.
        for (key, group) in Dictionary(grouping: notes.filter { !$0.isUnassociated }, by: \.courseKey)
            where migratedKeys.contains(key) && Set(group.map(\.text)).count > 1 {
            for note in group { note.isUnassociated = true }
        }
        for group in Dictionary(grouping: occurrences.filter { !$0.isUnassociated }, by: \.occurrenceKey).values {
            if let first = group.first, migratedKeys.contains(first.courseKey), Set(group.map(\.text)).count > 1 {
                for note in group { note.isUnassociated = true }
            }
        }
        for (key, group) in Dictionary(grouping: reminders.filter { !$0.isUnassociated }, by: \.courseKey)
            where migratedKeys.contains(key) && Set(group.map { "\($0.minutesBefore):\($0.anchorPeriod ?? 0)" })
            .count > 1 {
            for reminder in group { reminder.isUnassociated = true }
        }
        return changed
    }

    static func run(context: ModelContext, save: (ModelContext) throws -> Void = { try $0.save() }) throws
        -> TimetableReminderRefreshPlan? {
        let courses = try context.fetch(FetchDescriptor<Course>())
        let undo = try TimetableLocalDataReassociation.personalDataUndo(in: context)
        do {
            guard try apply(courses: courses, context: context) else { return nil }
            let plan = try TimetableReminderRefreshPlan(
                oldIdentifiers: Array(Set(courses
                        .flatMap { TimetableNotificationManager.courseReminderIdentifiers(for: $0) })),
                courses: courses, settings: context.fetch(FetchDescriptor<CourseReminderSetting>())
            )
            try save(context)
            return plan
        } catch {
            undo()
            context.processPendingChanges()
            throw error
        }
    }
}
