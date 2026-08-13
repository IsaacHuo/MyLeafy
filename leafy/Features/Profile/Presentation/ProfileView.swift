import Foundation
import OSLog
import PhotosUI
import Photos
import SafariServices
import StoreKit
import SwiftData
import SwiftUI
import UIKit

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyLanguage) private var leafyLanguage
    @EnvironmentObject private var appNavigation: AppNavigationCoordinator
    @AppStorage(AppThemeColorPreference.storageKey) private var appThemeColorPreferenceRaw = AppThemeColorPreference.green.rawValue
    @AppStorage(AppThemeColorPreference.customColorHexKey) private var appThemeCustomColorHex = AppThemeColorPreference.defaultCustomColorHex
    @AppStorage(AppAppearancePreference.storageKey) private var appAppearancePreferenceRaw = AppAppearancePreference.light.rawValue
    @AppStorage("timetableHidesWeekends") private var timetableHidesWeekends = false
    @AppStorage(TimetableBackgroundStore.isEnabledKey) private var timetableBackgroundIsEnabled = false
    @AppStorage(TimetableBackgroundStore.kindKey) private var timetableBackgroundKindRaw = TimetableBackgroundKind.photo.rawValue
    @AppStorage(TimetableBackgroundStore.filenameKey) private var timetableBackgroundFilename = ""

    @ObservedObject private var sessionManager = CommunitySessionManager.shared
    @State private var showingLogoutAlert = false
    @State private var showingDeleteAccountConfirmation = false
    @State private var showingFinalDeleteAccountConfirmation = false
    @State private var isDeletingAccount = false
    @State private var accountDeletionError: String?
    @State private var showingFeedbackSheet = false
    @State private var feedbackInitialIssueType = "问题反馈"
    @State private var feedbackInitialBody = ""
    @State private var isCheckingForUpdate = false
    @State private var isOpeningReviewPage = false
    @State private var updateCheckMessage: String?
    @State private var reviewPageMessage: String?
    @State private var navigationPath = NavigationPath()
    @State private var pendingTimetableInviteCode: String?
    @State private var showingPoemeryOverlay = false

    private let profileRowIconSize: CGFloat = 34

    private var themeColorPreference: AppThemeColorPreference {
        AppThemeColorPreference.storedValue(appThemeColorPreferenceRaw)
    }

    private var isCommunityEnabled: Bool {
        ActiveCampusContext.descriptor.supports(.community)
    }

    private var isCustomCampus: Bool {
        ActiveCampusContext.identity?.isCustom == true
    }

    private var isReviewDemoAccount: Bool {
        ReviewDemoMode.isEnabled ||
            ReviewDemoDataSeeder.isDemoEduID(ActiveCampusContext.networkManager.authenticatedEduID)
    }

    private var canDeleteAccount: Bool {
        AppAccountDeletionPolicy.canDelete(
            isReviewDemoMode: ReviewDemoMode.isEnabled,
            eduID: ActiveCampusContext.networkManager.authenticatedEduID
        )
    }

    private var profileDisplayName: String {
        if !isCommunityEnabled {
            let displayName = ActiveCampusContext.identity?.displayName?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return displayName.isEmpty ? L10n.text("自定义账号", language: leafyLanguage) : displayName
        }
        return sessionManager.profile?.limitedResolvedDisplayName ?? L10n.text("社区资料", language: leafyLanguage)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            profileSettingsList
            .background(LeafyPageBackground())
            .tint(themeColorPreference.swatchColor)
            .navigationDestination(for: ProfileRoute.self) { route in
                switch route {
                case .timetableSharing:
                    if isCommunityEnabled {
                        TimetableSharingView(initialInviteCode: pendingTimetableInviteCode)
                    } else {
                        ContentUnavailableView("当前入口暂不支持共享课表", systemImage: "person.2.slash")
                    }
                case .cacheSync:
                    CacheAndSyncView()
                case .timetableBackground:
                    TimetableBackgroundSettingsView()
                }
            }
            .onChange(of: appNavigation.requestedProfileRoute) { _, route in
                handleProfileRouteRequest(route)
            }
            .leafySheet(isPresented: $showingFeedbackSheet) {
                FeedbackSheetView(
                    initialIssueType: feedbackInitialIssueType,
                    initialBody: feedbackInitialBody
                )
                    .presentationDetents([.medium, .large])
            }
            .appStoreOverlay(isPresented: $showingPoemeryOverlay) {
                SKOverlay.AppConfiguration(
                    appIdentifier: "6773236818",
                    position: .bottom
                )
            }
            .alert(logoutConfirmationTitle, isPresented: $showingLogoutAlert) {
                Button(logoutButtonTitle, role: .destructive) {
                    AppSessionResetter.returnToLogin(modelContext: modelContext)
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text(logoutConfirmationMessage)
            }
            .confirmationDialog(
                "删除 MyLeafy 账户？",
                isPresented: $showingDeleteAccountConfirmation,
                titleVisibility: .visible
            ) {
                Button("继续删除", role: .destructive) {
                    showingFinalDeleteAccountConfirmation = true
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("这会永久删除社区资料、帖子、评论、互动和私有媒体，并清除当前设备上的课表、成绩、草稿、学习资料和其他 MyLeafy 数据。此操作不会删除或修改北京林业大学官方教务账户。")
            }
            .alert("最终确认删除？", isPresented: $showingFinalDeleteAccountConfirmation) {
                Button("永久删除账户", role: .destructive) {
                    Task { await deleteAccount() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("删除后无法恢复。完成后 App 会清除本机数据并返回登录页。")
            }
            .alert("账户删除失败", isPresented: Binding(
                get: { accountDeletionError != nil },
                set: { if !$0 { accountDeletionError = nil } }
            )) {
                Button("重试", role: .destructive) {
                    Task { await deleteAccount() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text(accountDeletionError ?? "")
            }
            .alert("检查更新", isPresented: Binding(
                get: { updateCheckMessage != nil },
                set: { if !$0 { updateCheckMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(updateCheckMessage ?? "")
            }
            .alert("给 \(AppBrand.displayName) 评分", isPresented: Binding(
                get: { reviewPageMessage != nil },
                set: { if !$0 { reviewPageMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(reviewPageMessage ?? "")
            }
            .task {
                if isCommunityEnabled {
                    sessionManager.startBootstrapIfNeeded()
                } else {
                    sessionManager.cancelInFlightWork()
                }
            }
            .onAppear {
                handleProfileRouteRequest(appNavigation.requestedProfileRoute)
            }
        }
    }

    private var profileSettingsList: some View {
        List {
            Section {
                profileHeaderRow
            } header: {
                Text("资料")
            }
            .listRowBackground(AppTheme.cardBackground)

            Section {
                settingsRows
            } header: {
                Text("课表与偏好")
            }

            Section("帮助与资源") {
                helpAndResourcesRows
            }
            .listRowBackground(AppTheme.cardBackground)

            Section("关于 MyLeafy") {
                aboutRows
            }
            .listRowBackground(AppTheme.cardBackground)

            Section("我的更多作品") {
                moreWorksRows
            }
            .listRowBackground(AppTheme.cardBackground)

            Section {
                accountRows
            } header: {
                Text("账户")
            } footer: {
                if isReviewDemoAccount, !canDeleteAccount {
                    Text("此共享演示账户受保护，不能删除。退出演示模式不会影响正式账户与数据。")
                }
            }
            .listRowBackground(AppTheme.cardBackground)
        }
        .leafyInsetGroupedListStyle()
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .safeAreaPadding(.bottom, AppSpacing.compact)
        .frame(maxWidth: 760, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var settingsRows: some View {
        NavigationLink {
            CacheAndSyncView()
        } label: {
            profileRow(
                icon: "arrow.triangle.2.circlepath",
                title: "重新同步",
                detail: isCustomCampus ? "检查本地数据状态" : "重新同步教务数据"
            )
        }

        if isCommunityEnabled {
            NavigationLink {
                TimetableSharingView()
            } label: {
                profileRow(icon: "person.2.fill", title: "共享课表", detail: "邀请同学查看")
            }
        }

        NavigationLink {
            PersonalizationSettingsView()
        } label: {
            profileRow(icon: "paintpalette.fill", title: "个性化", detail: personalizationDetail)
        }

        NavigationLink {
            TimetableBackgroundSettingsView()
        } label: {
            profileRow(icon: "rectangle.3.group.fill", title: "课表背景", detail: timetableBackgroundDetail)
        }

        Toggle(isOn: $timetableHidesWeekends) {
            HStack(spacing: 12) {
                LeafyCompactProfileIconBadge(systemName: "calendar.badge.minus", size: profileRowIconSize)

                VStack(alignment: .leading, spacing: 2) {
                    Text("隐藏周末")
                        .leafyBody()
                        .foregroundStyle(AppTheme.primaryText)
                    Text("课表页仅显示周一至周五")
                        .microCaption()
                        .foregroundStyle(AppTheme.tertiaryText)
                }
            }
        }
        .tint(AppTheme.accent)
    }

    @ViewBuilder
    private var helpAndResourcesRows: some View {
        NavigationLink {
            LeafyGuideAndDataSecurityView()
        } label: {
            profileRow(
                icon: "questionmark.circle.fill",
                title: "帮助中心",
                detail: "使用指南、常见问题与数据安全"
            )
        }

        Button {
            feedbackInitialIssueType = "问题反馈"
            feedbackInitialBody = ""
            showingFeedbackSheet = true
        } label: {
            profileRow(
                icon: "bubble.left.and.bubble.right.fill",
                title: "反馈与举报",
                detail: "功能建议、问题反馈与内容举报",
                showsDisclosure: true
            )
        }

        if !isCustomCampus {
            NavigationLink {
                CampusLinksView()
            } label: {
                profileRow(icon: "building.columns.fill", title: "常用链接", detail: "教务系统等常用网站")
            }
        }
    }

    @ViewBuilder
    private var aboutRows: some View {
        Button {
            Task { await checkForUpdate() }
        } label: {
            profileRow(
                icon: "arrow.down.circle.fill",
                title: "检查更新",
                detail: isCheckingForUpdate ? "检查中" : "跳转到 App Store",
                showsDisclosure: true
            )
        }
        .disabled(isCheckingForUpdate)

        Button {
            Task { await openReviewPage() }
        } label: {
            profileRow(
                icon: "star.bubble.fill",
                title: "给 \(AppBrand.displayName) 评分",
                detail: isOpeningReviewPage ? "打开中" : "前往 App Store",
                showsDisclosure: true
            )
        }
        .disabled(isOpeningReviewPage)

        NavigationLink {
            AboutMyLeafyView()
        } label: {
            profileRow(icon: "info.circle.fill", title: "了解 MyLeafy", detail: "简介与设计理念")
        }
    }

    private var moreWorksRows: some View {
        Button {
            showingPoemeryOverlay = true
        } label: {
            poemeryPromotionRow
        }
    }

    @ViewBuilder
    private var accountRows: some View {
        if isCommunityEnabled, !isCustomCampus, ActiveCampusContext.descriptor.id == .bjfu {
            NavigationLink("绑定邮箱") {
                ProfileEmailBindingView()
            }
        }

        logoutButton

        if canDeleteAccount {
            deleteAccountButton
        }
    }

    private var logoutButton: some View {
        Button(logoutButtonTitle, role: .destructive) {
            showingLogoutAlert = true
        }
    }

    private var deleteAccountButton: some View {
        Button(
            isDeletingAccount ? "正在删除账户…" : "删除 MyLeafy 账户",
            role: .destructive
        ) {
            showingDeleteAccountConfirmation = true
        }
        .disabled(isDeletingAccount)
        .accessibilityHint("永久删除社区账户和当前设备上的 MyLeafy 数据")
        .accessibilityIdentifier("profile.delete-account")
    }

    private var logoutButtonTitle: String {
        isReviewDemoAccount ? "退出演示模式" : "退出登录"
    }

    private var logoutConfirmationTitle: String {
        isReviewDemoAccount ? "退出演示模式？" : "确认退出？"
    }

    private var logoutConfirmationMessage: String {
        if isReviewDemoAccount {
            return "退出后会返回登录页，正式账户与数据不会受到影响。"
        }
        return "退出后需重新登录，本地缓存的课表和成绩数据将保留。"
    }

    @MainActor
    private func deleteAccount() async {
        guard canDeleteAccount, !isDeletingAccount else {
            return
        }
        isDeletingAccount = true
        defer { isDeletingAccount = false }

        do {
            let localCleanupError = try await AppAccountDeletionCoordinator.delete {
                try await sessionManager.deleteCurrentAccount()
            } locally: {
                try AppSessionResetter.deleteAllUserData(modelContext: modelContext)
            }
            if let localCleanupError {
                CommunityDiagnostics.log.error(
                    "Remote account deletion succeeded but local cleanup failed: \(localCleanupError.localizedDescription, privacy: .public)"
                )
                appNavigation.completeAccountDeletion(
                    with: .deletedWithLocalCleanupWarning(localCleanupError.localizedDescription)
                )
                AppSessionResetter.returnToLogin()
            } else {
                appNavigation.completeAccountDeletion(with: .deleted)
            }
        } catch {
            accountDeletionError = error.localizedDescription
        }
    }

    private func handleProfileRouteRequest(_ route: ProfileRoute?) {
        guard let route else { return }
        if route == .timetableSharing, !isCommunityEnabled {
            appNavigation.requestedProfileRoute = nil
            appNavigation.requestedTimetableInviteCode = nil
            return
        }
        if route == .timetableSharing {
            pendingTimetableInviteCode = appNavigation.requestedTimetableInviteCode
            appNavigation.requestedTimetableInviteCode = nil
        }
        navigationPath.append(route)
        appNavigation.requestedProfileRoute = nil
    }

    private var personalizationDetail: String {
        let themeTitle = themeColorPreference.title(language: leafyLanguage)
        let appearanceTitle = AppAppearancePreference.storedValue(appAppearancePreferenceRaw).title(language: leafyLanguage)
        return "\(themeTitle) · \(appearanceTitle)"
    }

    private var timetableBackgroundDetail: String {
        guard timetableBackgroundIsEnabled,
              let kind = TimetableBackgroundKind(rawValue: timetableBackgroundKindRaw) else {
            return L10n.text("已关闭", language: leafyLanguage)
        }
        switch kind {
        case .photo:
            guard !timetableBackgroundFilename.isEmpty else {
                return L10n.text("等待选择照片", language: leafyLanguage)
            }
            return L10n.text("照片", language: leafyLanguage)
        case .solid:
            return L10n.text("纯色", language: leafyLanguage)
        }
    }

    private var profileSubtitle: String {
        profileSubtitleLines.joined(separator: "\n")
    }

    private var profileSubtitleLines: [String] {
        guard isCommunityEnabled else {
            return [L10n.text("当前入口账号。学校相关数据保存在本机。", language: leafyLanguage)]
        }

        if let bootstrapError = sessionManager.bootstrapError, sessionManager.profile == nil {
            return [bootstrapError]
        }

        guard let profile = sessionManager.profile else {
            return [L10n.text("社区资料会和教务学号绑定，首次发帖或点赞前需要先完善昵称。头像、学院和年级可选。", language: leafyLanguage)]
        }

        if sessionManager.requiresProfileCompletion {
            return [L10n.text("学号 %@ 已绑定，请先补全昵称。头像、学院和年级可选，未设置头像会使用默认头像。", language: leafyLanguage, profile.eduID)]
        }

        let parts = [profile.grade, profile.major]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let firstLine = parts.isEmpty
            ? L10n.text("已与教务绑定", language: leafyLanguage)
            : parts.joined(separator: " · ")
        return [
            firstLine,
            L10n.text("学号 %@", language: leafyLanguage, profile.eduID)
        ]
    }

    @ViewBuilder
    private var profileHeaderRow: some View {
        if isCommunityEnabled {
            NavigationLink {
                CommunityUserProfileView(
                    profileID: sessionManager.currentUserID,
                    initialProfile: sessionManager.profile,
                    allowsEditing: true
                )
            } label: {
                HStack(spacing: 16) {
                    CommunityAvatarView(profile: sessionManager.profile, size: 80 * leafyControlScale)
                    profileHeaderText
                    Spacer()
                }
                .padding(.vertical, 6 * leafyControlScale)
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(AppTheme.softFill)
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 48 * leafyControlScale, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                .frame(width: 80 * leafyControlScale, height: 80 * leafyControlScale)

                profileHeaderText
                Spacer()
            }
            .padding(.vertical, 6 * leafyControlScale)
        }
    }

    private var profileHeaderText: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(profileDisplayName)
                .title2()
                .foregroundStyle(AppTheme.primaryText)

            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(profileSubtitleLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .leafyBody()
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private func profileRow(
        icon: String,
        title: String,
        detail: String,
        tint: Color = AppTheme.accent,
        showsDisclosure: Bool = false
    ) -> some View {
        HStack(alignment: .center, spacing: 11) {
            LeafyCompactProfileIconBadge(systemName: icon, tint: tint, size: profileRowIconSize)

            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.text(title, language: leafyLanguage))
                    .leafyBody()
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(L10n.text(detail, language: leafyLanguage))
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsDisclosure {
                LeafyDisclosureIndicator()
            }
        }
        .padding(.vertical, 1)
    }

    private var poemeryPromotionRow: some View {
        HStack(alignment: .center, spacing: 11) {
            Image("PoemeryAppIcon")
                .resizable()
                .scaledToFill()
                .frame(width: profileRowIconSize, height: profileRowIconSize)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: profileRowIconSize * 0.22,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: profileRowIconSize * 0.22,
                        style: .continuous
                    )
                    .stroke(AppTheme.separator, lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text("诗境 Poemery")
                    .leafyBody()
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)

                Text("离线阅读中文古典诗词")
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            LeafyDisclosureIndicator()
        }
        .padding(.vertical, 1)
    }

    @MainActor
    private func checkForUpdate() async {
        guard !isCheckingForUpdate else { return }
        guard let bundleIdentifier = Bundle.main.bundleIdentifier, !bundleIdentifier.isEmpty else {
            updateCheckMessage = L10n.text("暂未找到 App Store 页面，请稍后再试。", language: leafyLanguage)
            return
        }

        isCheckingForUpdate = true
        defer { isCheckingForUpdate = false }

        do {
            guard let appStoreURL = try await AppStoreUpdateLookup.appStoreURL(bundleIdentifier: bundleIdentifier) else {
                updateCheckMessage = L10n.text("暂未找到 App Store 页面，请稍后再试。", language: leafyLanguage)
                return
            }

            openURL(appStoreURL)
        } catch {
            updateCheckMessage = L10n.text("暂未找到 App Store 页面，请稍后再试。", language: leafyLanguage)
        }
    }

    @MainActor
    private func openReviewPage() async {
        guard !isOpeningReviewPage else { return }
        guard let bundleIdentifier = Bundle.main.bundleIdentifier, !bundleIdentifier.isEmpty else {
            reviewPageMessage = L10n.text("暂未找到 App Store 评分页面，请稍后再试。", language: leafyLanguage)
            return
        }

        isOpeningReviewPage = true
        defer { isOpeningReviewPage = false }

        do {
            guard let appStoreURL = try await AppStoreUpdateLookup.appStoreURL(bundleIdentifier: bundleIdentifier) else {
                reviewPageMessage = L10n.text("暂未找到 App Store 评分页面，请稍后再试。", language: leafyLanguage)
                return
            }

            openURL(AppStoreUpdateLookup.reviewURL(from: appStoreURL))
        } catch {
            reviewPageMessage = L10n.text("暂未找到 App Store 评分页面，请稍后再试。", language: leafyLanguage)
        }
    }
}

private struct AboutMyLeafyView: View {
    @State private var browserItem: ProfileBrowserItem?

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        List {
            Section("项目") {
                Button {
                    browserItem = ProfileBrowserItem(url: LeafyExternalLinks.authorBlog)
                } label: {
                    externalLinkRow(
                        icon: "doc.text.fill",
                        title: "项目介绍",
                        detail: "了解产品定位与设计"
                    )
                }

                Button {
                    browserItem = ProfileBrowserItem(url: LeafyExternalLinks.githubRepository)
                } label: {
                    externalLinkRow(
                        icon: "chevron.left.forwardslash.chevron.right",
                        title: "GitHub",
                        detail: "查看开源项目"
                    )
                }
            }
            .listRowBackground(AppTheme.cardBackground)

            Section("版本") {
                LabeledContent("当前版本", value: "Version \(version)")
            }
            .listRowBackground(AppTheme.cardBackground)
        }
        .leafyInsetGroupedListStyle()
        .scrollContentBackground(.hidden)
        .background(LeafyPageBackground())
        .navigationTitle("关于 MyLeafy")
        .leafyInlineNavigationTitle()
        .sheet(item: $browserItem) { item in
            ProfileSafariView(url: item.url)
        }
    }

    private func aboutTextRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .leafyBody()
                .foregroundStyle(AppTheme.primaryText)
            Text(detail)
                .microCaption()
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(.vertical, 2)
    }

    private func externalLinkRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 11) {
            LeafyCompactProfileIconBadge(systemName: icon, size: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .leafyBody()
                    .foregroundStyle(AppTheme.primaryText)
                Text(detail)
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            LeafyDisclosureIndicator()
        }
        .padding(.vertical, 1)
    }
}

private struct ProfileSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

private struct ProfileBrowserItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ThemeColorSwatch: View {
    let option: AppThemeColorPreference
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(option.swatchColor)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(AppTheme.separator, lineWidth: 1)
            )
    }
}

private struct LeafyCompactProfileIconBadge: View {
    let systemName: String
    var tint: Color = AppTheme.accent
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.72))

            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(width: size, height: size)
    }
}

private struct IconAppearanceSwatch: View {
    let option: LeafyAppIconAppearancePreference
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        baseColor.opacity(0.38),
                        baseColor
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay(alignment: .center) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))
                    .rotationEffect(.degrees(-16))
            }
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .stroke(AppTheme.separator, lineWidth: 1)
            )
    }

    private var baseColor: Color {
        switch option {
        case .green:
            return AppTheme.accent(for: .green)
        case .tiffanyBlue:
            return AppTheme.accent(for: .tiffanyBlue)
        case .candyPink:
            return AppTheme.accent(for: .candyPink)
        case .sunsetApricot:
            return AppTheme.accent(for: .sunsetApricot)
        case .irisPurple:
            return AppTheme.accent(for: .irisPurple)
        }
    }
}

