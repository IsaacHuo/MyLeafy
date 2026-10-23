import Foundation
import SwiftData

@MainActor
enum ScheduleMemoPersistence {
    static func insert(
        _ memo: ScheduleMemo,
        resources: [any PersistentModel] = [],
        in context: ModelContext,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        let inserted: [any PersistentModel] = [memo] + resources
        inserted.forEach { context.insert($0) }
        try LocalModelSave.save(context, undo: {
            inserted.forEach { context.delete($0) }
        }, using: save)
    }

    /// A cleanup warning means the edit committed and must not be submitted again.
    static func update(
        _ memo: ScheduleMemo,
        title: String?,
        body: String,
        inserting: [any PersistentModel] = [],
        removing: [any PersistentModel] = [],
        files: [LocalFileCleanup.File] = [],
        in context: ModelContext,
        cleanup: LocalFileCleanup? = nil,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> String? {
        let cleanup = cleanup ?? LocalFileCleanup()
        try cleanup.enqueue(files)
        let previous = (memo.title, memo.body, memo.tagsRawValue, memo.updatedAt)
        inserting.forEach { context.insert($0) }
        removing.forEach { context.delete($0) }
        memo.title = title
        memo.updateBody(body)
        try LocalModelSave.save(context, undo: {
            inserting.forEach { context.delete($0) }
            removing.forEach { context.insert($0) }
            memo.title = previous.0
            memo.body = previous.1
            memo.tagsRawValue = previous.2
            memo.updatedAt = previous.3
        }, using: save)
        guard !files.isEmpty else { return nil }
        do {
            try cleanup.retry(in: context)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
