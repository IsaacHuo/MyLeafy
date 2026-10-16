import Foundation
import SwiftData

@MainActor
enum ICloudLocalData {
    static let preferenceKeys = ["appThemeColorPreference", "appThemeCustomColorHex", "appAppearancePreference",
        "appFontSizePreference", "appLanguagePreference", "appIconAppearancePreference", "timetableHidesWeekends",
        "timetableCurrentTimeIndicatorEnabled", "timetableCurrentTimeIndicatorThickness", "timetableCurrentTimeIndicatorTransparency",
        "timetableBackground.isEnabled", "timetableBackground.kind", "timetableBackground.filename",
        "timetableBackground.displayMode", "timetableBackground.imageOpacity", "timetableBackground.blurRadius",
        "timetableBackground.overlayOpacity", "timetableBackground.courseCardOpacity", "timetableBackground.lightPalette",
        "timetableBackground.darkPalette", "timetableBackground.solidColor"]

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    static func capture(context: ModelContext, journal: ICloudSyncJournal) throws -> [ICloudSyncValue] {
        var result: [ICloudSyncValue] = []
        func append<T: Encodable>(_ key: String, _ value: T, date: Date = Date()) throws {
            result.append(ICloudSyncValue(key: key, payload: try encode(value), modifiedAt: date))
        }
        func models<T: ICloudModelValue>(_ type: T.Type) throws {
            for model in try context.fetch(FetchDescriptor<T.Model>()) {
                let value = T(model)
                try append(T.kind + "/" + value.id.uuidString.lowercased(), value, date: value.syncDate)
            }
        }
        let courses = try context.fetch(FetchDescriptor<Course>()).map(SyncedCourse.init).sorted { $0.id.uuidString < $1.id.uuidString }
        if !courses.isEmpty || journal.records["school/courses"] != nil {
            try append("school/courses", courses, date: TimetableCacheMetadata.lastSyncAt ?? .distantPast)
        }
        let grades = try context.fetch(FetchDescriptor<Grade>()).map(SyncedGrade.init).sorted { $0.id.uuidString < $1.id.uuidString }
        if !grades.isEmpty || journal.records["school/grades"] != nil { try append("school/grades", grades, date: SchoolDataCache.lastSyncDate(for: .gradeDetails) ?? .distantPast) }
        let supplemental = ICloudGradeSupplemental(rankings: SchoolDataCache.loadGradeRankings(), summary: SchoolDataCache.loadGradeCreditSummary())
        if !supplemental.rankings.isEmpty || supplemental.summary != nil || journal.records["school/gradeSupplemental"] != nil {
            try append("school/gradeSupplemental", supplemental, date: SchoolDataCache.lastSyncDate(for: .gradeRankings) ?? .distantPast)
        }
        let exams = SchoolDataCache.loadExamSchedule()
        if !exams.isEmpty || journal.records["school/exams"] != nil { try append("school/exams", exams, date: SchoolDataCache.lastSyncDate(for: .examSchedule) ?? .distantPast) }
        try models(SyncedCourseNote.self); try models(SyncedCourseOccurrenceNote.self)
        try models(SyncedCourseReminderSetting.self); try models(SyncedTimetableCellReminder.self)
        try models(SyncedScheduleMemo.self); try models(SyncedScheduleMemoImage.self)
        try models(SyncedScheduleMemoAttachment.self); try models(SyncedScheduleMemoAudio.self)
        for event in try CustomScheduleStore.loadForSync() { try append("CustomSchedule/" + event.id, event, date: event.updatedAt ?? event.createdAt ?? .distantPast) }
        let defaults = UserDefaults.standard
        for key in preferenceKeys {
            if let value = defaults.object(forKey: key) {
                let data = try PropertyListSerialization.data(fromPropertyList: ["value": value], format: .binary, options: 0)
                try append("preference/" + key, data, date: journal.records["preference/" + key] == nil ? .distantPast : Date())
            }
        }
        // Freeze the initial effective settings when sync is first enabled.
        try append("settings/timetable", UserTimetableSettingsStore.load(), date: defaults.object(forKey: CampusScopedDefaults.key(UserTimetableSettingsStore.key + ".editedAt")) as? Date ?? .distantPast)
        func file(_ path: String) throws {
            let url = try fileURL(path)
            if FileManager.default.fileExists(atPath: url.path) {
                let digest = try fileDigest(url)
                result.append(ICloudSyncValue(key: "file/" + path, payload: Data(), modifiedAt: Date(), filePath: path, fileDigest: digest))
            } else if let previous = journal.records["file/" + path], !previous.deleted {
                result.append(previous)
            } else { throw ICloudSyncFailure.message("附件文件缺失：\(url.lastPathComponent)。请恢复文件后重试同步。") }
        }
        for image in try context.fetch(FetchDescriptor<ScheduleMemoImage>()) { try file("images/" + image.localFilename) }
        for attachment in try context.fetch(FetchDescriptor<ScheduleMemoAttachment>()) { try file("attachments/" + attachment.localFilename) }
        for audio in try context.fetch(FetchDescriptor<ScheduleMemoAudio>()) { try file("audio/" + audio.localFilename) }
        if let filename = defaults.string(forKey: TimetableBackgroundStore.filenameKey), !filename.isEmpty { try file("background/" + filename) }
        return result
    }