private struct PersonalizationSettingsView: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    @AppStorage(AppThemeColorPreference.storageKey) private var appThemeColorPreferenceRaw = AppThemeColorPreference.green.rawValue
    @AppStorage(AppThemeColorPreference.customColorHexKey) private var appThemeCustomColorHex = AppThemeColorPreference.defaultCustomColorHex
    @AppStorage(LeafyAppIconAppearancePreference.storageKey) private var appIconAppearancePreferenceRaw = LeafyAppIconAppearancePreference.green.rawValue
    @AppStorage("appFontSizePreference") private var appDisplaySizePreferenceRaw = AppDisplaySizePreference.standard.rawValue
    @AppStorage(AppAppearancePreference.storageKey) private var appAppearancePreferenceRaw = AppAppearancePreference.light.rawValue
    @AppStorage(AppLanguagePreference.storageKey) private var appLanguagePreferenceRaw = AppLanguagePreference.system.rawValue
    @AppStorage(TimetableCurrentTimeIndicatorPreference.isEnabledKey) private var currentTimeIndicatorIsEnabled = TimetableCurrentTimeIndicatorPreference.defaultIsEnabled
    @AppStorage(TimetableCurrentTimeIndicatorPreference.thicknessKey) private var currentTimeIndicatorThickness = TimetableCurrentTimeIndicatorPreference.defaultThickness
    @State private var showingCustomThemeColorPicker = false

    private var themeColorPreference: AppThemeColorPreference {
        AppThemeColorPreference.storedValue(appThemeColorPreferenceRaw)
    }

    private var iconAppearancePreference: LeafyAppIconAppearancePreference {
        LeafyAppIconAppearancePreference.storedValue(appIconAppearancePreferenceRaw)
    }

    private var displaySizePreference: AppDisplaySizePreference {
        AppDisplaySizePreference(rawValue: appDisplaySizePreferenceRaw) ?? .standard
    }

    private var appearancePreference: AppAppearancePreference {
        AppAppearancePreference.storedValue(appAppearancePreferenceRaw)
    }

    private var languagePreference: AppLanguagePreference {
        AppLanguagePreference.storedValue(appLanguagePreferenceRaw)
    }

    private var currentTimeIndicatorThicknessBinding: Binding<Double> {
        Binding(
            get: {
                TimetableCurrentTimeIndicatorPreference.sanitizedThickness(currentTimeIndicatorThickness)
            },
            set: { newValue in
                currentTimeIndicatorThickness = TimetableCurrentTimeIndicatorPreference.sanitizedThickness(newValue)
            }
        )
    }

    var body: some View {
        List {
            Section {
                ForEach(AppThemeColorPreference.allCases) { option in
                    Button {
                        selectThemeColor(option)
                    } label: {
                        selectionRow(
                            title: option.title(language: leafyLanguage),
                            isSelected: option == themeColorPreference
                        ) {
                            ThemeColorSwatch(option: option, size: 28)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("主题色")
            } footer: {
                Text("主题色会用于 App 强调色、课程卡片和小组件外观。")
            }
            .listRowBackground(AppTheme.cardBackground)

            Section {
                ForEach(AppDisplaySizePreference.allCases) { option in
                    Button {
                        appDisplaySizePreferenceRaw = option.rawValue
                    } label: {
                        selectionRow(
                            title: option.title(language: leafyLanguage),
                            isSelected: option == displaySizePreference
                        ) {
                            FontSizeSwatch(option: option)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("字号")
            } footer: {
                Text("字号会影响全局文本、课表卡片和常用控件尺寸。")
            }
            .listRowBackground(AppTheme.cardBackground)

            Section {
                ForEach(LeafyAppIconAppearancePreference.allCases) { option in
                    Button {
                        appIconAppearancePreferenceRaw = option.rawValue
                    } label: {
                        selectionRow(
                            title: option.title(language: leafyLanguage),
                            isSelected: option == iconAppearancePreference
                        ) {
                            IconAppearanceSwatch(option: option, size: 30)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("App 外观")
            }
            .listRowBackground(AppTheme.cardBackground)

            Section {
                ForEach([AppLanguagePreference.system, .zhHans, .enUS], id: \.self) { option in
                    Button {
                        appLanguagePreferenceRaw = option.rawValue
                    } label: {
                        selectionRow(
                            title: option.title(displayLanguage: leafyLanguage),
                            isSelected: option == languagePreference
                        ) {
                            LeafyIconBadge(systemName: "globe")
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("语言")
            } footer: {
                Text("仅更改 MyLeafy 的显示语言，不会修改系统语言。")
            }
            .listRowBackground(AppTheme.cardBackground)

            Section {
                ForEach(AppAppearancePreference.allCases) { option in
                    Button {
                        withAnimation(.easeInOut(duration: 0.55)) {
                            appAppearancePreferenceRaw = option.rawValue
                        }
                    } label: {
                        selectionRow(
                            title: option.title(language: leafyLanguage),
                            detail: option.detail(language: leafyLanguage),
                            isSelected: option == appearancePreference
                        ) {
                            LeafyIconBadge(systemName: option.systemImage)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("外观")
            } footer: {
                Text("默认使用浅色外观，也可以跟随系统或固定深色。")
            }
            .listRowBackground(AppTheme.cardBackground)

            Section {
                Toggle("显示当前时间线", isOn: $currentTimeIndicatorIsEnabled)

                VStack(alignment: .leading, spacing: AppSpacing.micro) {
                    HStack {
                        Text("粗细")
                        Spacer()
                        Text("\(TimetableCurrentTimeIndicatorPreference.sanitizedThickness(currentTimeIndicatorThickness), specifier: "%.1f") pt")
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: currentTimeIndicatorThicknessBinding,
                        in: TimetableCurrentTimeIndicatorPreference.thicknessRange,
                        step: TimetableCurrentTimeIndicatorPreference.thicknessStep
                    )
                    .disabled(!currentTimeIndicatorIsEnabled)
                }
            } header: {
                Text("课表当前时间线")
            } footer: {
                Text("仅显示在今天所在周，颜色跟随主题色。")
            }
            .listRowBackground(AppTheme.cardBackground)
        }
        .leafyInsetGroupedListStyle()
        .scrollContentBackground(.hidden)
        .background(LeafyPageBackground())
        .navigationTitle("个性化")
        .leafyInlineNavigationTitle()
        .leafySheet(isPresented: $showingCustomThemeColorPicker) {
            CustomThemeColorPickerSheet(color: customThemeColorBinding)
                .presentationDetents([.medium])
        }
    }

    private var customThemeColorBinding: Binding<Color> {
        Binding(
            get: { AppThemeColorPreference.color(fromHex: appThemeCustomColorHex) },
            set: { newValue in
                appThemeCustomColorHex = AppThemeColorPreference.hexString(from: newValue)
                appThemeColorPreferenceRaw = AppThemeColorPreference.custom.rawValue
            }
        )
    }

    private func selectThemeColor(_ option: AppThemeColorPreference) {
        appThemeColorPreferenceRaw = option.rawValue
        if option == .custom {
            showingCustomThemeColorPicker = true
        }
    }

    private func selectionRow<Accessory: View>(
        title: String,
        detail: String? = nil,
        isSelected: Bool,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 12) {
            accessory()

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .leafyBody()
                    .foregroundStyle(AppTheme.primaryText)

                if let detail {
                    Text(detail)
                        .microCaption()
                        .foregroundStyle(AppTheme.tertiaryText)
                }
            }

            Spacer()

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.tertiaryText)
        }
        .contentShape(Rectangle())
    }
}

private struct FontSizeSwatch: View {
    let option: AppDisplaySizePreference

    var body: some View {
        ZStack {
            Circle()
                .fill(AppTheme.softFill)
                .frame(width: 30, height: 30)

            Text("A")
                .font(.system(size: glyphSize, weight: .bold))
                .foregroundStyle(AppTheme.accentEmphasis)
        }
    }

    private var glyphSize: CGFloat {
        switch option {
        case .compact:
            return 12
        case .standard:
            return 14
        case .comfortable:
            return 16
        case .spacious:
            return 18
        }
    }
}

private struct CustomThemeColorPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var color: Color

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ColorPicker("自定义主题色", selection: $color, supportsOpacity: false)

                    HStack(spacing: 12) {
                        Circle()
                            .fill(color)
                            .frame(width: 36, height: 36)
                            .overlay(
                                Circle()
                                    .stroke(AppTheme.separator, lineWidth: 1)
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text("当前颜色")
                                .leafyBody()
                            Text(AppThemeColorPreference.hexString(from: color))
                                .microCaption()
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                } footer: {
                    Text("自定义主题色会用于按钮、课程卡片和页面强调色。")
                }
            }
            .navigationTitle("自定义主题色")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct FeedbackSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyDependencies) private var dependencies
    @State private var isSubmitting = false
    @State private var operationAlert: LeafyOperationAlert?
    @State private var issueType: String
    @State private var feedbackBody: String
    @State private var contact = ""
    @State private var showingContactSheet = false

    private var isCommunityEnabled: Bool {
        ActiveCampusContext.descriptor.supports(.community)
    }

    private var issueTypes: [String] {
        var items = ["问题反馈", "功能建议", "数据异常", "界面体验"]
        if isCommunityEnabled {
            items.append("社区安全")
        }
        return items
    }

    init(initialIssueType: String = "问题反馈", initialBody: String = "") {
        _issueType = State(initialValue: initialIssueType)
        _feedbackBody = State(initialValue: initialBody)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.card) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("举报与反馈内容")
                            .leafyHeadline()

                        Picker("类型", selection: $issueType) {
                            ForEach(issueTypes, id: \.self) { type in
                                Text(L10n.text(type, language: leafyLanguage)).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)

                        TextField("请描述你遇到的问题、建议或不当活动", text: $feedbackBody, axis: .vertical)
                            .lineLimit(5, reservesSpace: true)
                            .padding(14)
                            .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))

                        TextField("联系方式（可选）", text: $contact)
                            .leafyDisableAutocapitalization()
                            .padding(14)
                            .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))

                        Text(isCommunityEnabled
                            ? "社区安全或不当活动也可邮件联系：\(CommunityTerms.supportEmail)"
                            : "当前入口的问题和建议也可以通过这里反馈。")
                            .microCaption()
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .padding(18)
                    .leafyCardStyle()

                    Button {
                        showingContactSheet = true
                    } label: {
                        HStack(spacing: 11) {
                            LeafyCompactProfileIconBadge(systemName: "person.2.wave.2.fill", size: 34)

                            VStack(alignment: .leading, spacing: 1) {
                                Text("联系我们")
                                    .leafyBody()
                                    .foregroundStyle(AppTheme.primaryText)
                                Text("QQ群反馈群")
                                    .microCaption()
                                    .foregroundStyle(AppTheme.tertiaryText)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AppTheme.tertiaryText)
                        }
                        .padding(18)
                        .leafyCardStyle()
                    }
                    .buttonStyle(.plain)
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle("举报与反馈")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .leafyTrailing) {
                    Button(isSubmitting ? "提交中" : "提交") {
                        Task { await submit() }
                    }
                    .disabled(isSubmitting || feedbackBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .leafyOperationAlert($operationAlert)
            .leafySheet(isPresented: $showingContactSheet) {
                ContactUsSheetView()
                    .presentationDetents([.medium, .large])
            }
        }
    }

    @MainActor
    private func submit() async {
        let trimmedBody = feedbackBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else {
            operationAlert = .failure(L10n.text("请先填写反馈内容。", language: leafyLanguage))
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await dependencies.communityActivityRepository.submitFeedback(
                issueType: issueType,
                body: trimmedBody,
                contact: contact,
                deviceInfo: feedbackDeviceInfo()
            )
            feedbackBody = ""
            contact = ""
            operationAlert = .success(
                L10n.text("反馈已提交。", language: leafyLanguage),
                action: { dismiss() }
            )
        } catch {
            operationAlert = .failure(error.localizedDescription)
        }
    }

    private func feedbackDeviceInfo() -> [String: String] {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? L10n.text("未知", language: leafyLanguage)
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? L10n.text("未知", language: leafyLanguage)
        let isCustomCampus = ActiveCampusContext.identity?.isCustom == true
        let loggedIn = isCustomCampus
            ? L10n.text("本地学校账号", language: leafyLanguage)
            : (ActiveCampusContext.networkManager.isLoggedIn ? L10n.text("BJFU 教务已登录", language: leafyLanguage) : L10n.text("BJFU 教务未登录", language: leafyLanguage))
        let lastSync = TimetableCacheMetadata.lastSyncAt.map { DateFormatters.headerWithTime.string(from: $0) } ?? L10n.text("无", language: leafyLanguage)
        return [
            "device": LeafyDeviceInfo.model,
            "system": LeafyDeviceInfo.systemDescription,
            "app": "\(appVersion) (\(build))",
            "loginStatus": loggedIn,
            "lastTimetableSync": lastSync
        ]
    }
}

private struct CommunityTermsPreferenceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyDependencies) private var dependencies
    @State private var isAccepted = false
    @State private var originalAccepted: Bool?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var operationAlert: LeafyOperationAlert?

    private var hasChanges: Bool {
        guard let originalAccepted else { return false }
        return originalAccepted != isAccepted
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("\(AppBrand.displayName) 社区条约")
                            .title2()
                            .foregroundStyle(AppTheme.primaryText)

                        Text("你可以在这里查看社区规则，并重新选择是否同意。不同意后将不能进入社区、发帖或评论。")
                            .leafyBody()
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .padding(18)
                    .leafyCardStyle()

                    VStack(alignment: .leading, spacing: 12) {
                        termsLine("不得发布辱骂、骚扰、歧视、威胁、色情低俗、违法、侵权、侵犯隐私或其他令人反感的内容。")
                        termsLine("不得滥用匿名发布、冒充他人、刷屏、恶意引战或规避审核。")
                        termsLine("\(AppBrand.displayName) 会过滤违规内容；用户可以举报内容、屏蔽用户，并可删除自己发布的帖子和评论。")
                        termsLine("开发者会在 24 小时内处理违规举报，必要时移除内容并禁言或移除违规用户。")
                        termsLine("社区安全联系邮箱：\(CommunityTerms.supportEmail)。")
                    }
                    .padding(18)
                    .leafyCardStyle()

                    VStack(alignment: .leading, spacing: 12) {
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        } else {
                            Toggle(isOn: $isAccepted) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("我同意社区条约")
                                        .leafyBody()
                                        .foregroundStyle(AppTheme.primaryText)
                                    Text(isAccepted ? "同意后可继续使用社区功能。" : "不同意时社区内容和互动会被条款门禁拦截。")
                                        .microCaption()
                                        .foregroundStyle(AppTheme.secondaryText)
                                }
                            }
                            .tint(AppTheme.accent)
                        }
                    }
                    .padding(18)
                    .leafyCardStyle()

                    if let errorMessage {
                        Text(errorMessage)
                            .microCaption()
                            .foregroundStyle(AppTheme.danger)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                    }
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle("社区条约")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .leafyTrailing) {
                    Button(isSaving ? "保存中" : "保存") {
                        Task { await save() }
                    }
                    .disabled(isLoading || isSaving || !hasChanges)
                }
            }
            .task {
                await loadCurrentChoice()
            }
            .leafyOperationAlert($operationAlert)
        }
    }

    private func termsLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.accentEmphasis)
                .padding(.top, 2)
            Text(text)
                .leafyBody()
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @MainActor
    private func loadCurrentChoice() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let accepted = try await dependencies.communityActivityRepository.hasAcceptedCurrentTerms()
            isAccepted = accepted
            originalAccepted = accepted
        } catch {
            errorMessage = error.localizedDescription
            originalAccepted = false
            isAccepted = false
        }
    }

    @MainActor
    private func save() async {
        guard hasChanges else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            if isAccepted {
                try await dependencies.communityActivityRepository.acceptCurrentTerms()
            } else {
                try await dependencies.communityActivityRepository.revokeCurrentTerms()
            }
            originalAccepted = isAccepted
            operationAlert = .success(L10n.text("设置已保存。", language: leafyLanguage))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ContactUsSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyLanguage) private var leafyLanguage
    @State private var isSaving = false
    @State private var saveResultMessage: String?

    private var feedbackImage: UIImage? {
        FeedbackImageAsset.load()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("社区安全与技术支持")
                            .leafyHeadline()
                            .foregroundStyle(AppTheme.primaryText)
                        Text("如需举报不当活动、违规内容或滥用用户，可以在“举报与反馈”中选择“社区安全”，也可以发送邮件到 \(CommunityTerms.supportEmail)。")
                            .leafyBody()
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .padding(18)
                    .leafyCardStyle()

                    if let feedbackImage {
                        Image(uiImage: feedbackImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                                    .stroke(AppTheme.separator, lineWidth: 1)
                            )
                    } else {
                        ContentUnavailableView(
                            "未找到反馈图片",
                            systemImage: "photo",
                            description: Text("请确认 feedback.JPG 已包含在 App 资源中。")
                        )
                    }
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle("联系我们")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .leafyTrailing) {
                    Button {
                        if let feedbackImage {
                            Task { await save(image: feedbackImage) }
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .offset(y: -1.5)
                    }
                    .disabled(isSaving || feedbackImage == nil)
                }
            }
            .alert("保存结果", isPresented: Binding(
                get: { saveResultMessage != nil },
                set: { if !$0 { saveResultMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(saveResultMessage ?? "")
            }
        }
    }

    @MainActor
    private func save(image: UIImage) async {
        isSaving = true
        defer { isSaving = false }

        do {
            try await LeafyPhotoLibrarySaver.save(image)
            saveResultMessage = L10n.text("已保存到系统相册。", language: leafyLanguage)
        } catch {
            saveResultMessage = error.localizedDescription
        }
    }
}

