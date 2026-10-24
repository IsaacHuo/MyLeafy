import Foundation
import SwiftUI
import WidgetKit

struct LeafyWidgetBackground: View {
    let palette: LeafyWidgetPalette

    var body: some View {
        LinearGradient(colors: [palette.surface, palette.surfaceTint],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct LeafyWidgetPalette {
    let surface: Color
    let surfaceTint: Color
    let brand: Color
    let primary: Color
    let secondary: Color
    let tertiary: Color
    let courseAccents: [Color]
    let isFullColor: Bool
    let onAccent: Color

    var rule: Color { primary.opacity(isFullColor ? 0.08 : 0.18) }

    init(theme: LeafyWidgetThemeSnapshot, colorScheme: ColorScheme,
         renderingMode: WidgetRenderingMode = .fullColor) {
        let base = LeafyWidgetThemePalette.baseColor(for: theme)
        let emphasis = LeafyWidgetThemePalette.emphasisColor(for: theme)
        let textBase = Self.mix(base, with: .black, amount: 0.76)
        let secondaryText = Self.mix(base, with: .black, amount: 0.58)
        let tertiaryText = Self.mix(base, with: .black, amount: 0.44)

        isFullColor = renderingMode == .fullColor
        surface = colorScheme == .dark ? Color(white: 0.08) : .white
        surfaceTint = Self.color(Self.mix(base, with: colorScheme == .dark
                ? .black : .white, amount: colorScheme == .dark ? 0.88 : 0.96))
        brand = isFullColor ? Self.color(colorScheme == .dark ? base : emphasis) : .white
        onAccent = isFullColor ? Self.contrastingText(on: colorScheme == .dark ? base : emphasis) : .white
        primary = !isFullColor || colorScheme == .dark ? .white : Self.color(textBase)
        secondary = !isFullColor || colorScheme == .dark ? .white.opacity(0.78) : Self.color(secondaryText)
        tertiary = !isFullColor || colorScheme == .dark ? .white.opacity(0.58) : Self.color(tertiaryText)
        courseAccents = LeafyWidgetThemePalette.courseAccentColors(for: theme).map(Self.color)
    }

    nonisolated private static func contrastingText(on color: LeafyWidgetThemePalette.ColorComponents) -> Color {
        func linear(_ component: Double) -> Double {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(color.normalizedRed)
            + 0.7152 * linear(color.normalizedGreen) + 0.0722 * linear(color.normalizedBlue)
        return luminance > 0.179 ? .black : .white
    }

    nonisolated private static func color(_ components: LeafyWidgetThemePalette.ColorComponents) -> Color {
        Color(
            red: components.normalizedRed,
            green: components.normalizedGreen,
            blue: components.normalizedBlue
        )
    }

    nonisolated private static func mix(
        _ base: LeafyWidgetThemePalette.ColorComponents,
        with target: LeafyWidgetThemePalette.ColorComponents,
        amount: Double
    ) -> LeafyWidgetThemePalette.ColorComponents {
        LeafyWidgetThemePalette.ColorComponents(
            red: base.red + (target.red - base.red) * amount,
            green: base.green + (target.green - base.green) * amount,
            blue: base.blue + (target.blue - base.blue) * amount
        )
    }
}

private extension LeafyWidgetThemePalette.ColorComponents {
    static let black = LeafyWidgetThemePalette.ColorComponents(red: 0, green: 0, blue: 0)
    static let white = LeafyWidgetThemePalette.ColorComponents(red: 255, green: 255, blue: 255)
}
