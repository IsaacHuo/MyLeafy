import Foundation
import SwiftData

@MainActor
private protocol TimetableNoteRecord: PersistentModel {
    var text: String { get set }
    var updatedAt: Date { get set }
}

extension CourseNote: TimetableNoteRecord {}
extension CourseOccurrenceNote: TimetableNoteRecord {}

@MainActor
enum TimetableLocalEdits {
    static func cellReminderUndo(_ record: TimetableCellReminder) -> () -> Void {
        let previous = (record.week, record.dayOfWeek, record.period, record.endPeriod, record.cellKey,
            record.title, record.location, record.note, record.startsAt, record.endsAt,
            record.minutesBefore, record.updatedAt)
        return {
            record.week = previous.0; record.dayOfWeek = previous.1; record.period = previous.2
            record.endPeriod = previous.3; record.cellKey = previous.4; record.title = previous.5
            record.location = previous.6; record.note = previous.7; record.startsAt = previous.8
            record.endsAt = previous.9; record.minutesBefore = previous.10; record.updatedAt = previous.11
        }
    }

    static func setCourseNote(
        _ text: String, courseKey: String, in context: ModelContext,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        let existing = try context.fetch(FetchDescriptor<CourseNote>()).first { !$0.isUnassociated && $0.courseKey == courseKey }
        try setNote(text, existing: existing, create: { CourseNote(courseKey: courseKey) }, in: context, save: save)
    }

    static func setOccurrenceNote(
        _ text: String, courseKey: String, occurrenceKey: String, week: Int, dayOfWeek: Int,
        in context: ModelContext, save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        let existing = try context.fetch(FetchDescriptor<CourseOccurrenceNote>()).first { !$0.isUnassociated && $0.occurrenceKey == occurrenceKey }
        try setNote(text, existing: existing, create: {
            CourseOccurrenceNote(courseKey: courseKey, occurrenceKey: occurrenceKey, week: week, dayOfWeek: dayOfWeek)
        }, in: context, save: save)
    }

    private static func setNote<T: TimetableNoteRecord>(
        _ text: String, existing: T?, create: () -> T, in context: ModelContext,
        save: (ModelContext) throws -> Void
    ) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard existing != nil || !trimmed.isEmpty else { try save(context); return }
        let note = existing ?? create()
        let previous = (note.text, note.updatedAt)
        if trimmed.isEmpty {
            context.delete(note)
        } else {
            if existing == nil { context.insert(note) }
            note.text = trimmed
            note.updatedAt = Date()
        }
        try LocalModelSave.save(context, undo: {
            if existing == nil { context.delete(note) }
            else {
                if trimmed.isEmpty { context.insert(note) }
                note.text = previous.0
                note.updatedAt = previous.1
            }
        }, using: save)
    }

    static func setReminder(
        courseKey: String, minutesBefore: Int, anchorPeriod: Int?, in context: ModelContext,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        let existing = try context.fetch(FetchDescriptor<CourseReminderSetting>()).first { !$0.isUnassociated && $0.courseKey == courseKey }
        let setting = existing ?? CourseReminderSetting(courseKey: courseKey)
        let previous = (setting.minutesBefore, setting.anchorPeriod, setting.updatedAt)
        if existing == nil { context.insert(setting) }
        setting.minutesBefore = minutesBefore
        setting.anchorPeriod = anchorPeriod
        setting.updatedAt = Date()
        try LocalModelSave.save(context, undo: {
            if existing == nil { context.delete(setting) }
            else {
                setting.minutesBefore = previous.0
                setting.anchorPeriod = previous.1
                setting.updatedAt = previous.2
            }
        }, using: save)
    }
}