private enum FeedbackImageAsset {
    static func load() -> UIImage? {
        if let image = UIImage(named: "feedback") {
            return image
        }

        let url = Bundle.main.url(forResource: "feedback", withExtension: "JPG")
            ?? Bundle.main.url(forResource: "feedback", withExtension: "jpg")

        guard let url else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

private struct LeafyGuideAndDataSecurityView: View {
    @State private var showingCommunityTermsSheet = false

    private var isCommunityEnabled: Bool {
        ActiveCampusContext.descriptor.supports(.community)
    }

    private let chapters = [
        ManualChapter(
            icon: "leaf.fill",
            title: "开始使用",
            detail: "产品定位与主要入口",
            intro: "\(AppBrand.displayName) 面向北京林业大学，根导航包含课表、社区、日迹、校园和我的。",
            rows: [
                ManualInfo(title: "产品用途", body: "北林的教务和校园服务分布在多个系统。\(AppBrand.displayName) 集中提供常用入口，并保留最近一次成功同步的数据供离线查看。"),
                ManualInfo(title: "与学校系统的关系", body: "\(AppBrand.displayName) 是第三方校园应用，不属于北京林业大学官方教务系统。登录、验证码、校园网、VPN 和访问权限均受学校系统限制。成绩、培养方案和考试安排等正式结果以学校系统为准。"),
                ManualInfo(title: "主要入口", body: "“课表”显示当前学年的课程与个人日程；“社区”用于同学交流和通知；“日迹”包含随记、日程和推送；“校园”提供成绩、考试、教学培养、自习安排、学习空间、校历和评分；“我的”用于管理资料、同步、个性化和安全设置。"),
                ManualInfo(title: "需要同步的情况", body: "选课、调课、成绩发布或考试安排更新后，可连接能够访问北林教务的网络重新同步。同步失败不会删除最近一次成功缓存。")
            ],
            steps: [
                ManualStep(title: "查看课表", body: "确认当前周和当天课程，按需刷新数据或调整显示设置。"),
                ManualStep(title: "记录日迹", body: "在“日迹”中写随记、维护个人日程或调整推送。"),
                ManualStep(title: "查看校园数据", body: "成绩、考试、培养方案、自习安排、学习空间、校历、评分、学习资料和体育记录位于“校园”。"),
                ManualStep(title: "管理账号与数据", body: "登录状态、同步缓存、共享课表、反馈和本手册位于“我的”。")
            ]
        ),
        ManualChapter(
            icon: "calendar",
            title: "课表与学年",
            detail: "周次、学年范围和刷新",
            intro: "课表一次浏览一个学年，从秋季学期开始，到下一学年开始前一天结束。",
            rows: [
                ManualInfo(title: "学年范围", body: "当前学年包含秋季学期、寒假、春季学期和暑假。暑假最后一周停在学年边界，不会继续滑入下一学年第 1 周。"),
                ManualInfo(title: "进入下一学年", body: "打开课表右上角的周次与日期选择，选择下一学年或对应日期。返回当前学年时使用同一入口。"),
                ManualInfo(title: "学校课表数据", body: "学校每次返回一个学期的课表，数据范围为 20 周。App 按绝对日期把已获取的学期数据放入当前学年；尚未开放或尚未获取的未来学期保持为空。"),
                ManualInfo(title: "周次与假期", body: "教学周显示第几周；寒假和暑假显示假期名称。学期结束日期和假期范围来自运行时校历配置。"),
                ManualInfo(title: "刷新范围", body: "学校课表刷新只请求当前启用的学期。切换学年用于查看已配置或已缓存的数据，不会主动请求尚未开放的未来学期。")
            ],
            steps: [
                ManualStep(title: "切换周次", body: "在当前学年内左右滑动，或使用右上角周次菜单定位日期。"),
                ManualStep(title: "切换学年", body: "到达暑假最后一周后，打开周次与日期选择进入下一学年。"),
                ManualStep(title: "更新课表", body: "学校开放新学期后，确认教务登录有效，再在课表页刷新。")
            ]
        ),
        ManualChapter(
            icon: "note.text",
            title: "日迹",
            detail: "随记、日程与推送",
            intro: "日迹顶部提供随记、日程和推送，内容按当前校园身份保存在本机。",
            rows: [
                ManualInfo(title: "随记", body: "随记支持文字、图片、最多 3 个常用文档附件、录音、Tag、回顾和统计。已有的文字随记可使用 Markdown 编辑与预览，并把本地图片或附件插入正文位置。卡片可置顶、编辑、生成图文卡片、转为个人日程、创建投稿邮件或移到回收站。"),
                ManualInfo(title: "输入器", body: "点按输入区后会展开编辑；内容达到 4 个视觉行时，可使用右上角按钮放大或缩小编辑区。"),
                ManualInfo(title: "Tag 筛选", body: "点击卡片上的 Tag 后，列表顶部会显示当前 Tag。点“全部随记”即可清除 Tag 筛选并回到完整列表。"),
                ManualInfo(title: "记录日迹", body: "在日迹侧栏“记录”分组中打开“记录日迹”。页面按自然年查看每月随记数和记录天数，也会显示近 30 天热力、连续记录、星期与时段习惯、常用标签和里程碑。点按近 30 天的日期可查看当天随记。"),
                ManualInfo(title: "统计分享", body: "点右上角分享按钮可在本机生成统计图片，再使用系统分享。图片只含聚合统计，不含随记正文或标签名；统计和图片都不会上传。"),
                ManualInfo(title: "个人日程", body: "日程页浏览用户创建的计划和倒计时。当前学年内的日期会投射到课表；学年外日期保留在个人日程列表。学校课程、考试和校历不会写入随记或个人日程。"),
                ManualInfo(title: "推送", body: "推送页管理考试提醒和重要日期报告。开关保存后立即生效，系统通知仍受设备通知权限控制。"),
                ManualInfo(title: "本地文件", body: "随记图片、附件和录音保存在当前校园身份的 App 目录。删除随记或清除本地数据时，对应文件会一起删除。")
            ],
            steps: [
                ManualStep(title: "创建随记", body: "在随记页底部输入文字，或使用加号添加图片、附件和录音。加号不再提供新建文章入口。"),
                ManualStep(title: "编辑与投稿", body: "打开随记菜单后选择编辑，可在源文与预览之间切换，并插入格式、图片或附件。选择“投稿”会调起系统默认邮箱并生成邮件草稿；本地图片和附件需要在邮箱 App 中按需补充。"),
                ManualStep(title: "查看某个 Tag", body: "点卡片上的 Tag 查看筛选结果；点“全部随记”返回完整列表。"),
                ManualStep(title: "维护个人日程", body: "切换到“日程”创建或编辑计划，日期在当前学年内时可在课表中查看。")
            ]
        ),
        ManualChapter(
            icon: "wifi",
            title: "数据来源",
            detail: "教务同步与本地维护",
            intro: "课表、成绩等教务数据来自北京林业大学强智教务系统。查询由用户主动发起，解析结果按功能保存在本机。",
            rows: [
                ManualInfo(title: "校园网要求", body: "北林强智教务系统通常只能通过校园网或学校认可的 VPN 访问。浏览器无法打开教务系统时，App 也无法同步相关数据。"),
                ManualInfo(title: "教务数据", body: "课表、成绩、考试安排、教学计划、培养方案、空闲教室和教室占用来自北林教务页面。解析结果用于展示、检索和离线查看。"),
                ManualInfo(title: "本机数据", body: "随记、个人日程、课程备注、课表提醒、收藏、学习资料、学习空间、任务、专注记录和体测记录由用户在当前设备创建、导入或维护。"),
                ManualInfo(title: "登录状态", body: "学校登录状态用于减少重复认证。会话失效、网络切换或学校页面变化时，相关功能会要求重新登录。"),
                ManualInfo(title: "同步问题", body: "先确认当前网络能够访问北林教务，再检查是否需要重新登录。单个页面持续异常时，请记录页面名称、错误提示和发生时间。")
            ],
            steps: [
                ManualStep(title: "确认网络", body: "连接 bjfu-wifi、校园网或学校 VPN，并确认浏览器能够访问北林教务系统。"),
                ManualStep(title: "重新登录", body: "出现会话失效或登录状态异常提示时，完成认证后返回原页面刷新。"),
                ManualStep(title: "提交反馈", body: "问题仍未解决时，请附上页面名称、错误提示、发生时间和浏览器访问结果。")
            ]
        ),
        ManualChapter(
            icon: "arrow.triangle.2.circlepath",
            title: "同步与缓存",
            detail: "本地缓存和重试顺序",
            intro: "最近一次成功同步的教务数据保存在本机。网络或学校系统异常时，现有缓存仍可查看。",
            rows: [
                ManualInfo(title: "教务缓存", body: "课表、成绩、考试安排、教学计划、培养方案和空闲教室查询结果按功能保存在本机，供离线查看。"),
                ManualInfo(title: "本地记录", body: "随记、个人日程、课程备注、课表提醒、收藏、学习资料、学习空间、任务、专注记录和体测记录由用户在当前设备创建或导入。"),
                ManualInfo(title: "同步失败时", body: "同步或导入失败不会删除现有数据。成功更新后，新数据会替换对应缓存。"),
                ManualInfo(title: "清除本地缓存", body: "此操作会删除本地身份、教务登录状态、教务缓存，以及随记、个人日程、图片、附件、录音、备注、提醒、收藏、学习资料、任务和体测记录等本机内容。"),
                ManualInfo(title: "适用情况", body: "仅在切换账号、身份异常、缓存明显不一致或需要移除本机数据时清除缓存。普通同步失败应先重试或重新登录。")
            ],
            steps: [
                ManualStep(title: "确认网络", body: "连接能够访问北林教务的网络，并确认学校页面可以打开。"),
                ManualStep(title: "重新同步", body: "返回对应页面刷新，或在“我的”中集中更新教务数据。"),
                ManualStep(title: "检查缓存", body: "进入“缓存与同步”查看状态，确认是否需要清理。"),
                ManualStep(title: "提交反馈", body: "同一功能多次失败时，请附上页面名称、错误提示和发生时间。")
            ]
        ),
        ManualChapter(
            icon: "person.2.fill",
            title: "社区、反馈与共享课表",
            detail: "社区数据与主动发布内容",
            intro: "\(AppBrand.displayName) 社区服务与北林教务系统相互独立。学校身份用于确认校园归属，社区资料用于展示、互动、通知和安全处理。",
            rows: [
                ManualInfo(title: "社区服务保存的内容", body: "昵称、头像、学院、年级、帖子、评论、点赞、收藏、通知、举报、反馈、评教和主动发布的共享课表数据会保存到 \(AppBrand.displayName) 社区服务。正式账户可在“我的”底部直接发起永久删除。"),
                ManualInfo(title: "草稿和图文卡片", body: "普通帖子草稿按社区账号保存在本机，仅在原账号登录后显示。图文卡片也保存在本机。帖子通过发布校验并进入发布队列后，内容才会提交到社区服务。"),
                ManualInfo(title: "帖子图片和附件", body: "用户选择的帖子图片及 PDF、Excel、Word 或 Markdown 附件存入 Supabase 私有存储，并通过短期签名链接访问。附件会校验类型和文件结构，但不提供病毒扫描。删帖后媒体通常保留 30 天；存在未解决举报或后台隐藏时暂停清理。"),
                ManualInfo(title: "保留在本机的内容", body: "成绩、考试安排、随记、个人日程、课程备注、提醒、收藏、学习资料文件、学习空间、任务、专注记录和体测记录不会因进入社区自动上传。"),
                ManualInfo(title: "共享课表", body: "共享内容仅包含课程安排，不包含成绩、考试、课程备注、提醒、收藏或学习资料。查看权限可随时撤销。"),
                ManualInfo(title: "反馈信息", body: "举报与反馈会提交文字说明。必要时还会提交设备型号、iOS 版本、App 版本、登录状态和最近同步时间，用于定位问题。"),
                ManualInfo(title: "社区安全", body: "发现不当内容、骚扰、冒充、刷屏、恶意评分或隐私泄露时，可在“举报与反馈”中选择“社区安全”，也可通过联系邮箱或反馈群说明情况。")
            ],
            steps: [
                ManualStep(title: "发布前检查", body: "提交帖子、评论、评分或共享课表前，请确认内容不含个人隐私、他人隐私或其他不宜公开的信息。"),
                ManualStep(title: "举报问题", body: "发现不当内容时，请通过举报入口说明问题类型和位置。"),
                ManualStep(title: "撤销或删除", body: "共享课表权限可在对应入口撤销；正式账户可在“我的”底部删除 MyLeafy 账户及关联线上内容。演示账户不可删除。")
            ]
        ),
        ManualChapter(
            icon: "lock.shield.fill",
            title: "数据安全边界",
            detail: "本机、学校和社区服务",
            intro: "数据分别由本机、学校系统和社区服务处理。清除缓存、退出登录或撤销共享前，请先确认对应的数据范围。",
            rows: [
                ManualInfo(title: "教务账号和密码", body: "教务账号和密码仅用于向北林强智教务系统发起登录请求，不用于社区资料，也不会作为帖子、评论、反馈或共享课表内容保存。"),
                ManualInfo(title: "学校教务数据", body: "课表、成绩、考试、教学计划和培养方案等个人教务数据优先保存在本机，供离线查看。学校教务系统仍是正式数据来源。"),
                ManualInfo(title: "本机私有数据", body: "随记、个人日程、图片、附件、录音、学习资料、简历、社区帖子草稿、图文卡片、课程备注、提醒、学习空间、任务、专注记录、体测记录和收藏保存在 App 的本机空间。卸载 App、清除缓存或更换设备前，请确认需要保留的内容。"),
                ManualInfo(title: "社区服务数据", body: "主动参与社区、反馈、评教或共享课表时，相关内容会进入 \(AppBrand.displayName) 社区服务，用于展示、通知、审核、反馈处理和社区安全。"),
                ManualInfo(title: "退出登录、清除缓存与删除账户", body: "退出登录只结束当前会话并保留本机缓存；清除本地缓存会删除当前设备保存的数据；删除 MyLeafy 账户还会永久删除社区账户与关联线上内容。以上操作都不会删除或修改北京林业大学官方教务账户。"),
                ManualInfo(title: "设备权限", body: "相册、文件和通知权限仅在对应功能中使用。导入资料保存在 App 私有目录，通知用于课程和本机提醒。拒绝权限只影响对应功能。")
            ],
            steps: [
                ManualStep(title: "确认数据来源", body: "教务结果以学校系统为准；个人记录位于当前设备；社区内容来自主动发布或反馈。"),
                ManualStep(title: "处理账号问题", body: "登录异常时先重新认证。身份不一致或切换账号时，再考虑清除缓存。"),
                ManualStep(title: "迁移或卸载", body: "更换设备、卸载 App 或清理本机文件前，请导出需要保留的资料。")
            ]
        ),
        ManualChapter(
            icon: "questionmark.circle.fill",
            title: "常见问题",
            detail: "网络、登录与数据问题",
            intro: "常见原因包括网络不可达、教务会话过期、验证码失效、学校页面变化、缓存未更新或社区服务暂时不可用。",
            rows: [
                ManualInfo(title: "课表或成绩无法刷新", body: "确认当前网络能够访问北林教务。出现重新登录提示时，完成认证后返回功能页刷新。浏览器也无法访问时，请等待网络或学校服务恢复。"),
                ManualInfo(title: "无法登录", body: "检查账号、密码、验证码、网络和学校页面状态。验证码过期后需刷新；切换网络或从后台返回时，可重新打开登录页。"),
                ManualInfo(title: "仍显示旧数据", body: "当前显示的是最近一次成功同步的缓存。刷新成功后，新数据会替换旧缓存。"),
                ManualInfo(title: "空闲教室或培养计划异常", body: "先重新同步并确认查询条件。问题持续存在时，请反馈页面名称和发生时间。"),
                ManualInfo(title: "社区功能不可用", body: "确认教务身份有效并已完成社区资料。服务异常时可稍后重试；内容、举报、评分或共享课表问题可通过“举报与反馈”提交。"),
                ManualInfo(title: "提交反馈", body: "请说明页面名称、网络状态、是否重新登录、错误提示、发生时间，以及浏览器能否访问学校系统。")
            ],
            steps: [
                ManualStep(title: "确认问题类型", body: "教务数据检查校园网和登录；社区功能检查社区身份和网络；本地资料检查设备存储和文件权限。"),
                ManualStep(title: "保留错误信息", body: "记录错误文字、页面名称和发生时间。"),
                ManualStep(title: "补充环境信息", body: "说明网络连接、重新登录、缓存清理和浏览器访问情况。")
            ]
        )
    ]

    var body: some View {
        List {
            Section {
                ManualIntroBlock()
                    .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 18))
                    .listRowBackground(Color.clear)
            }

            if isCommunityEnabled {
                Section("社区") {
                    Button {
                        showingCommunityTermsSheet = true
                    } label: {
                        ManualActionRow(
                            icon: "checkmark.shield.fill",
                            title: "社区条约",
                            detail: "查看或更新同意状态"
                        )
                    }
                    .buttonStyle(.plain)
                }
                .listRowBackground(AppTheme.cardBackground)
            }

            Section(header: Text("目录"), footer: Text("点进每一项，可以查看对应章节的详细说明。")) {
                ForEach(chapters) { chapter in
                    NavigationLink {
                        ManualChapterDetailView(chapter: chapter)
                    } label: {
                        ManualDirectoryRow(chapter: chapter)
                    }
                }
            }
        }
        .leafyInsetGroupedListStyle()
        .leafyCompactListSectionSpacing()
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(LeafyPageBackground())
        .navigationTitle("帮助中心")
        .leafyInlineNavigationTitle()
        .leafySheet(isPresented: $showingCommunityTermsSheet) {
            CommunityTermsPreferenceSheet()
                .presentationDetents([.large])
        }
    }
}

