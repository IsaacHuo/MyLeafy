import SwiftUI

struct CampusRootView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference
    @EnvironmentObject private var appNavigation: AppNavigationCoordinator
    @ObservedObject var notificationBadgeViewModel: CommunityNotificationBadgeViewModel
    @State private var visitedSections: Set<CampusSection> = []

    private var isCommunityEnabled: Bool {
        ActiveCampusContext.descriptor.supports(.community)
    }

    private var destinations: [CampusSidebarDestination] {
        CampusSidebarDestination.visibleCases(
            isCustomCampus: ActiveCampusContext.identity?.isCustom == true,
            isCommunityEnabled: isCommunityEnabled,
            isMedicalEnabled: ActiveCampusContext.descriptor.supports(.medicalServices),
            campusID: ActiveCampusContext.descriptor.id
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            sidebar

            ZStack {
                retainedPane(.schedule) {
                    ScheduleRootView()
                }
                if isCommunityEnabled {
                    retainedPane(.community) {
                        CommunityRootView(notificationBadgeViewModel: notificationBadgeViewModel)
                    }
                }
                retainedPane(.academics) {
                    AcademicHubView(selectedTab: $appNavigation.selectedAcademicTab)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(LeafyPageBackground())
        .onChange(of: appNavigation.selectedCampusSection, initial: true) { _, section in
            visitedSections.insert(section)
        }
    }

    @ViewBuilder
    private func retainedPane<Content: View>(
        _ section: CampusSection,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if visitedSections.contains(section) || appNavigation.selectedCampusSection == section {
            let isSelected = appNavigation.selectedCampusSection == section
            let isActive = isSelected && appNavigation.selectedRootTab == .academics
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(isSelected ? 1 : 0)
                .allowsHitTesting(isActive)
                .disabled(!isActive)
                .accessibilityHidden(!isActive)
                .zIndex(isSelected ? 1 : 0)
        }
    }

    private var sidebar: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 4 * leafyControlScale) {
                ForEach(destinations) { destination in
                    let isSelected = isSelected(destination)
                    let unreadCount = destination == .community ? notificationBadgeViewModel.unreadCount : 0
                    Button {
                        select(destination)
                    } label: {
                        CampusSidebarTabItem(
                            title: destination.title(language: leafyLanguage),
                            icon: destination.icon,
                            isSelected: isSelected,
                            themeColorPreference: themeColorPreference,
                            unreadCount: unreadCount
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(destination.title(language: leafyLanguage))
                    .accessibilityValue(unreadCount > 0
                        ? L10n.text("%d 条未读通知", language: leafyLanguage, unreadCount) : "")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(8 * leafyControlScale)
            .leafyGlassSurface(
                in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous),
                fallbackFill: Color(uiColor: .systemBackground).opacity(0.9)
            )
        }
        .frame(width: min(max(74 * leafyControlScale, 72), 92), alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, -(AppSpacing.micro / 15))
        .accessibilityElement(children: .contain)
    }

    private func isSelected(_ destination: CampusSidebarDestination) -> Bool {
        guard appNavigation.selectedCampusSection == destination.section else { return false }
        if case .academic(let tab) = destination {
            return appNavigation.selectedAcademicTab == tab
        }
        return true
    }

    private func select(_ destination: CampusSidebarDestination) {
        let update = {
            if case .academic(let tab) = destination {
                self.appNavigation.selectedAcademicTab = tab
            }
            self.appNavigation.selectedCampusSection = destination.section
        }
        if accessibilityReduceMotion {
            update()
        } else {
            withAnimation(.easeInOut(duration: 0.22), update)
        }
    }
}

private struct CampusSidebarTabItem: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    let title: String
    let icon: String
    let isSelected: Bool
    let themeColorPreference: AppThemeColorPreference
    let unreadCount: Int

    var body: some View {
        VStack(spacing: 4 * leafyControlScale) {
            Image(systemName: icon)
                .font(.system(size: 14 * leafyControlScale, weight: .semibold))
                .foregroundStyle(isSelected
                    ? AppTheme.textOnAccent(for: themeColorPreference)
                    : AppTheme.accent(for: themeColorPreference))
                .frame(width: 28 * leafyControlScale, height: 28 * leafyControlScale)
                .background(isSelected
                    ? AppTheme.accent(for: themeColorPreference)
                    : AppTheme.accent(for: themeColorPreference).opacity(0.12), in: Circle())
                .overlay(alignment: .topTrailing) {
                    if unreadCount > 0 {
                        Text(unreadCount > 99 ? "99+" : String(unreadCount))
                            .font(.system(size: 9 * leafyControlScale, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 15, minHeight: 15)
                            .background(.red, in: Capsule())
                            .offset(x: 8, y: -4)
                            .accessibilityHidden(true)
                    }
                }

            Text(title)
                .font(.system(size: 11.5 * leafyControlScale, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 54 * leafyControlScale)
        .background(isSelected ? AppTheme.accent(for: themeColorPreference).opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
    }
}
