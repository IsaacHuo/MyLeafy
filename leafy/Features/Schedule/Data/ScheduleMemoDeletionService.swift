import Foundation
import SwiftData

@MainActor
enum ScheduleMemoDeletionService {
    static func moveToTrash(_ memo: ScheduleMemo, now: Date = Date(), in context: ModelContext) throws {
        memo.trashedAt = now
        memo.pinnedAt = nil
        memo.updatedAt = now
        try context.save()
    }

    static func restore(_ memo: ScheduleMemo, now: Date = Date(), in context: ModelContext) throws {
        memo.trashedAt = nil
        memo.updatedAt = now
        try context.save()
    }

    static func permanentlyDelete(
        _ memo: ScheduleMemo,
        images: [ScheduleMemoImage],
        in context: ModelContext,
        imageDirectory: URL? = nil,
        saves: Bool = true
    ) throws {
        let ownedImages = images.filter { $0.memoID == memo.id }
        try ScheduleMemoImageStore.deleteFiles(named: ownedImages.map(\.localFilename), in: imageDirectory)
        ownedImages.forEach(context.delete)
        context.delete(memo)
        if saves { try context.save() }
    }
}

nonisolated enum ScheduleMemoLinkResolver {
    static func title(
        kind: ScheduleMemoLinkKind?,
        stableID: String?,
        timetableTitles: [String: String],
        importantDateTitles: [String: String]
    ) -> String? {
        guard let kind, let stableID else { return nil }
        switch kind {
        case .timetableReminder:
            return timetableTitles[stableID] ?? "原日程已删除"
        case .importantDate:
            return importantDateTitles[stableID] ?? "原日程已删除"
        }
    }
}