private struct ManualInfo: Identifiable {
    var id: String { title }
    let title: String
    let body: String
}

private struct ManualStep: Identifiable {
    var id: String { title }
    let title: String
    let body: String
}

private struct ManualChapter: Identifiable {
    var id: String { title }
    let icon: String
    let title: String
    let detail: String
    let intro: String
    let rows: [ManualInfo]
    let steps: [ManualStep]
}

private struct ManualIntroBlock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(AppBrand.displayName) 帮助中心")
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)

                    Text("使用指南 / 常见问题 / 同步与数据安全")
                        .microCaption()
                        .foregroundStyle(AppTheme.tertiaryText)
                }
            }

            Text("本手册说明 \(AppBrand.displayName) 的主要入口、课表学年范围、日迹用法、教务同步、数据边界和常见问题处理方式。")
                .leafySubheadline()
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 0)
    }
}

private struct ManualDirectoryRow: View {
    let chapter: ManualChapter

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: chapter.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(chapter.title)
                    .leafyBody()
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)

                Text(chapter.detail)
                    .microCaption()
                    .foregroundStyle(AppTheme.tertiaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

private struct ManualActionRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .leafyBody()
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)

                Text(detail)
                    .microCaption()
                    .foregroundStyle(AppTheme.tertiaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.tertiaryText)
        }
        .padding(.vertical, 4)
    }
}

