import Foundation
import SwiftUI

nonisolated enum AppLanguagePreference: String, Sendable {
    case system
    case zhHans = "zh-Hans"
    case enUS = "en-US"

    static let storageKey = "appLanguagePreference"
    static let appGroupIdentifier = "group.com.isaachuo.leafy"
    static let appGroupStorageKey = "leafy.appLanguagePreference"

    static var current: AppLanguagePreference {
        storedValue(UserDefaults.standard.string(forKey: storageKey))
    }

    static func storedValue(_ rawValue: String?) -> AppLanguagePreference {
        AppLanguagePreference(rawValue: rawValue ?? "") ?? .system
    }

    var localeIdentifier: String {
        switch self {
        case .system:
            return Locale.autoupdatingCurrent.identifier
        case .zhHans:
            return "zh-Hans"
        case .enUS:
            return "en-US"
        }
    }

    var locale: Locale {
        switch self {
        case .system:
            return .autoupdatingCurrent
        case .zhHans, .enUS:
            return Locale(identifier: localeIdentifier)
        }
    }

    var resolvedLocalization: AppLanguagePreference {
        switch self {
        case .system:
            let preferredLanguage = Locale.preferredLanguages.first?.lowercased() ?? ""
            return preferredLanguage.hasPrefix("en") ? .enUS : .zhHans
        case .zhHans, .enUS:
            return self
        }
    }

    func title(displayLanguage: AppLanguagePreference) -> String {
        switch self {
        case .system:
            return L10n.text("跟随系统", language: displayLanguage)
        case .zhHans:
            return "简体中文"
        case .enUS:
            return "English"
        }
    }

    func syncToAppGroup(defaults: UserDefaults? = UserDefaults(suiteName: appGroupIdentifier)) {
        defaults?.set(rawValue, forKey: Self.appGroupStorageKey)
    }

    func weekdayTitle(for day: Int) -> String {
        let index = max(0, min(day - 1, 6))
        let keys = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        return L10n.text(keys[index], language: self)
    }
}

private struct LeafyLanguageKey: EnvironmentKey {
    static let defaultValue = AppLanguagePreference.current
}

extension EnvironmentValues {
    var leafyLanguage: AppLanguagePreference {
        get { self[LeafyLanguageKey.self] }
        set { self[LeafyLanguageKey.self] = newValue }
    }
}

nonisolated enum L10n {
    static func text(_ key: String, language: AppLanguagePreference = .current) -> String {
        String(
            localized: String.LocalizationValue(key),
            bundle: .main,
            locale: language.resolvedLocalization.locale
        )
    }

    static func text(_ key: String, language: AppLanguagePreference = .current, _ arguments: CVarArg...) -> String {
        let format = text(key, language: language)
        return String(format: format, locale: language.resolvedLocalization.locale, arguments: arguments)
    }
}