    static func fileURL(_ path: String) throws -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, !parts[1].isEmpty, ![".", ".."].contains(parts[1]), !parts[1].contains("\\") else { throw CocoaError(.fileReadCorruptFile) }
        let base: URL
        switch parts[0] {
        case "images": base = ScheduleMemoImageStore.directoryURL()
        case "attachments": base = ScheduleMemoAttachmentStore.directoryURL()
        case "audio": base = ScheduleMemoAudioStore.directoryURL()
        case "background": base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TimetableBackground")
        default: throw CocoaError(.fileReadCorruptFile)
        }
        return base.appendingPathComponent(parts[1])
    }
    static func fileDigest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func requiredFiles(for value: ICloudSyncValue) throws -> [String] {
        guard !value.deleted else { return [] }
        let decoder = JSONDecoder()
        switch value.key.split(separator: "/").first {
        case "ScheduleMemoImage": return ["images/" + (try decoder.decode(SyncedScheduleMemoImage.self, from: value.payload)).localFilename]
        case "ScheduleMemoAttachment": return ["attachments/" + (try decoder.decode(SyncedScheduleMemoAttachment.self, from: value.payload)).localFilename]
        case "ScheduleMemoAudio": return ["audio/" + (try decoder.decode(SyncedScheduleMemoAudio.self, from: value.payload)).localFilename]
        default:
            if value.key == "preference/" + TimetableBackgroundStore.filenameKey {
                let data = try decoder.decode(Data.self, from: value.payload)
                let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
                if let filename = plist?["value"] as? String, !filename.isEmpty { return ["background/" + filename] }
            }
            return []
        }
    }

    static func apply(_ value: ICloudSyncValue, context: ModelContext) throws {
        if value.key.hasPrefix("file/") { return }
        let decoder = JSONDecoder()
        func models<T: ICloudModelValue>(_ type: T.Type) throws {
            let idString = String(value.key.dropFirst(T.kind.count + 1))
            guard let id = UUID(uuidString: idString) else { throw CocoaError(.fileReadCorruptFile) }
            let all = try context.fetch(FetchDescriptor<T.Model>())
            let matches = all.filter { T($0).id == id }
            if value.deleted {
                for item in matches {
                    let file: LocalFileCleanup.File?
                    switch item {
                    case let image as ScheduleMemoImage: file = LocalFileCleanup.File(image, url: try fileURL("images/" + image.localFilename))
                    case let attachment as ScheduleMemoAttachment: file = LocalFileCleanup.File(attachment, url: try fileURL("attachments/" + attachment.localFilename))
                    case let audio as ScheduleMemoAudio: file = LocalFileCleanup.File(audio, url: try fileURL("audio/" + audio.localFilename))
                    default: file = nil
                    }
                    if let file { try LocalFileCleanup().enqueue([file]) }
                    context.delete(item)
                }
                return
            }
            let dto = try decoder.decode(T.self, from: value.payload)
            guard dto.id == id else { throw CocoaError(.fileReadCorruptFile) }
            if let model = matches.first { dto.apply(to: model) } else { context.insert(dto.make()) }
            for duplicate in matches.dropFirst() { context.delete(duplicate) }
        }
        let kind = String(value.key.split(separator: "/").first ?? "")
        switch kind {
        case "CourseNote": try models(SyncedCourseNote.self)
        case "CourseOccurrenceNote": try models(SyncedCourseOccurrenceNote.self)
        case "CourseReminderSetting": try models(SyncedCourseReminderSetting.self)
        case "TimetableCellReminder": try models(SyncedTimetableCellReminder.self)
        case "ScheduleMemo": try models(SyncedScheduleMemo.self)
        case "ScheduleMemoImage": try models(SyncedScheduleMemoImage.self)
        case "ScheduleMemoAttachment": try models(SyncedScheduleMemoAttachment.self)
        case "ScheduleMemoAudio": try models(SyncedScheduleMemoAudio.self)
        case "school":
            switch value.key {
            case "school/courses":
                let old = try context.fetch(FetchDescriptor<Course>())
                let incoming = value.deleted ? [] : try decoder.decode([SyncedCourse].self, from: value.payload).map { $0.make() }
                try TimetableLocalDataReassociation(oldCourses: old, newCourses: incoming, context: context).apply(to: context)
                for item in old { context.delete(item) }
                for item in incoming { context.insert(item) }
            case "school/grades":
                for item in try context.fetch(FetchDescriptor<Grade>()) { context.delete(item) }
                if !value.deleted { for dto in try decoder.decode([SyncedGrade].self, from: value.payload) { context.insert(dto.make()) } }
            case "school/gradeSupplemental":
                if !value.deleted {
                    let supplemental = try decoder.decode(ICloudGradeSupplemental.self, from: value.payload)
                    SchoolDataCache.saveGradeRankings(supplemental.rankings, notifies: false)
                    if let summary = supplemental.summary { SchoolDataCache.saveGradeCreditSummary(summary, notifies: false) }
                }
            case "school/exams": SchoolDataCache.saveExamSchedule(value.deleted ? [] : try decoder.decode([ExamArrangement].self, from: value.payload))
            default: throw CocoaError(.fileReadCorruptFile)
            }
        case "CustomSchedule":
            let id = String(value.key.dropFirst("CustomSchedule/".count))
            var events = try CustomScheduleStore.loadForSync().filter { $0.id != id }
            if !value.deleted {
                let event = try decoder.decode(CustomScheduleEvent.self, from: value.payload)
                guard event.id == id else { throw CocoaError(.fileReadCorruptFile) }
                events.append(event)
            }
            CustomScheduleStore.save(events)
        case "preference":
            let key = String(value.key.dropFirst("preference/".count))
            guard preferenceKeys.contains(key) else { throw CocoaError(.fileReadCorruptFile) }
            if value.deleted { UserDefaults.standard.removeObject(forKey: key) }
            else {
                let data = try decoder.decode(Data.self, from: value.payload)
                guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any], let setting = plist["value"] else { throw CocoaError(.fileReadCorruptFile) }
                UserDefaults.standard.set(setting, forKey: key)
            }
        case "settings":
            guard value.key == "settings/timetable", !value.deleted else { return }
            try UserTimetableSettingsStore.save(decoder.decode(UserTimetableSettings.self, from: value.payload))
        default: throw CocoaError(.fileReadCorruptFile)
        }
    }

    static func markUnlinkedEdits(in context: ModelContext) throws {
        let courses = try context.fetch(FetchDescriptor<Course>())
        let keys = Set(courses.map(\.stableCourseKey))
        for note in try context.fetch(FetchDescriptor<CourseNote>()) where !note.isUnassociated && !keys.contains(note.courseKey) { note.isUnassociated = true }
        for note in try context.fetch(FetchDescriptor<CourseOccurrenceNote>()) {
            if !note.isUnassociated && !courses.contains(where: { $0.stableCourseKey == note.courseKey && $0.weeks.contains(note.week) }) { note.isUnassociated = true }
        }
        for setting in try context.fetch(FetchDescriptor<CourseReminderSetting>()) where !setting.isUnassociated && !keys.contains(setting.courseKey) { setting.isUnassociated = true }
        if context.hasChanges { try context.save() }
    }

    static func conflictCopy(_ value: ICloudSyncValue, context: ModelContext) throws -> ICloudSyncValue? {
        let decoder = JSONDecoder()
        func copy<T: ICloudModelValue>(_ type: T.Type, transform: (inout T) -> Void = { _ in }) throws -> ICloudSyncValue {
            var dto = try decoder.decode(T.self, from: value.payload)
            // Stable conflict IDs avoid duplicates if interrupted and replayed.
            let digest = ICloudSyncValue.digest(Data((value.key + value.revision).utf8))
            let hex = String(digest.prefix(32))
            let formatted = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20))"
            dto.id = UUID(uuidString: formatted)!
            transform(&dto)
            let copy = ICloudSyncValue(key: T.kind + "/" + dto.id.uuidString.lowercased(), payload: try encode(dto), modifiedAt: Date())
            try apply(copy, context: context)
            return copy
        }
        switch value.key.split(separator: "/").first {
        case "ScheduleMemo": return try copy(SyncedScheduleMemo.self) { $0.title = ($0.title ?? "随记") + "（冲突副本）" }
        case "CourseNote": return try copy(SyncedCourseNote.self) { $0.isUnassociated = true }
        case "CourseOccurrenceNote": return try copy(SyncedCourseOccurrenceNote.self) { $0.isUnassociated = true }
        case "TimetableCellReminder":
            let dto = try decoder.decode(SyncedTimetableCellReminder.self, from: value.payload)
            let model = dto.make()
            guard let start = model.resolvedStartDate else { throw CocoaError(.fileReadCorruptFile) }
            let event = CustomScheduleEvent(id: ICloudSyncValue.digest(Data(value.revision.utf8)),
                title: dto.title + "（冲突副本）", startsAt: start, endsAt: dto.endsAt,
                location: dto.location ?? "", note: dto.note ?? "", minutesBefore: dto.minutesBefore, createdAt: dto.createdAt)
            let result = ICloudSyncValue(key: "CustomSchedule/" + event.id, payload: try encode(event), modifiedAt: Date())
            try apply(result, context: context); return result
        case "CustomSchedule":
            let original = try decoder.decode(CustomScheduleEvent.self, from: value.payload)
            var copy = CustomScheduleEvent(id: ICloudSyncValue.digest(Data(value.revision.utf8)), title: original.title + "（冲突副本）",
                startsAt: original.startsAt, endsAt: original.endsAt, location: original.locationText,
                note: original.noteText, minutesBefore: original.minutesBefore, createdAt: original.createdAt)
            copy.updatedAt = Date()
            let result = ICloudSyncValue(key: "CustomSchedule/" + copy.id, payload: try encode(copy), modifiedAt: Date())
            try apply(result, context: context); return result
        default: return nil
        }
    }

}

import CryptoKit

nonisolated enum ICloudSyncFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { text } else { nil } }
}

nonisolated struct ICloudGradeSupplemental: Codable {
    let rankings: [GradeRankingRecord]
    let summary: GradeCreditSummary?
}