private struct ManualChapterDetailView: View {
    let chapter: ManualChapter

    var body: some View {
        ScrollView(showsIndicators: false) {
            ManualChapterCard(chapter: chapter)
                .padding(.horizontal, AppSpacing.page)
                .padding(.top, AppSpacing.page)
                .padding(.bottom, AppSpacing.section)
        }
        .background(LeafyPageBackground())
        .navigationTitle(chapter.title)
        .leafyInlineNavigationTitle()
    }
}

private struct ManualChapterCard: View {
    let chapter: ManualChapter

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                LeafyIconBadge(systemName: chapter.icon)

                VStack(alignment: .leading, spacing: 5) {
                    Text(chapter.title)
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)

                    Text(chapter.intro)
                        .leafyBody()
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(chapter.rows) { row in
                    ManualInfoRow(info: row)
                }
            }

            if !chapter.steps.isEmpty {
                Divider()
                    .overlay(AppTheme.separator)

                VStack(alignment: .leading, spacing: 12) {
                    Text("建议步骤")
                        .leafySubheadline()
                        .foregroundStyle(AppTheme.primaryText)

                    ForEach(chapter.steps.indices, id: \.self) { index in
                        ManualStepRow(number: index + 1, step: chapter.steps[index])
                    }
                }
            }
        }
        .padding(18)
        .leafyCardStyle()
    }
}

