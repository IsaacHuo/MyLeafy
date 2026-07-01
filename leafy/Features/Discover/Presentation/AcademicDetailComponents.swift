import SwiftUI

enum AcademicDetailChrome {
    static let bottomFloatingReserve: CGFloat = 44
}

struct AcademicDetailScrollContainer<Content: View>: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @State private var initialLayoutRefreshID = UUID()
    @State private var didScheduleInitialLayoutRefresh = false

    private let spacing: CGFloat
    @ViewBuilder private let content: () -> Content

    init(
        spacing: CGFloat = AppSpacing.card,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: spacing) {
                content()
            }
            .leafyAdaptiveContentWidth(maxWidth: 840, horizontalPadding: AppSpacing.page)
            .padding(.top, AppSpacing.compact)
            .padding(.bottom, bottomSpacing)
        }
        .id(initialLayoutRefreshID)
        .background {
            LeafyPageBackground()
        }
        .task {
            guard !didScheduleInitialLayoutRefresh else { return }
            didScheduleInitialLayoutRefresh = true

            await Task.yield()
            refreshInitialLayout()

            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            refreshInitialLayout()
        }
    }

    private var bottomSpacing: CGFloat {
        RootFloatingTabBar.reservedHeight(controlScale: leafyControlScale) + AcademicDetailChrome.bottomFloatingReserve
    }

    private func refreshInitialLayout() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            initialLayoutRefreshID = UUID()
        }
    }
}

struct AcademicDetailCard<Content: View>: View {
    @ViewBuilder private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.card)
            .leafyCardStyle()
    }
}

struct AcademicDetailSectionHeader: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let title: String

    var body: some View {
        Text(L10n.text(title, language: leafyLanguage))
            .leafySubheadline()
            .foregroundStyle(AppTheme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AcademicDetailFooterText: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let text: String

    var body: some View {
        Text(L10n.text(text, language: leafyLanguage))
            .font(.footnote)
            .foregroundStyle(AppTheme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AcademicDetailDivider: View {
    var body: some View {
        Divider()
            .overlay(AppTheme.separator)
    }
}
