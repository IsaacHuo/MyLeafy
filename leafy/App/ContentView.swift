//
//  ContentView.swift
//  leafy
//
//  Created by IsaacHuo on 2026/4/21.
//

import Foundation
import OSLog
import SwiftUI

struct ContentView: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var appNavigation: AppNavigationCoordinator
    @ObservedObject var communityNotificationBadgeViewModel: CommunityNotificationBadgeViewModel
    @ObservedObject private var communitySessionManager = CommunitySessionManager.shared
    @State private var initialRootTab: RootTab

    init(
        appNavigation: AppNavigationCoordinator,
        communityNotificationBadgeViewModel: CommunityNotificationBadgeViewModel
    ) {
        self.appNavigation = appNavigation
        self.communityNotificationBadgeViewModel = communityNotificationBadgeViewModel
        _initialRootTab = State(initialValue: appNavigation.selectedRootTab)
    }

    private var isCommunityEnabled: Bool {
        ActiveCampusContext.descriptor.supports(.community)
    }

    var body: some View {
        rootShell
            .tint(AppTheme.accent(for: themeColorPreference))
            .environmentObject(appNavigation)
            .onAppear {
                CommunityDiagnostics.log.info("ContentView appeared with selected tab \(String(describing: appNavigation.selectedRootTab), privacy: .public)")
                sanitizeUnavailableRootTab()
            }
            .onChange(of: appNavigation.selectedRootTab) { _, newTab in
                CommunityDiagnostics.log.info("Root tab changed to \(String(describing: newTab), privacy: .public)")
                handleRootTabChange(to: newTab)
            }
            .task {
                CommunityDiagnostics.log.info("ContentView startup task began; communityEnabled=\(isCommunityEnabled, privacy: .public) options=\(CommunityDiagnosticsOptions.summary, privacy: .public)")
                if isCommunityEnabled {
                    await restoreCommunityNotificationBadge()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    if isCommunityEnabled {
                        Task { await restoreCommunityNotificationBadge() }
                    }
                case .background:
                    communityNotificationBadgeViewModel.stop(reset: false)
                default:
                    break
                }
            }
            .onChange(of: communitySessionManager.currentUserID) { _, currentUserID in
                syncCommunityNotificationBadgeSubscription(profileID: currentUserID)
            }
    }

    @ViewBuilder
    private var rootShell: some View {
        if #available(iOS 26.0, *) {
            nativeTabShell
        } else {
            legacyNativeTabShell
        }
    }

    @available(iOS 26.0, *)
    private var nativeTabShell: some View {
        nativeTabView
            .nativeRootTabBarBehavior()
    }

    @available(iOS 26.0, *)
    private var nativeTabView: some View {
        TabView(selection: nativeRootTabSelection) {
            Tab(
                RootTab.timetable.title(language: leafyLanguage),
                systemImage: RootTab.timetable.systemImage,
                value: RootTab.timetable
            ) {
                TimetableView()
                    .rootTabContentReveal(
                        skipsInitialReveal: initialRootTab == .timetable
                    )
            }

            if isCommunityEnabled {
                Tab(
                    RootTab.community.title(language: leafyLanguage),
                    systemImage: RootTab.community.systemImage,
                    value: RootTab.community
                ) {
                    CommunityRootView(
                        notificationBadgeViewModel: communityNotificationBadgeViewModel
                    )
                    .rootTabContentReveal(
                        skipsInitialReveal: initialRootTab == .community
                    )
                }
                .badge(communityNotificationBadgeViewModel.unreadCount)
            }

            Tab(
                RootTab.schedule.title(language: leafyLanguage),
                systemImage: RootTab.schedule.systemImage,
                value: RootTab.schedule
            ) {
                ScheduleRootView()
                    .rootTabContentReveal(
                        skipsInitialReveal: initialRootTab == .schedule
                    )
            }

            Tab(
                RootTab.academics.title(language: leafyLanguage),
                systemImage: RootTab.academics.systemImage,
                value: RootTab.academics
            ) {
                AcademicHubView(selectedTab: $appNavigation.selectedAcademicTab)
                    .onAppear {
                        appNavigation.selectedRootTab = .academics
                    }
                    .rootTabContentReveal(
                        skipsInitialReveal: initialRootTab == .academics
                    )
            }

            Tab(
                RootTab.profile.title(language: leafyLanguage),
                systemImage: RootTab.profile.systemImage,
                value: RootTab.profile
            ) {
                ProfileView()
                    .rootTabContentReveal(
                        skipsInitialReveal: initialRootTab == .profile
                    )
            }
        }
    }

    private var nativeRootTabSelection: Binding<RootTab> {
        Binding(
            get: { appNavigation.selectedRootTab },
            set: { newTab in
                appNavigation.selectedRootTab = newTab
            }
        )
    }

    private var legacyNativeTabShell: some View {
        TabView(selection: $appNavigation.selectedRootTab) {
            TimetableView()
                .rootTabContentReveal(
                    skipsInitialReveal: initialRootTab == .timetable
                )
                .tabItem {
                    Label(RootTab.timetable.title(language: leafyLanguage), systemImage: RootTab.timetable.systemImage)
                }
                .tag(RootTab.timetable)

            if isCommunityEnabled {
                CommunityRootView(
                    notificationBadgeViewModel: communityNotificationBadgeViewModel
                    )
                    .rootTabContentReveal(
                        skipsInitialReveal: initialRootTab == .community
                    )
                    .tabItem {
                        Label(RootTab.community.title(language: leafyLanguage), systemImage: RootTab.community.systemImage)
                    }
                    .badge(communityNotificationBadgeViewModel.unreadCount)
                    .tag(RootTab.community)
            }

            ScheduleRootView()
                .rootTabContentReveal(
                    skipsInitialReveal: initialRootTab == .schedule
                )
                .tabItem {
                    Label(RootTab.schedule.title(language: leafyLanguage), systemImage: RootTab.schedule.systemImage)
                }
                .tag(RootTab.schedule)

            AcademicHubView(selectedTab: $appNavigation.selectedAcademicTab)
                .rootTabContentReveal(
                    skipsInitialReveal: initialRootTab == .academics
                )
                .tabItem {
                    Label(RootTab.academics.title(language: leafyLanguage), systemImage: RootTab.academics.systemImage)
                }
                .tag(RootTab.academics)

            ProfileView()
                .rootTabContentReveal(
                    skipsInitialReveal: initialRootTab == .profile
                )
                .tabItem {
                    Label(RootTab.profile.title(language: leafyLanguage), systemImage: RootTab.profile.systemImage)
                }
                .tag(RootTab.profile)
        }
        .tint(AppTheme.accent(for: themeColorPreference))
    }

    private func handleRootTabChange(to newTab: RootTab) {
        appNavigation.sanitizePublicRootTab(isCommunityEnabled: isCommunityEnabled)
    }

    @MainActor
    private func restoreCommunityNotificationBadge() async {
        guard isCommunityEnabled else {
            communityNotificationBadgeViewModel.stop(reset: true)
            return
        }
        guard !CommunityDiagnosticsOptions.disablesNotifications else {
            CommunityDiagnostics.log.info("Community notification badge restore skipped by diagnostics")
            communityNotificationBadgeViewModel.stop(reset: true)
            return
        }
        communitySessionManager.startBootstrapIfNeeded()
        await communitySessionManager.restoreProfileIfPossible()
        syncCommunityNotificationBadgeSubscription(profileID: communitySessionManager.currentUserID)
        await communityNotificationBadgeViewModel.refresh()
    }

    @MainActor
    private func syncCommunityNotificationBadgeSubscription(profileID: UUID?) {
        guard isCommunityEnabled else {
            communityNotificationBadgeViewModel.stop(reset: true)
            return
        }
        guard !CommunityDiagnosticsOptions.disablesNotifications else {
            communityNotificationBadgeViewModel.stop(reset: true)
            return
        }
        if let profileID {
            communityNotificationBadgeViewModel.start(profileID: profileID)
        } else {
            communityNotificationBadgeViewModel.stop(reset: true)
        }
    }

    @MainActor
    private func sanitizeUnavailableRootTab() {
        let isCustomCampus = ActiveCampusContext.identity?.isCustom == true
        appNavigation.sanitizePublicRootTab(isCommunityEnabled: isCommunityEnabled)
        if !appNavigation.selectedAcademicTab.isVisible(
            isCustomCampus: isCustomCampus,
            isCommunityEnabled: isCommunityEnabled,
            campusID: ActiveCampusContext.descriptor.id
        ) {
            appNavigation.selectedAcademicTab = .cultivation
        }
        if !isCommunityEnabled {
            communityNotificationBadgeViewModel.stop(reset: true)
        }
    }
}