private struct ManualInfoRow: View {
    let info: ManualInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(info.title)
                .leafySubheadline()
                .foregroundStyle(AppTheme.primaryText)

            Text(info.body)
                .leafyBody()
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(AppTheme.accent.opacity(0.38))
                .frame(width: 3)
        }
    }
}

private struct ManualStepRow: View {
    let number: Int
    let step: ManualStep

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .microCaption()
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(AppTheme.accent, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .leafySubheadline()
                    .foregroundStyle(AppTheme.primaryText)

                Text(step.body)
                    .leafyBody()
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct CacheAndSyncView: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.modelContext) private var modelContext
    @Query private var courses: [Course]
    @Query private var grades: [Grade]
    @Query private var notes: [CourseNote]
    @Query private var occurrenceNotes: [CourseOccurrenceNote]
    @Query private var reminders: [CourseReminderSetting]
    @Query private var cellReminders: [TimetableCellReminder]
    @Query private var favoriteClassrooms: [FavoriteClassroom]
    @Query private var favoriteLinks: [FavoriteCampusLink]
    @Query private var postgraduateTargets: [PostgraduateTarget]
    @Query private var careerResumes: [CareerResumeDocument]
    @Query private var careerTasks: [CareerTask]
    @Query private var careerOpportunities: [CareerOpportunity]
    @Query private var learningMaterials: [LearningMaterialDocument]
    @Query private var learningProjects: [LearningProject]
    @Query private var learningTasks: [LearningProjectTask]
    @Query private var studyTimeRecords: [StudyTimeRecord]
    @Query private var fitnessTestRecords: [FitnessTestRecord]
    @Query private var medicalLedgerEntries: [MedicalLedgerEntry]
    @Query private var medicalLedgerPhotos: [MedicalLedgerPhoto]
    @Query private var scheduleMemos: [ScheduleMemo]
    @Query private var scheduleMemoImages: [ScheduleMemoImage]
    @Query private var scheduleMemoAttachments: [ScheduleMemoAttachment]
    @Query private var scheduleMemoAudioRecords: [ScheduleMemoAudio]

