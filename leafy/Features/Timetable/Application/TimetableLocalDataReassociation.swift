import Foundation
import SwiftData

enum TimetableLocalDataConflict: LocalizedError {
    case conflictingRecords(String)
    case ambiguousArrangement(String)
    case ambiguousOccurrence(String, Int)
    var errorDescription: String? {
        switch self {
        case .ambiguousArrangement(let name): return L10n.text("学校返回的“%@”在同一时段有不同班级或教室，无法确定排课，已保留当前课表。", name)
        case .conflictingRecords(let name): return L10n.text("“%@”存在不同的备注或提醒。请保留原记录并选择其他课程，或先编辑现有内容。", name)
        case .ambiguousOccurrence(let name, let week): return L10n.text("无法确定“%@”第 %d 周备注对应的课次，请手动关联。", name, week)
        }
    }
}

/// Personal edits survive every course replacement. Ambiguity is explicit and nonblocking.
@MainActor
struct TimetableLocalDataReassociation {
    let oldCourses: [Course]
    let newCourses: [Course]
    let context: ModelContext
    init(oldCourses: [Course], newCourses: [Course], context: ModelContext) throws {
        self.oldCourses = oldCourses; self.newCourses = newCourses; self.context = context
    }
    /// Capture the current editor values, including unsaved edits, before reassociation.
    static func personalDataUndo(in context: ModelContext) throws -> () -> Void {
        let inserted = Set(context.insertedModelsArray.map { ObjectIdentifier($0) })
        let notes = try context.fetch(FetchDescriptor<CourseNote>()).map { note in
            let previous = (note.courseKey, note.isUnassociated, note.sourceCourseTitle, note.updatedAt)
            return { context.insert(note); note.courseKey = previous.0; note.isUnassociated = previous.1
                note.sourceCourseTitle = previous.2; note.updatedAt = previous.3 }
        }
        let occurrences = try context.fetch(FetchDescriptor<CourseOccurrenceNote>()).map { note in
            let previous = (note.courseKey, note.occurrenceKey, note.dayOfWeek, note.isUnassociated, note.sourceCourseTitle, note.updatedAt)
            return { context.insert(note); note.courseKey = previous.0; note.occurrenceKey = previous.1
                note.dayOfWeek = previous.2; note.isUnassociated = previous.3
                note.sourceCourseTitle = previous.4; note.updatedAt = previous.5 }
        }
        let reminders = try context.fetch(FetchDescriptor<CourseReminderSetting>()).map { setting in
            let previous = (setting.courseKey, setting.isUnassociated, setting.sourceCourseTitle, setting.updatedAt)
            return { context.insert(setting); setting.courseKey = previous.0; setting.isUnassociated = previous.1
                setting.sourceCourseTitle = previous.2; setting.updatedAt = previous.3 }
        }
        return {
            for model in context.insertedModelsArray where !inserted.contains(ObjectIdentifier(model)) {
                if model is CourseNote || model is CourseOccurrenceNote || model is CourseReminderSetting {
                    context.delete(model)
                }
            }
            for restore in notes + occurrences + reminders { restore() }
        }
    }
    private func targets(for old: Course) -> [Course] {
        let exact = newCourses.filter { $0.legacyStableCourseKey == old.legacyStableCourseKey && $0.classInfo == old.classInfo }
        if !exact.isEmpty && old.weeks.allSatisfy({ week in exact.contains { $0.weeks.contains(week) } }) { return exact }
        let candidates = newCourses.filter {
            normalized($0.courseName) == normalized(old.courseName) && normalized($0.classInfo) == normalized(old.classInfo)
        }
        // Do not infer a new class when multiple old arrangements have this name/class.
        let oldKeys = Set(oldCourses.filter {
            normalized($0.courseName) == normalized(old.courseName) && normalized($0.classInfo) == normalized(old.classInfo)
        }.map(\.stableCourseKey))
        if candidates.count == 1 && oldKeys.count == 1 { return candidates }
        let split = candidates.filter { $0.dayOfWeek == old.dayOfWeek && $0.room == old.room
            && $0.location == old.location && Set($0.duration).isSubset(of: Set(old.duration))
            && !Set($0.weeks).isDisjoint(with: old.weeks) }
        return oldKeys.count == 1 ? split : []
    }
    private func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    private func preferredID(_ records: [(UUID, String, Date)], origins: [UUID: (String, Date)], prefersDestination: Bool = true) -> UUID {
        records.sorted { left, right in
            let leftOrigin = origins[left.0], rightOrigin = origins[right.0]
            let leftStayed = leftOrigin?.0 == left.1, rightStayed = rightOrigin?.0 == right.1
            if prefersDestination && leftStayed != rightStayed { return leftStayed }
            let leftDate = leftOrigin?.1 ?? left.2, rightDate = rightOrigin?.1 ?? right.2
            if leftDate != rightDate { return leftDate > rightDate }
            return left.0.uuidString < right.0.uuidString
        }[0].0
    }
    func apply(to context: ModelContext) throws {
        let notes = try context.fetch(FetchDescriptor<CourseNote>())
        let occurrences = try context.fetch(FetchDescriptor<CourseOccurrenceNote>())
        let reminders = try context.fetch(FetchDescriptor<CourseReminderSetting>())
        let noteOrigins = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, ($0.courseKey, $0.updatedAt)) })
        let occurrenceOrigins = Dictionary(uniqueKeysWithValues: occurrences.map { ($0.id, ($0.occurrenceKey, $0.updatedAt)) })
        let reminderOrigins = Dictionary(uniqueKeysWithValues: reminders.map { ($0.id, ($0.courseKey, $0.updatedAt)) })
        for note in notes where !note.isUnassociated {
            guard let old = oldCourses.first(where: { $0.stableCourseKey == note.courseKey }) else {
                note.isUnassociated = !newCourses.contains { $0.stableCourseKey == note.courseKey }
                continue
            }
            note.sourceCourseTitle = old.courseName
            let keys = Array(Set(targets(for: old).map(\.stableCourseKey))).sorted {
                if ($0 == old.stableCourseKey) != ($1 == old.stableCourseKey) { return $0 == old.stableCourseKey }
                return $0 < $1
            }
            guard !keys.isEmpty, keys.allSatisfy({ key in !notes.contains { $0.id != note.id && !$0.isUnassociated && $0.courseKey == key && $0.text != note.text } }) else {
                note.isUnassociated = true
                continue
            }
            note.updatedAt = max(note.updatedAt, notes.filter { keys.contains($0.courseKey) && !$0.isUnassociated }.map(\.updatedAt).max() ?? .distantPast)
            for target in notes where keys.contains(target.courseKey) && !target.isUnassociated {
                target.updatedAt = note.updatedAt
            }
            note.courseKey = keys[0]
            for key in keys.dropFirst() where !notes.contains(where: { $0.courseKey == key && !$0.isUnassociated }) {
                context.insert(CourseNote(courseKey: key, text: note.text, updatedAt: note.updatedAt))
            }
        }
        for note in occurrences where !note.isUnassociated {
            guard let old = oldCourses.first(where: { $0.stableCourseKey == note.courseKey }) else {
                note.isUnassociated = !newCourses.contains { $0.stableCourseKey == note.courseKey }
                continue
            }
            note.sourceCourseTitle = old.courseName
            let matches = targets(for: old).filter { $0.weeks.contains(note.week) }
            let keys = Set(matches.map(\.stableCourseKey))
            guard keys.count == 1, let key = keys.first,
                  !occurrences.contains(where: { $0.id != note.id && !$0.isUnassociated && $0.courseKey == key && $0.week == note.week && $0.text != note.text }) else {
                note.isUnassociated = true
                continue
            }
            note.courseKey = key
            note.dayOfWeek = matches[0].dayOfWeek
            note.occurrenceKey = CourseOccurrenceNote.occurrenceKey(courseKey: key, week: note.week)
        }
        for setting in reminders where !setting.isUnassociated {
            guard let old = oldCourses.first(where: { $0.stableCourseKey == setting.courseKey }) else {
                setting.isUnassociated = !newCourses.contains { $0.stableCourseKey == setting.courseKey }
                continue
            }
            setting.sourceCourseTitle = old.courseName
            let matches = targets(for: old)
            let keys = Array(Set(matches.map(\.stableCourseKey))).sorted {
                if ($0 == old.stableCourseKey) != ($1 == old.stableCourseKey) { return $0 == old.stableCourseKey }
                return $0 < $1
            }
            guard !keys.isEmpty, keys.allSatisfy({ key in !reminders.contains { $0.id != setting.id && !$0.isUnassociated && $0.courseKey == key && ($0.minutesBefore != setting.minutesBefore || $0.anchorPeriod != setting.anchorPeriod) } }) else {
                setting.isUnassociated = true
                continue
            }
            setting.updatedAt = max(setting.updatedAt, reminders.filter { keys.contains($0.courseKey) && !$0.isUnassociated }.map(\.updatedAt).max() ?? .distantPast)
            for target in reminders where keys.contains(target.courseKey) && !target.isUnassociated {
                target.updatedAt = setting.updatedAt
            }
            setting.courseKey = keys[0]
            let oldAnchor = setting.anchorPeriod
            for key in keys.dropFirst() where !reminders.contains(where: { $0.courseKey == key && !$0.isUnassociated }) {
                context.insert(CourseReminderSetting(courseKey: key, minutesBefore: setting.minutesBefore,
                    anchorPeriod: oldAnchor, updatedAt: setting.updatedAt))
            }
        }
        for group in Dictionary(grouping: try context.fetch(FetchDescriptor<CourseNote>()).filter { !$0.isUnassociated }, by: \.courseKey).values {
            if Set(group.map(\.text)).count == 1 {
                let id = preferredID(group.map { ($0.id, $0.courseKey, $0.updatedAt) }, origins: noteOrigins)
                group.first { $0.id == id }?.updatedAt = group.map(\.updatedAt).max()!
                for duplicate in group where duplicate.id != id { context.delete(duplicate) }
            }
        }
        for group in Dictionary(grouping: try context.fetch(FetchDescriptor<CourseOccurrenceNote>()).filter { !$0.isUnassociated }, by: \.occurrenceKey).values {
            if Set(group.map(\.text)).count == 1 {
                let id = preferredID(group.map { ($0.id, $0.occurrenceKey, $0.updatedAt) }, origins: occurrenceOrigins, prefersDestination: false)
                group.first { $0.id == id }?.updatedAt = group.map(\.updatedAt).max()!
                for duplicate in group where duplicate.id != id { context.delete(duplicate) }
            }
        }
        for group in Dictionary(grouping: try context.fetch(FetchDescriptor<CourseReminderSetting>()).filter { !$0.isUnassociated }, by: \.courseKey).values {
            if Set(group.map { "\($0.minutesBefore):\($0.anchorPeriod ?? 0)" }).count == 1 {
                let id = preferredID(group.map { ($0.id, $0.courseKey, $0.updatedAt) }, origins: reminderOrigins)
                group.first { $0.id == id }?.updatedAt = group.map(\.updatedAt).max()!
                for duplicate in group where duplicate.id != id { context.delete(duplicate) }
            }
        }
    }
}