private extension View {
    func rootTabContentReveal(skipsInitialReveal: Bool) -> some View {
        modifier(RootTabContentRevealModifier(skipsInitialReveal: skipsInitialReveal))
    }

    @ViewBuilder
    func nativeRootTabBarBehavior() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.never)
        } else {
            self
        }
    }
}

private struct RootTabContentRevealModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let skipsInitialReveal: Bool
    @State private var hasAppeared = false
    @State private var isRevealed = false

    func body(content: Content) -> some View {
        content
            .opacity(isRevealed ? 1 : 0)
            .onAppear {
                let shouldRevealImmediately =
                    accessibilityReduceMotion || (!hasAppeared && skipsInitialReveal)
                hasAppeared = true
                if shouldRevealImmediately {
                    reset(to: true)
                } else {
                    reveal()
                }
            }
            .onDisappear {
                reset()
            }
            .onChange(of: accessibilityReduceMotion) { _, newValue in
                guard newValue else { return }
                reset(to: true)
            }
    }

    private func reveal() {
        guard !accessibilityReduceMotion else {
            reset(to: true)
            return
        }
        withAnimation(.easeInOut(duration: 0.22)) {
            isRevealed = true
        }
    }

    private func reset(to value: Bool = false) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isRevealed = value
        }
    }
}

#Preview {
    PreviewRoot()
}

private struct PreviewRoot: View {
    @StateObject private var networkManager = ActiveCampusContext.networkManager
    @StateObject private var appNavigation = AppNavigationCoordinator()
    @StateObject private var communityNotificationBadgeViewModel = CommunityNotificationBadgeViewModel()

    var body: some View {
        if networkManager.hasCachedIdentity {
            ContentView(
                appNavigation: appNavigation,
                communityNotificationBadgeViewModel: communityNotificationBadgeViewModel
            )
        } else {
            LoginView()
        }
    }
}