    @State private var isSyncing = false
    @State private var isClearing = false
    @State private var message: String?
    @State private var cacheSummary = ProfileCacheSummary.empty
    @State private var showingAcademicCacheClearConfirmation = false
    @State private var showingClearConfirmation = false
    private let networkManager = ActiveCampusContext.networkManager
    @State private var reauthenticationRequest: SchoolReauthenticationRequest?
    @State private var operationAlert: LeafyOperationAlert?

    private var isCustomCampus: Bool {
        ActiveCampusContext.identity?.isCustom == true
    }

    var body: some View {
        List {
            Section {
                Button {
                    Task { await syncAll() }
                } label: {
                    HStack {
                        Text(syncButtonTitle)
                        Spacer()
                        if isSyncing { ProgressView() }
                    }
                }
                .disabled(isSyncing || isClearing)

                Button(role: .destructive) {
                    showingAcademicCacheClearConfirmation = true
                } label: {
                    Text(L10n.text("清除教务缓存", language: leafyLanguage))
                }
                .disabled(isSyncing || isClearing)

                Button(role: .destructive) {
                    showingClearConfirmation = true
                } label: {
                    Text(isClearing ? L10n.text("清理中", language: leafyLanguage) : L10n.text("清除本地缓存", language: leafyLanguage))
                }
                .disabled(isSyncing || isClearing)

                if !isCustomCampus {
                    NavigationLink {
                        CampusNetworkConnectionGuideView()
                    } label: {
                        Label("校园网连接说明", systemImage: "wifi")
                    }
                    .disabled(isSyncing || isClearing)
                }
            } footer: {
                Text(cacheFooterText)
            }

            Section("缓存状态") {
                ForEach(cacheSummary.rows) { row in
                    cacheRow(row)
                }
            }

            if let message {
                Section {
                    Text(message)
                        .foregroundStyle(message.contains(L10n.text("失败", language: leafyLanguage)) ? AppTheme.danger : AppTheme.secondaryText)
                }
            }
        }
        .navigationTitle(isCustomCampus ? "管理本地数据" : "缓存与同步")
        .leafyInlineNavigationTitle()
        .confirmationDialog("确认清除教务缓存？", isPresented: $showingAcademicCacheClearConfirmation, titleVisibility: .visible) {
            Button("清除教务缓存", role: .destructive) {
                clearAcademicCaches()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(academicCacheClearConfirmationText)
        }
        .confirmationDialog("确认清除本地缓存？", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
            Button("清除缓存", role: .destructive) {
                clearAllCaches()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(clearConfirmationText)
        }
        .schoolReauthenticationSheet(
            request: $reauthenticationRequest,
            networkManager: networkManager
        ) { _ in
            Task { await syncAll() }
        }
        .leafyOperationAlert($operationAlert)
        .onAppear(perform: refreshCacheSummary)
        .onReceive(NotificationCenter.default.publisher(for: .schoolDataDidRefresh)) { _ in
            refreshCacheSummary()
        }
        .onChange(of: leafyLanguage) { _, _ in
            refreshCacheSummary()
        }
    }

    private var syncButtonTitle: String {
        if isSyncing {
            return L10n.text(isCustomCampus ? "检查中" : "同步中", language: leafyLanguage)
        }
        return L10n.text(isCustomCampus ? "检查本地数据状态" : "重新同步教务数据", language: leafyLanguage)
    }

    private var cacheFooterText: String {
        if isCustomCampus {
            return "“清除教务缓存”只删除课表、成绩、考试安排和同步记录，保留账号登录状态和本机保存的内容；“清除本地缓存”会一并删除本地身份、备注、提醒、收藏、简历、职业规划、学习数据和体测记录等内容，需要重新登录当前账号。"
        }
        return "“清除教务缓存”只删除课表、成绩、考试安排、教学计划和空教室等教务数据，保留登录状态和本机保存的内容；“清除本地缓存”会一并删除本地身份、教务登录态、备注、提醒、收藏、简历、职业规划和学习数据等内容，需要连接校园网重新登录。"
    }

    private var academicCacheClearConfirmationText: String {
        isCustomCampus
            ? "这个操作只会清除课表、成绩、考试安排等学校数据和同步记录。本地身份、账号登录状态、备注、提醒、收藏和学习数据会保留。"
            : "这个操作只会清除课表、成绩、考试安排、教学计划、培养方案和空教室等教务缓存。本地身份、教务登录状态、备注、提醒、收藏和学习数据会保留。"
    }

    private var clearConfirmationText: String {
        isCustomCampus
            ? "这个操作会清除本地身份、简历、职业规划和本机保存的数据。清除后需要重新登录当前账号。"
            : "这个操作会清除本地身份、教务登录态、简历、职业规划和本机保存的数据。清除后需要连接校园网重新登录。"
    }

    private func cacheRow(_ row: ProfileCacheSummaryRow) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text(row.title, language: leafyLanguage))
                    .leafyBody()
                Text(row.detail)
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Spacer()
            Text(row.value)
                .leafySubheadline()
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private func refreshCacheSummary() {
        cacheSummary = ProfileCacheSummary.makeLive(
            language: leafyLanguage,
            courseCount: courses.count,
            gradeCount: grades.count,
            noteCount: notes.count + occurrenceNotes.count,
            reminderCount: reminders.count,
            cellReminderCount: cellReminders.count,
            favoriteClassroomCount: favoriteClassrooms.count,
            postgraduateTargetCount: postgraduateTargets.count,
            learningMaterialCount: learningMaterials.count,
            learningProjectCount: learningProjects.count,
            learningTaskCount: learningTasks.count,
            studyTimeRecordCount: studyTimeRecords.count,
            fitnessTestRecordCount: fitnessTestRecords.count,
            scheduleMemoCount: scheduleMemos.count
        )
    }

    @MainActor
    private func syncAll() async {
        guard !isSyncing else { return }

        if !isCustomCampus,
           !ReviewDemoMode.isEnabled,
           let request = await SchoolReauthentication.preflightRequest(
               networkManager: networkManager,
               context: .schoolDataSync
           ) {
            reauthenticationRequest = request
            return
        }

        isSyncing = true
        defer {
            isSyncing = false
            refreshCacheSummary()
        }

        switch await SchoolDataSyncService.syncAll(
            modelContext: modelContext,
            language: leafyLanguage,
            userInitiated: true
        ) {
        case .success(let syncMessage):
            message = syncMessage
        case .needsLogin:
            operationAlert = .failure(L10n.text("请先连接校园网登录教务系统。", language: leafyLanguage))
        case .needsReauthentication(let context):
            reauthenticationRequest = SchoolReauthenticationRequest(context: context)
        }
    }

    @MainActor
    private func clearAcademicCaches() {
        isClearing = true

        for course in courses { modelContext.delete(course) }
        for grade in grades { modelContext.delete(grade) }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            isClearing = false
            operationAlert = .failure("教务缓存清除失败：\(error.localizedDescription)")
            return
        }

        SchoolDataCache.clearDiscoverCaches()
        TimetableCacheMetadata.clear()
        LeafyWidgetSnapshotBuilder.publish(
            from: modelContext,
            isAuthenticated: networkManager.hasCachedIdentity || isCustomCampus || ReviewDemoMode.isEnabled
        )
        SchoolDataRefreshNotifier.post(.all)

        isClearing = false
        message = L10n.text("教务缓存已清除，本地数据与登录状态已保留。", language: leafyLanguage)
        refreshCacheSummary()
        operationAlert = .success(L10n.text("教务缓存已清除。", language: leafyLanguage))
    }

