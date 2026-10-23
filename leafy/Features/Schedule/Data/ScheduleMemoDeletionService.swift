import Foundation
import SwiftData

@MainActor
enum ScheduleMemoDeletionService {
    static func moveToTrash(_ memo: ScheduleMemo, now: Date = Date(), in context: ModelContext) throws {
        let previous = (memo.trashedAt, memo.pinnedAt, memo.updatedAt)
        memo.trashedAt = now
        memo.pinnedAt = nil
        memo.updatedAt = now
        try LocalModelSave.save(context, undo: {
            memo.trashedAt = previous.0
            memo.pinnedAt = previous.1
            memo.updatedAt = previous.2
        })
    }

    static func restore(_ memo: ScheduleMemo, now: Date = Date(), in context: ModelContext) throws {
        let previous = (memo.trashedAt, memo.updatedAt)
        memo.trashedAt = nil
        memo.updatedAt = now
        try LocalModelSave.save(context, undo: {
            memo.trashedAt = previous.0
            memo.updatedAt = previous.1
        })
    }

    static func permanentlyDelete(
        _ memo: ScheduleMemo, images: [ScheduleMemoImage], attachments: [ScheduleMemoAttachment] = [],
        audioRecords: [ScheduleMemoAudio] = [], in context: ModelContext,
        imageDirectory: URL? = nil, attachmentDirectory: URL? = nil, audioDirectory: URL? = nil,
        cleanup: LocalFileCleanup? = nil, save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        try permanentlyDelete(
            [memo], images: images, attachments: attachments, audioRecords: audioRecords, in: context,
            imageDirectory: imageDirectory, attachmentDirectory: attachmentDirectory, audioDirectory: audioDirectory,
            cleanup: cleanup, save: save
        )
    }

    static func permanentlyDelete(
        _ memos: [ScheduleMemo], images: [ScheduleMemoImage], attachments: [ScheduleMemoAttachment] = [],
        audioRecords: [ScheduleMemoAudio] = [], in context: ModelContext,
        imageDirectory: URL? = nil, attachmentDirectory: URL? = nil, audioDirectory: URL? = nil,
        cleanup: LocalFileCleanup? = nil, save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        let ids = Set(memos.map(\.id))
        let ownedImages = try (images.isEmpty ? context.fetch(FetchDescriptor<ScheduleMemoImage>()) : images)
            .filter { ids.contains($0.memoID) }
        let ownedAttachments = try (attachments.isEmpty ? context
            .fetch(FetchDescriptor<ScheduleMemoAttachment>()) : attachments).filter { ids.contains($0.memoID) }
        let ownedAudio = try (audioRecords.isEmpty ? context.fetch(FetchDescriptor<ScheduleMemoAudio>()) : audioRecords)
            .filter { ids.contains($0.memoID) }
        let files = ownedImages.map {
            LocalFileCleanup.File(
                $0,
                url: (imageDirectory ?? ScheduleMemoImageStore.directoryURL()).appendingPathComponent($0.localFilename)
            )
        } + ownedAttachments.compactMap { record in
            ScheduleMemoAttachmentStore.fileURL(named: record.localFilename, in: attachmentDirectory)
                .map { LocalFileCleanup.File(
                    record,
                    url: $0
                ) }
        } + ownedAudio.compactMap { record in
            ScheduleMemoAudioStore.fileURL(named: record.localFilename, in: audioDirectory).map { LocalFileCleanup.File(
                record,
                url: $0
            ) }
        }
        let models: [any PersistentModel] = memos + ownedImages + ownedAttachments + ownedAudio
        try (cleanup ?? LocalFileCleanup()).delete(models, files: files, in: context, save: save)
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
