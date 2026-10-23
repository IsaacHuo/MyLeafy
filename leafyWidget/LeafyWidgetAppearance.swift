import SwiftUI

struct LeafyWidgetBackground: View {
    let palette: LeafyWidgetPalette

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    palette.surface,
                    palette.brand.opacity(0.10),
                    palette.brand.opacity(0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    palette.surface.opacity(0.58),
                    palette.brand.opacity(0.15)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

struct LeafyWidgetPalette {
    let surface: Color
    let brand: Color
    let primary: Color
    let secondary: Color
    let tertiary: Color
    let courseAccents: [Color]

    init(theme: LeafyWidgetThemeSnapshot, colorScheme: ColorScheme) {
        let base = LeafyWidgetThemePalette.baseColor(for: theme)
        let emphasis = LeafyWidgetThemePalette.emphasisColor(for: theme)
        let textBase = Self.mix(base, with: .black, amount: 0.76)
        let secondaryText = Self.mix(base, with: .black, amount: 0.58)
        let tertiaryText = Self.mix(base, with: .black, amount: 0.44)

        surface = colorScheme == .dark ? Color(white: 0.08) : .white
        brand = Self.color(colorScheme == .dark ? base : emphasis)
        primary = colorScheme == .dark ? .white : Self.color(textBase)
        secondary = colorScheme == .dark ? .white.opacity(0.78) : Self.color(secondaryText)
        tertiary = colorScheme == .dark ? .white.opacity(0.58) : Self.color(tertiaryText)
        courseAccents = LeafyWidgetThemePalette.courseAccentColors(for: theme).map(Self.color)
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
}
