import SwiftUI

struct FeatureCard<Destination: View>: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyLanguage) private var leafyLanguage

    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination()) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20 * leafyControlScale, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .frame(width: 46 * leafyControlScale, height: 46 * leafyControlScale)
                    .background(AppTheme.softFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppTheme.separator, lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text(title, language: leafyLanguage))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(L10n.text(subtitle, language: leafyLanguage))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 140, alignment: .leading)
            .padding(18)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: UIConstants.cornerRadiusLarge, style: .continuous))
            .shadow(color: UIConstants.floatingShadow(for: .light), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

struct DetailHero: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text(title, language: leafyLanguage))
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text(L10n.text(subtitle, language: leafyLanguage))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct InfoPanel<Content: View>: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L10n.text(title, language: leafyLanguage), systemImage: icon)
                .font(.headline)
            content()
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct PlanBadge: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyLanguage) private var leafyLanguage

    let text: String

    var body: some View {
        Text(L10n.text(text, language: leafyLanguage))
            .microCaption()
            .fontWeight(.semibold)
            .padding(.horizontal, 8 * leafyControlScale)
            .padding(.vertical, 4 * leafyControlScale)
            .background(AppTheme.softFill, in: Capsule())
    }
}
