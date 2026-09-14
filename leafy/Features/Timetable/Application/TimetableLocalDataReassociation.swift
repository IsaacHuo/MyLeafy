import Foundation
import SwiftData

enum TimetableLocalDataConflict: LocalizedError {
    case conflictingRecords(String)
    case ambiguousOccurrence(String, Int)

    var errorDescription: String? {
        switch self {
        case .conflictingRecords(let name):
            return L10n.text("“%@”的备注或提醒存在冲突，课表未更新。请检查相关记录后重试。", name)
        case .ambiguousOccurrence(let name, let week):
            return L10n.text("无法确定“%@”第 %d 周备注对应的课次，课表未更新。原课表和备注已保留。", name, week)
        }
    }
}

/// Preflights all associations before changing the context. The existing course keys remain
/// authoritative; only a verified teacher/period split creates associations with new keys.
@MainActor
struct TimetableLocalDataReassociation {
    private struct NoteValue {
        let text: String
        let updatedAt: Date
    }

    private struct ReminderValue {
        let minutesBefore: Int
        let anchorPeriod: Int?
        let updatedAt: Date
    }

    private struct OccurrenceMove {
        let note: CourseOccurrenceNote
        let courseKey: String
    }

    private var noteValues: [String: NoteValue] = [:]
    private var reminderValues: [String: ReminderValue] = [:]
    private var occurrenceMoves: [UUID: OccurrenceMove] = [:]
    private var duplicateOccurrences: [CourseOccurrenceNote] = []
    private let notes: [CourseNote]
    private let reminders: [CourseReminderSetting]

    init(oldCourses: [Course], newCourses: [Course], context: ModelContext) throws {
        notes = try context.fetch(FetchDescriptor<CourseNote>())
        reminders = try context.fetch(FetchDescriptor<CourseReminderSetting>())
        let occurrences = try context.fetch(FetchDescriptor<CourseOccurrenceNote>())
        let oldByKey = Dictionary(grouping: oldCourses, by: \.stableCourseKey)

        for (oldKey, oldGroup) in oldByKey {
            // Already-separated teaching arrangements may coexist in the same week. If
            // this key still covers its original occurrences, their independent notes
            // must not be copied into another teacher's existing arrangement.
            let stillCovered = oldGroup.allSatisfy { old in
                old.weeks.allSatisfy { week in
                    newCourses.contains {
                        $0.stableCourseKey == oldKey && Self.sameArrangement($0, old) && $0.weeks.contains(week)
                    }
                }
            }
            if stillCovered { continue }
            let candidates = newCourses.filter { new in
                oldGroup.contains { old in Self.isSplitCandidate(new, of: old) }
            }
            guard candidates.contains(where: { $0.stableCourseKey != oldKey }) else { continue }

            let name = oldGroup[0].courseName
            let sourceNotes = notes.filter { $0.courseKey == oldKey }
            let sourceReminders = reminders.filter { $0.courseKey == oldKey }
            let sourceOccurrences = occurrences.filter { $0.courseKey == oldKey }

            // A legacy key omits room/classInfo. If it names different original arrangements,
            // local records cannot reliably identify which arrangement the user annotated.
            if !sourceNotes.isEmpty || !sourceReminders.isEmpty || !sourceOccurrences.isEmpty {
                guard oldGroup.allSatisfy({ Self.sameArrangement($0, oldGroup[0]) }) else {
                    throw TimetableLocalDataConflict.conflictingRecords(name)
                }
            }

            let targetKeys = Set(candidates.map(\.stableCourseKey)).union([oldKey])
            if let source = try Self.noteValue(sourceNotes, name: name) {
                for key in targetKeys {
                    let existing = try Self.noteValue(notes.filter { $0.courseKey == key }, name: name)
                    let previous = noteValues[key] ?? existing
                    if let previous, previous.text != source.text {
                        throw TimetableLocalDataConflict.conflictingRecords(name)
                    }
                    noteValues[key] = NoteValue(text: source.text, updatedAt: max(source.updatedAt, previous?.updatedAt ?? .distantPast))
                }
            }
            if let source = try Self.reminderValue(sourceReminders, name: name) {
                for key in targetKeys {
                    let existing = try Self.reminderValue(reminders.filter { $0.courseKey == key }, name: name)
                    let previous = reminderValues[key] ?? existing
                    if let previous, previous.minutesBefore != source.minutesBefore || previous.anchorPeriod != source.anchorPeriod {
                        throw TimetableLocalDataConflict.conflictingRecords(name)
                    }
                    reminderValues[key] = ReminderValue(
                        minutesBefore: source.minutesBefore,
                        anchorPeriod: source.anchorPeriod,
                        updatedAt: max(source.updatedAt, previous?.updatedAt ?? .distantPast)
                    )
                }
            }

            for note in sourceOccurrences {
                guard oldGroup.contains(where: { $0.weeks.contains(note.week) && $0.dayOfWeek == note.dayOfWeek }) else {
                    throw TimetableLocalDataConflict.ambiguousOccurrence(name, note.week)
                }
                let targets = candidates.filter { $0.weeks.contains(note.week) && $0.dayOfWeek == note.dayOfWeek }
                guard targets.count == 1, let target = targets.first else {
                    throw TimetableLocalDataConflict.ambiguousOccurrence(name, note.week)
                }
                occurrenceMoves[note.id] = OccurrenceMove(note: note, courseKey: target.stableCourseKey)
            }
        }

        // Validate the final destinations together, including records already at a target.
        // This catches two old arrangements trying to overwrite the same occurrence.
        let touchedKeys = Set(occurrenceMoves.values.map {
            CourseOccurrenceNote.occurrenceKey(courseKey: $0.courseKey, week: $0.note.week)
        })
        let byDestination = Dictionary(grouping: occurrences) { note in
            occurrenceMoves[note.id].map {
                CourseOccurrenceNote.occurrenceKey(courseKey: $0.courseKey, week: note.week)
            } ?? note.occurrenceKey
        }
        for key in touchedKeys {
            let group = byDestination[key, default: []]
            guard Set(group.map(\.text)).count <= 1 else {
                let moving = group.first { occurrenceMoves[$0.id] != nil }!
                let name = oldCourses.first { $0.stableCourseKey == moving.courseKey }?.courseName ?? ""
                throw TimetableLocalDataConflict.conflictingRecords(name)
            }
            let sorted = group.sorted { $0.updatedAt > $1.updatedAt }
            for duplicate in sorted.dropFirst() {
                occurrenceMoves.removeValue(forKey: duplicate.id)
                duplicateOccurrences.append(duplicate)
            }
        }
    }

