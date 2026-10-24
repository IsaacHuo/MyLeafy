import SwiftData

@MainActor
enum LocalModelSave {
    static func save(
        _ context: ModelContext,
        undo: () -> Void,
        using operation: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        do { try operation(context) }
        catch {
            // Undo only this operation; rollback() also discards other open editors.
            undo()
            // Reinserted deletions remain filtered from fetches until pending changes are processed.
            context.processPendingChanges()
            throw error
        }
    }

    static func delete<T: PersistentModel>(_ model: T, in context: ModelContext) throws {
        context.delete(model)
        try save(context, undo: { context.insert(model) })
    }
}
