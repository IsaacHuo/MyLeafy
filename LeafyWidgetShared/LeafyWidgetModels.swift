import Foundation
import os

nonisolated enum LeafyWidgetConstants {
    static let appGroupIdentifier = "group.com.isaachuo.leafy"
    static let snapshotFilename = "leafy-widget-snapshot.json"
    static let snapshotArchiveFilename = "leafy-widget-snapshots.json"
    static let widgetKind = "LeafyTimetableWidget"
    static let selectedDayOffsetKey = "leafyWidget.selectedDayOffset"
    static let themeSnapshotKey = "leafyWidget.themeSnapshot"
    static let themePreferenceKey = "leafyWidget.themePreference"
    static let themeCustomColorHexKey = "leafyWidget.themeCustomColorHex"
    static let appLanguagePreferenceKey = "leafy.appLanguagePreference"
    static let supportedDayOffsets = [0, 1]
}

nonisolated enum LeafyWidgetLanguagePreference: String, Sendable {
    case system
    case zhHans = "zh-Hans"
    case enUS = "en-US"

    static var current: LeafyWidgetLanguagePreference {
        let rawValue = UserDefaults(suiteName: LeafyWidgetConstants.appGroupIdentifier)?
            .string(forKey: LeafyWidgetConstants.appLanguagePreferenceKey)
        return LeafyWidgetLanguagePreference(rawValue: rawValue ?? "") ?? .system
    }

    var locale: Locale {
        switch self {
        case .system:
            return .autoupdatingCurrent
        case .zhHans:
            return Locale(identifier: "zh-Hans")
        case .enUS:
            return Locale(identifier: "en-US")
        }
    }

    var localizationIdentifier: String {
        switch self {
        case .system:
            let preferredLanguage = Locale.preferredLanguages.first?.lowercased() ?? ""
            return preferredLanguage.hasPrefix("en") ? "en-US" : "zh-Hans"
        case .zhHans:
            return "zh-Hans"
        case .enUS:
            return "en-US"
        }
    }
}

nonisolated enum LeafyWidgetL10n {
    static func text(_ key: String) -> String {
        String(
            localized: String.LocalizationValue(key),
            bundle: .main,
            locale: LeafyWidgetLanguagePreference.current.locale
        )
    }

    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: LeafyWidgetLanguagePreference.current.locale, arguments: arguments)
    }
}

nonisolated enum LeafyWidgetRoute: Equatable {
    case timetable
    case course(id: UUID)
    case timetableSharing
    case cacheSync
    case scheduleReports
    case schedules

    private static let scheme = "leafy"

    /// Non-optional fallback used when `URLComponents` fails to produce a URL.
    /// Built from compile-time constants and validated once here, so the hot path
    /// below never needs an inline force-unwrap.
    private static let fallbackURL: URL = {
        guard let url = URL(string: "\(scheme)://timetable") else {
            preconditionFailure("Invalid LeafyWidgetRoute fallback URL for scheme: \(scheme)")
        }
        return url
    }()

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme

        switch self {
        case .timetable:
            components.host = "timetable"
        case .course(let id):
            components.host = "course"
            components.queryItems = [
                URLQueryItem(name: "id", value: id.uuidString)
            ]
        case .timetableSharing:
            components.host = "timetable-sharing"
        case .cacheSync:
            components.host = "cache-sync"
        case .scheduleReports:
            components.host = "schedule-reports"
        case .schedules:
            components.host = "schedules"
        }

        return components.url ?? Self.fallbackURL
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }

        switch url.host {
        case "timetable":
            self = .timetable
        case "course":
            let idValue = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "id" })?
                .value
            guard let idValue, let id = UUID(uuidString: idValue) else { return nil }
            self = .course(id: id)
        case "timetable-sharing":
            self = .timetableSharing
        case "cache-sync":
            self = .cacheSync
        case "schedule-reports":
            self = .scheduleReports
        case "schedules":
            self = .schedules
        default:
            return nil
        }
    }
}

nonisolated enum LeafyWidgetSnapshotStore {
    private static let logger = Logger(subsystem: "com.isaachuo.leafy", category: "WidgetSnapshotStore")
    static var selectedDayOffset: Int {
        normalizedDayOffset(appGroupDefaults.integer(forKey: LeafyWidgetConstants.selectedDayOffsetKey))
    }

    static func normalizedDayOffset(_ dayOffset: Int) -> Int {
        LeafyWidgetConstants.supportedDayOffsets.contains(dayOffset) ? dayOffset : 0
    }

    static func setSelectedDayOffset(_ dayOffset: Int) {
        appGroupDefaults.set(
            normalizedDayOffset(dayOffset),
            forKey: LeafyWidgetConstants.selectedDayOffsetKey
        )
    }

    static func alternateDayOffset(for dayOffset: Int) -> Int {
        normalizedDayOffset(dayOffset) == 0 ? 1 : 0
    }

    static func loadArchive() -> LeafyWidgetSnapshotArchive? {
        guard let data = try? Data(contentsOf: snapshotArchiveURL),
              let archive = try? JSONDecoder.leafyWidget.decode(LeafyWidgetSnapshotArchive.self, from: data),
              archive.schemaVersion == LeafyWidgetSnapshotArchive.currentSchemaVersion else {
            return nil
        }
        return archive
    }

    @discardableResult
    static func save(_ archive: LeafyWidgetSnapshotArchive) -> Bool {
        do {
            let directory = snapshotArchiveURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder.leafyWidget.encode(archive)
            try data.write(to: snapshotArchiveURL, options: [.atomic])

            return true
        } catch {
            logger.error("Widget snapshot save failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: snapshotURL)
        try? FileManager.default.removeItem(at: snapshotArchiveURL)
    }

    private static var snapshotArchiveURL: URL {
        containerURL.appendingPathComponent(LeafyWidgetConstants.snapshotArchiveFilename)
    }

    private static var snapshotURL: URL {
        containerURL.appendingPathComponent(LeafyWidgetConstants.snapshotFilename)
    }

    private static var containerURL: URL {
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: LeafyWidgetConstants.appGroupIdentifier
        ) {
            return container
        }
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("LeafyWidget", isDirectory: true)
    }

    private static var appGroupDefaults: UserDefaults {
        UserDefaults(suiteName: LeafyWidgetConstants.appGroupIdentifier) ?? .standard
    }
}

nonisolated private extension JSONDecoder {
    static var leafyWidget: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

nonisolated private extension JSONEncoder {
    static var leafyWidget: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
