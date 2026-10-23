import Foundation
import UIKit
import WidgetKit

@MainActor
enum LeafyAppIconManager {
    static func primaryIconImage(in bundle: Bundle = .main) throws -> UIImage {
        guard let icons = bundle.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String] else {
            throw LeafyAppIconImageError.unavailable
        }
        for name in files.reversed() {
            if let image = UIImage(named: name, in: bundle, compatibleWith: nil) { return image }
        }
        throw LeafyAppIconImageError.unavailable
    }

    static func syncTheme(
        preferenceRaw: String,
        customColorHex: String,
        iconPreferenceRaw: String
    ) {
        let iconPreference = LeafyAppIconAppearancePreference.storedValue(iconPreferenceRaw)

        LeafyWidgetThemeStore.save(preferenceRaw: preferenceRaw, customHex: customColorHex)
        WidgetCenter.shared.reloadTimelines(ofKind: LeafyWidgetConstants.widgetKind)
        applyIconIfNeeded(iconPreference: iconPreference)
    }

    static func applyIconIfNeeded(
        iconPreference: LeafyAppIconAppearancePreference
    ) {
        guard UIApplication.shared.supportsAlternateIcons else { return }

        let iconName = alternateIconName(iconPreference: iconPreference)
        guard UIApplication.shared.alternateIconName != iconName else { return }

        UIApplication.shared.setAlternateIconName(iconName) { error in
            #if DEBUG
                if let error {
                    print("Leafy alternate icon update failed: \(error)")
                }
            #endif
        }
    }

    static func alternateIconName(
        iconPreference: LeafyAppIconAppearancePreference
    ) -> String? {
        let resolvedTheme = iconPreference.themePreferenceRaw

        switch resolvedTheme {
        case .green:
            return nil
        case .tiffanyBlue:
            return "AppIconTiffanyBlue"
        case .candyPink:
            return "AppIconCandyPink"
        case .sunsetApricot:
            return "AppIconSunsetApricot"
        case .irisPurple:
            return "AppIconIrisPurple"
        case .custom:
            return nil
        }
    }
}

private enum LeafyAppIconImageError: LocalizedError {
    case unavailable
    var errorDescription: String? {
        L10n.text("App 图标资源不可用，无法生成分享卡片。")
    }
}

extension LeafyAppIconAppearancePreference {
    func title(language: AppLanguagePreference) -> String {
        L10n.text(title, language: language)
    }
}
