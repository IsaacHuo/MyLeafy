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
            throw error
        }
    }

    static func delete<T: PersistentModel>(_ model: T, in context: ModelContext) throws {
        context.delete(model)
        try save(context, undo: { context.insert(model) })
    }
}
