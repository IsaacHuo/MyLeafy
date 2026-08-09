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
        attachments: [ScheduleMemoAttachment] = [],
        in context: ModelContext,
        imageDirectory: URL? = nil,
        attachmentDirectory: URL? = nil,
        saves: Bool = true
    ) throws {
        let imageRecords: [ScheduleMemoImage]
        if images.isEmpty {
            imageRecords = try context.fetch(FetchDescriptor<ScheduleMemoImage>())
        } else {
            imageRecords = images
        }
        let attachmentRecords: [ScheduleMemoAttachment]
        if attachments.isEmpty {
            attachmentRecords = try context.fetch(FetchDescriptor<ScheduleMemoAttachment>())
        } else {
            attachmentRecords = attachments
        }
        let ownedImages = imageRecords.filter { $0.memoID == memo.id }
        let ownedAttachments = attachmentRecords.filter { $0.memoID == memo.id }
        try ScheduleMemoImageStore.deleteFiles(named: ownedImages.map(\.localFilename), in: imageDirectory)
        try ScheduleMemoAttachmentStore.deleteFiles(
            named: ownedAttachments.map(\.localFilename),
            in: attachmentDirectory
        )
        ownedImages.forEach(context.delete)
        ownedAttachments.forEach(context.delete)
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