    func apply(to context: ModelContext) {
        for (key, value) in noteValues {
            let existing = notes.filter { $0.courseKey == key }.sorted { $0.updatedAt > $1.updatedAt }
            if let note = existing.first {
                note.updatedAt = value.updatedAt
                for duplicate in existing.dropFirst() { context.delete(duplicate) }
            } else {
                context.insert(CourseNote(courseKey: key, text: value.text, updatedAt: value.updatedAt))
            }
        }
        for (key, value) in reminderValues {
            let existing = reminders.filter { $0.courseKey == key }.sorted { $0.updatedAt > $1.updatedAt }
            if let reminder = existing.first {
                reminder.updatedAt = value.updatedAt
                for duplicate in existing.dropFirst() { context.delete(duplicate) }
            } else {
                context.insert(CourseReminderSetting(
                    courseKey: key, minutesBefore: value.minutesBefore,
                    anchorPeriod: value.anchorPeriod, updatedAt: value.updatedAt
                ))
            }
        }
        for move in occurrenceMoves.values {
            move.note.courseKey = move.courseKey
            move.note.occurrenceKey = CourseOccurrenceNote.occurrenceKey(courseKey: move.courseKey, week: move.note.week)
        }
        for duplicate in duplicateOccurrences { context.delete(duplicate) }
    }

    private static func noteValue(_ values: [CourseNote], name: String) throws -> NoteValue? {
        guard let latest = values.max(by: { $0.updatedAt < $1.updatedAt }) else { return nil }
        guard values.allSatisfy({ $0.text == latest.text }) else {
            throw TimetableLocalDataConflict.conflictingRecords(name)
        }
        return NoteValue(text: latest.text, updatedAt: latest.updatedAt)
    }

    private static func reminderValue(_ values: [CourseReminderSetting], name: String) throws -> ReminderValue? {
        guard let latest = values.max(by: { $0.updatedAt < $1.updatedAt }) else { return nil }
        guard values.allSatisfy({ $0.minutesBefore == latest.minutesBefore && $0.anchorPeriod == latest.anchorPeriod }) else {
            throw TimetableLocalDataConflict.conflictingRecords(name)
        }
        return ReminderValue(minutesBefore: latest.minutesBefore, anchorPeriod: latest.anchorPeriod, updatedAt: latest.updatedAt)
    }

    private static func sameArrangement(_ lhs: Course, _ rhs: Course) -> Bool {
        samePlaceAndClass(lhs, rhs) && lhs.duration.sorted() == rhs.duration.sorted()
    }

    private static func samePlaceAndClass(_ lhs: Course, _ rhs: Course) -> Bool {
        lhs.sourceSemesterID == rhs.sourceSemesterID && normalized(lhs.courseName) == normalized(rhs.courseName) &&
        normalized(lhs.classInfo) == normalized(rhs.classInfo) && lhs.dayOfWeek == rhs.dayOfWeek &&
        normalized(lhs.room) == normalized(rhs.room) && normalized(lhs.location) == normalized(rhs.location)
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private static func isSplitCandidate(_ new: Course, of old: Course) -> Bool {
        samePlaceAndClass(new, old) && !new.duration.isEmpty &&
        Set(new.duration).isSubset(of: Set(old.duration)) &&
        !Set(new.weeks).isDisjoint(with: old.weeks)
    }
}