    @MainActor
    private func clearAllCaches() {
        isClearing = true

        do {
            try CareerDocumentFileStore.deleteAllFiles()
        } catch {
            isClearing = false
            operationAlert = .failure("简历文件清除失败：\(error.localizedDescription)")
            return
        }

        do {
            try SchoolLoginCredentialStore.deleteAll()
        } catch {
            isClearing = false
            operationAlert = .failure("教务登录凭据清除失败：\(error.localizedDescription)")
            return
        }

        TimetableNotificationManager.cancelAllCourseReminders(courses: courses)
        TimetableNotificationManager.cancelAllCellReminders(cellReminders)
        ScheduleReportNotificationManager.clearScheduledNotifications()

        for course in courses { modelContext.delete(course) }
        for grade in grades { modelContext.delete(grade) }
        for note in notes { modelContext.delete(note) }
        for note in occurrenceNotes { modelContext.delete(note) }
        for reminder in reminders { modelContext.delete(reminder) }
        for reminder in cellReminders { modelContext.delete(reminder) }
        for favorite in favoriteClassrooms { modelContext.delete(favorite) }
        for favorite in favoriteLinks { modelContext.delete(favorite) }
        for target in postgraduateTargets { modelContext.delete(target) }
        for resume in careerResumes { modelContext.delete(resume) }
        for task in careerTasks { modelContext.delete(task) }
        for opportunity in careerOpportunities { modelContext.delete(opportunity) }
        for project in learningProjects { modelContext.delete(project) }
        for task in learningTasks { modelContext.delete(task) }
        for record in studyTimeRecords { modelContext.delete(record) }
        for material in learningMaterials {
            try? LearningMaterialFileStore.deleteFile(named: material.localFilename)
            modelContext.delete(material)
        }
        for record in fitnessTestRecords { modelContext.delete(record) }
        for photo in medicalLedgerPhotos {
            try? MedicalLedgerPhotoStore.deleteFile(named: photo.localFilename)
            modelContext.delete(photo)
        }
        for entry in medicalLedgerEntries { modelContext.delete(entry) }
        MedicalLedgerPhotoStore.deleteAllFiles()
        do {
            try ScheduleMemoImageStore.deleteAllFiles()
        } catch {
            isClearing = false
            operationAlert = .failure("随记图片清除失败：\(error.localizedDescription)")
            return
        }
        do {
            try ScheduleMemoAttachmentStore.deleteAllFiles()
        } catch {
            isClearing = false
            operationAlert = .failure("随记附件清除失败：\(error.localizedDescription)")
            return
        }
        do {
            try ScheduleMemoAudioStore.deleteAllFiles()
        } catch {
            isClearing = false
            operationAlert = .failure("随记录音清除失败：\(error.localizedDescription)")
            return
        }
        for image in scheduleMemoImages { modelContext.delete(image) }
        for attachment in scheduleMemoAttachments { modelContext.delete(attachment) }
        for audio in scheduleMemoAudioRecords { modelContext.delete(audio) }
        for memo in scheduleMemos { modelContext.delete(memo) }

        SchoolDataCache.clearDiscoverCaches()
        TimetableCacheMetadata.clear()
        CustomScheduleStore.clear()
        let sunshineRunSettings = SunshineRunStore.loadReminderSettings()
        SunshineRunNotificationManager.cancelScheduledNotifications(settings: sunshineRunSettings)
        SunshineRunStore.clear()
        ScheduleReportSettingsStore.clear()
        AppSessionResetter.returnToLogin(modelContext: modelContext)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            isClearing = false
            operationAlert = .failure("本地缓存清除失败：\(error.localizedDescription)")
            return
        }

        isClearing = false
        message = L10n.text("本地缓存和本地身份已清除。", language: leafyLanguage)
        refreshCacheSummary()
        operationAlert = .success(L10n.text("本地缓存已清除。", language: leafyLanguage))
    }
}

private struct CampusNetworkConnectionGuideView: View {
    @Environment(\.openURL) private var openURL
    @State private var browserItem: ProfileBrowserItem?

    private let easyConnectURL = URL(string: "https://apps.apple.com/cn/app/easyconnect/id440460214")!
    private let vpnGuideURL = URL(string: "https://nic.bjfu.edu.cn/bszn/bslc/c5e6826b4e424db886eb70b0780de781.htm")!

    var body: some View {
        List {
            Section("在校内") {
                Label("连接 bjfu-wifi", systemImage: "wifi")
                    .leafyHeadline()

                Text("课表、成绩等教务信息需要通过校园网获取。连接校园网后返回 MyLeafy，可登录教务并同步课表、成绩和考试安排，或查询空闲教室。")
                    .leafyBody()
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Section("在校外") {
                Label("通过北林 VPN 连接", systemImage: "network.badge.shield.half.filled")
                    .leafyHeadline()

                Text("先安装 EasyConnect，使用学校账号连接北林 VPN。连接成功后返回 MyLeafy，可使用需要校园网的教务功能。")
                    .leafyBody()
                    .foregroundStyle(AppTheme.secondaryText)

                Button {
                    openURL(easyConnectURL)
                } label: {
                    Label("前往 App Store 下载 EasyConnect", systemImage: "arrow.down.app.fill")
                }

                Button {
                    browserItem = ProfileBrowserItem(url: vpnGuideURL)
                } label: {
                    Label("查看学校官方 VPN 使用指南", systemImage: "safari")
                }
            }

            Section {
                Text("如果重新登录页暂时无法加载验证码，请先确认校园网或北林 VPN 已连接，再点击验证码区域重试。")
                    .leafyBody()
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .leafyInsetGroupedListStyle()
        .navigationTitle("校园网连接说明")
        .leafyInlineNavigationTitle()
        .sheet(item: $browserItem) { item in
            ProfileSafariView(url: item.url)
        }
    }
}

private enum CampusLinkCatalog {
    struct LinkItem {
        let title: String
        let url: URL
    }

    struct LinkGroup {
        let title: String
        let links: [LinkItem]
    }

    static let serviceLinks: [LinkItem] = [
        ("官方网站", URL(string: "http://www.bjfu.edu.cn/")!),
        ("北林VPN", URL(string: "http://vpn1.bjfu.edu.cn/")!),
        ("数字北林", URL(string: "http://cas.bjfu.edu.cn/")!),
        ("教务系统", URL(string: "http://newjwxt.bjfu.edu.cn/")!),
        ("教务处", URL(string: "http://jwc.bjfu.edu.cn/")!),
        ("学生处", URL(string: "http://xsc.bjfu.edu.cn/")!),
        ("学工系统", URL(string: "http://xgxt.bjfu.edu.cn/")!),
        ("网络计费系统（内网）", URL(string: "http://e.bjfu.edu.cn/")!),
        ("图书馆", URL(string: "http://lib.bjfu.edu.cn/")!),
        ("邮件服务系统", URL(string: "http://mail.bjfu.edu.cn/")!),
        ("校医院", URL(string: "http://xyy.bjfu.edu.cn/")!),
        ("青桥网", URL(string: "http://qq.bjfu.edu.cn/")!),
        ("心桥网", URL(string: "http://xinqiao.bjfu.edu.cn/")!),
        ("可信电子成绩单", URL(string: "http://transcript.bjfu.edu.cn/login")!),
        ("教学平台", URL(string: "http://jxpt.bjfu.edu.cn")!),
        ("本科招生网", URL(string: "http://zsb.bjfu.edu.cn/")!),
        ("实验室与实践教学管理平台", URL(string: "http://sjjx.bjfu.edu.cn")!),
        ("保卫处", URL(string: "http://bwc.bjfu.edu.cn/")!),
        ("中国大学MOOC", URL(string: "https://www.icourse163.org/")!),
        ("学堂在线", URL(string: "https://www.xuetangx.com/")!)
    ]
    .map { LinkItem(title: $0.0, url: $0.1) }

    static let collegeLinks: [LinkItem] = [
        ("林学院", URL(string: "http://lxy.bjfu.edu.cn/")!),
        ("水土保持学院", URL(string: "http://shuibao.bjfu.edu.cn/")!),
        ("生物科学与技术学院", URL(string: "http://biology.bjfu.edu.cn/")!),
        ("园林学院", URL(string: "http://sola.bjfu.edu.cn/")!),
        ("经济管理学院", URL(string: "http://em.bjfu.edu.cn/")!),
        ("工学院", URL(string: "http://gxy.bjfu.edu.cn/")!),
        ("材料科学与技术学院", URL(string: "http://clxy.bjfu.edu.cn/")!),
        ("人文社会科学学院", URL(string: "http://renwen.bjfu.edu.cn/")!),
        ("外语学院", URL(string: "http://waiyu.bjfu.edu.cn/")!),
        ("信息学院", URL(string: "http://it.bjfu.edu.cn/")!),
        ("理学院", URL(string: "http://cos.bjfu.edu.cn/")!),
        ("生态与自然保护学院", URL(string: "https://styzrbh.bjfu.edu.cn")!),
        ("环境科学与工程学院", URL(string: "http://hjxy.bjfu.edu.cn/")!),
        ("艺术设计学院", URL(string: "http://ad.bjfu.edu.cn/")!),
        ("马克思主义学院", URL(string: "http://marxism.bjfu.edu.cn/")!),
        ("草业与草原学院", URL(string: "http://cxy.bjfu.edu.cn/")!),
        ("继续教育学院", URL(string: "http://jxjy.bjfu.edu.cn/")!),
        ("国际学院", URL(string: "http://ic.bjfu.edu.cn/")!)
    ]
    .map { LinkItem(title: $0.0, url: $0.1) }

    static let linkGroups: [LinkGroup] = [
        LinkGroup(title: "校园服务", links: serviceLinks),
        LinkGroup(title: "学院官网", links: collegeLinks)
    ]

    static var defaultLinks: [LinkItem] {
        linkGroups.flatMap(\.links)
    }
}

private struct CampusLinksView: View {
    @State private var isCollegeLinksExpanded = false
    @State private var browserItem: ProfileBrowserItem?

    private let serviceLinks = CampusLinkCatalog.serviceLinks
    private let collegeLinks = CampusLinkCatalog.collegeLinks

    var body: some View {
        List {
            Section("校园服务") {
                ForEach(serviceLinks, id: \.title) { link in
                    linkRow(link)
                }
            }

            Section {
                DisclosureGroup(isExpanded: $isCollegeLinksExpanded) {
                    ForEach(collegeLinks, id: \.title) { link in
                        linkRow(link)
                    }
                } label: {
                    HStack {
                        Text("学院官网")
                        Spacer()
                        Text("\(collegeLinks.count)")
                            .microCaption()
                            .foregroundStyle(AppTheme.tertiaryText)
                    }
                }
            }
        }
        .navigationTitle("常用链接")
        .leafyInlineNavigationTitle()
        .sheet(item: $browserItem) { item in
            ProfileSafariView(url: item.url)
        }
    }

    private func linkRow(_ link: CampusLinkCatalog.LinkItem) -> some View {
        Button {
            browserItem = ProfileBrowserItem(url: link.url)
        } label: {
            HStack {
                Text(link.title)
                Spacer()
                Image(systemName: "safari")
                    .foregroundStyle(AppTheme.tertiaryText)
                LeafyDisclosureIndicator()
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ProfileView()
        .environmentObject(AppNavigationCoordinator())
}
