import Combine
import OSLog
import SwiftUI

@MainActor
final class CommunityBannerViewModel: ObservableObject {
    @Published private(set) var banner: CommunityBanner?

    func load(campusID: String, defaults: UserDefaults = .standard) async {
        do {
            try await CommunityService.shared.ensureAnonymousSession()
            guard let fetched = try await CommunityService.shared.fetchActiveBanner(campusID: campusID),
                  !defaults.bool(forKey: fetched.dismissalKey)
            else {
                banner = nil
                return
            }
            banner = fetched
        } catch {
            banner = nil
            CommunityDiagnostics.log.error(
                "Community banner load failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func dismiss(defaults: UserDefaults = .standard) {
        guard let banner else { return }
        defaults.set(true, forKey: banner.dismissalKey)
        self.banner = nil
    }
}

struct CommunityBannerSlot: View {
    @EnvironmentObject private var appNavigation: AppNavigationCoordinator
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var viewModel = CommunityBannerViewModel()
    @State private var browserItem: CommunityBannerBrowserItem?

    let refreshID: UUID
    let campusID: String
    @Binding var isVisible: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(height: 0)

            if let banner = viewModel.banner {
                CommunityBannerCard(
                    banner: banner,
                    usesVerticalLayout: dynamicTypeSize.isAccessibilitySize,
                    onOpen: { open(banner) },
                    onDismiss: { viewModel.dismiss() }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.2), value: viewModel.banner?.dismissalKey)
        .onChange(of: viewModel.banner?.dismissalKey, initial: true) { _, dismissalKey in
            withAnimation(.easeOut(duration: 0.2)) {
                isVisible = dismissalKey != nil
            }
        }
        .task(id: CommunityBannerLoadID(refreshID: refreshID, campusID: campusID)) {
            await viewModel.load(campusID: campusID)
        }
        .sheet(item: $browserItem) { item in
            LeafyExternalBrowserView(url: item.url)
        }
    }

    private func open(_ banner: CommunityBanner) {
        guard let value = banner.destinationValue else { return }
        switch banner.destinationKind {
        case .none:
            return
        case .communityPost:
            guard let id = UUID(uuidString: value) else { return }
            appNavigation.openCommunityPost(id: id)
        case .httpsURL:
            guard let url = URL(string: value), url.scheme == "https" else { return }
            browserItem = CommunityBannerBrowserItem(url: url)
        case .appRoute:
            switch value {
            case "timetable":
                appNavigation.selectedRootTab = .timetable
            case "community":
                appNavigation.selectedRootTab = .community
            case "schedule_reports":
                appNavigation.openAcademicRoute(.scheduleReports)
            case "custom_schedules":
                appNavigation.openCustomSchedule()
            case "timetable_background":
                appNavigation.openProfileRoute(.timetableBackground)
            case "profile":
                appNavigation.selectedRootTab = .profile
            default:
                CommunityDiagnostics.log.error("Rejected unknown community banner app route")
            }
        }
    }
}

private struct CommunityBannerLoadID: Hashable {
    let refreshID: UUID
    let campusID: String
}

private struct CommunityBannerCard: View {
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let banner: CommunityBanner
    let usesVerticalLayout: Bool
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if usesVerticalLayout {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        bannerImage
                        copy
                    }
                } else {
                    HStack(spacing: AppSpacing.card) {
                        copy
                        bannerImage
                            .frame(width: banner.imageURL == nil ? 0 : 116)
                    }
                }
            }
            .padding(AppSpacing.card)
            .padding(.trailing, 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppTheme.accent(for: themeColorPreference).opacity(0.38),
                                AppTheme.accentSoft(for: themeColorPreference),
                                AppTheme.accent(for: themeColorPreference).opacity(0.22),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                            .stroke(AppTheme.accent(for: themeColorPreference).opacity(0.24), lineWidth: 1)
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
            .onTapGesture {
                if banner.hasDestination {
                    onOpen()
                }
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭运营 Banner")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(banner.title)，\(banner.subtitle)")
        .accessibilityHint(banner.hasDestination ? "轻点查看详情" : "")
        .accessibilityAddTraits(banner.hasDestination ? .isButton : [])
        .accessibilityAction(named: "关闭") {
            onDismiss()
        }
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(banner.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(banner.subtitle)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if banner.hasDestination {
                HStack(spacing: 4) {
                    Text("查看详情")
                    Image(systemName: "chevron.right")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var bannerImage: some View {
        if let imageURL = banner.imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    AppTheme.accent(for: themeColorPreference).opacity(0.08)
                        .overlay {
                            Image(systemName: "leaf.fill")
                                .foregroundStyle(AppTheme.accent(for: themeColorPreference))
                        }
                }
            }
            .frame(maxWidth: usesVerticalLayout ? .infinity : 116)
            .frame(height: usesVerticalLayout ? 120 : 82)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            .accessibilityHidden(true)
        }
    }
}

private struct CommunityBannerBrowserItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
