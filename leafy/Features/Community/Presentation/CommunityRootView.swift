import Combine
import OSLog
import QuickLook
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

@MainActor
final class CommunityNotificationBadgeViewModel: ObservableObject {
    @Published private(set) var unreadCount = 0

    private let repository: any CommunityNotificationRepository
    private var profileID: UUID?
    private var subscriptionID: UUID?
    private var realtimeTask: Task<Void, Never>?
    private var scheduledRefreshTask: Task<Void, Never>?

    init(repository: any CommunityNotificationRepository = LiveCommunityRepository()) {
        self.repository = repository
    }

    func start(profileID: UUID) {
        guard !CommunityDiagnosticsOptions.disablesNotifications else {
            CommunityDiagnostics.log.info("Community notification badge start skipped by diagnostics")
            stop(reset: true)
            return
        }
        guard self.profileID != profileID else { return }

        CommunityDiagnostics.log.info("Community notification badge start for profile \(profileID.uuidString, privacy: .public)")
        stop(reset: false)
        self.profileID = profileID
        let subscriptionID = UUID()
        self.subscriptionID = subscriptionID
        scheduleRefresh()
        if CommunityDiagnosticsOptions.disablesNotificationRealtime {
            CommunityDiagnostics.log.info("Community notification realtime subscription skipped by diagnostics")
        } else {
            realtimeTask = Task { @MainActor [weak self] in
                await self?.subscribeToNotificationChanges(profileID: profileID, subscriptionID: subscriptionID)
            }
        }
    }

    func stop(reset: Bool) {
        CommunityDiagnostics.log.debug("Community notification badge stop reset=\(reset, privacy: .public)")
        realtimeTask?.cancel()
        realtimeTask = nil
        scheduledRefreshTask?.cancel()
        scheduledRefreshTask = nil
        profileID = nil
        subscriptionID = nil

        if reset {
            unreadCount = 0
        }
    }

    func refresh() async {
        guard !CommunityDiagnosticsOptions.disablesNotifications else {
            unreadCount = 0
            return
        }
        guard let profileID, let subscriptionID else {
            unreadCount = 0
            return
        }

        do {
            CommunityDiagnostics.log.info("Community notification badge refresh started")
            let fetchedCount = try await CommunityTimeout.run(
                seconds: 6,
                message: L10n.text("未读通知加载超时。", language: .current)
            ) {
                try await self.repository.fetchUnreadNotificationCount()
            }
            guard !Task.isCancelled,
                  self.profileID == profileID,
                  self.subscriptionID == subscriptionID
            else { return }
            unreadCount = fetchedCount
        } catch {
            guard !Task.isCancelled else { return }
            guard self.profileID == profileID,
                  self.subscriptionID == subscriptionID
            else { return }
            CommunityDiagnostics.log.error("Community notification badge refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func scheduleRefresh() {
        scheduledRefreshTask?.cancel()
        scheduledRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    private func subscribeToNotificationChanges(profileID: UUID, subscriptionID: UUID) async {
        do {
            CommunityDiagnostics.log.info("Community notification realtime subscription starting")
            let events = await repository.notificationEvents(profileID: profileID)
            CommunityDiagnostics.log.info("Community notification realtime subscription active")
            for try await _ in events {
                guard !Task.isCancelled, self.subscriptionID == subscriptionID else { return }
                handleRealtimeChange(profileID: profileID)
            }
        } catch {
            guard !Task.isCancelled else { return }
            CommunityDiagnostics.log.error("Community notification realtime subscription failed: \(error.localizedDescription, privacy: .public)")
            await refresh()
        }
    }

    private func handleRealtimeChange(profileID: UUID) {
        guard self.profileID == profileID else { return }
        scheduleRefresh()
    }
}

struct CommunityRootView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference
    @Environment(\.leafyDependencies) private var dependencies
    @EnvironmentObject private var appNavigation: AppNavigationCoordinator
    @ObservedObject private var sessionManager = CommunitySessionManager.shared
    @State private var showingComposer = false
    @State private var showingCommunityProfileEditor = false
    @State private var showingCommunityTerms = false
    @State private var showingNotifications = false
    @State private var showingCommunitySearch = false
    @State private var selectedPost: CommunityPost?
    @State private var communityRefreshID = UUID()
    @State private var communityActionError: String?
    @State private var operationAlert: LeafyOperationAlert?
    @State private var isSubmittingSchoolRequest = false
    @State private var hasAcceptedCommunityTerms: Bool?
    @State private var isPreparingComposer = false
    @StateObject private var communityFeedViewModel = CommunityFeedViewModel()
    @ObservedObject var notificationBadgeViewModel: CommunityNotificationBadgeViewModel

    @State private var isTopicFilterPresented = false
    @State private var selectedCommunityCategory: String?
    @State private var isShowingHotPosts = false
    @State private var communityFeedContentFilter: CommunityFeedContentFilter = .all
    @State private var isCommunityFeedAtTop = true
    @State private var communityTopicFilterHeight: CGFloat = 0

    init(notificationBadgeViewModel: CommunityNotificationBadgeViewModel) {
        self.notificationBadgeViewModel = notificationBadgeViewModel
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                if CommunityDiagnosticsOptions.usesEmptyShell {
                    CommunityDiagnosticsShellView()
                        .leafyAdaptiveContentWidth(maxWidth: 560, horizontalPadding: AppSpacing.page)
                        .padding(.top, 72)
                } else if shouldShowCommunityFeed {
                    RealCommunitySectionView(
                        selectedCategory: $selectedCommunityCategory,
                        isShowingHotPosts: $isShowingHotPosts,
                        contentFilter: $communityFeedContentFilter,
                        isFeedAtTop: $isCommunityFeedAtTop,
                        selectedPost: $selectedPost,
                        hasAcceptedTerms: $hasAcceptedCommunityTerms,
                        requestProfileCompletion: {
                            showingCommunityProfileEditor = true
                        },
                        refreshID: communityRefreshID,
                        viewModel: communityFeedViewModel,
                        topContentInset: communityHeaderContentInset
                    )
                    .leafyAdaptiveContentWidth(maxWidth: 760, horizontalPadding: AppSpacing.page)

                    communityHeader
                        .zIndex(1)
                } else {
                    CommunityCampusRequestGateView(
                        profile: sessionManager.profile,
                        isBootstrapping: sessionManager.isBootstrapping,
                        bootstrapError: sessionManager.bootstrapError,
                        isSubmitting: isSubmittingSchoolRequest,
                        onSelectCampus: { campus in
                            Task { await selectInitialCampus(campus) }
                        },
                        onSubmitNewSchool: { schoolName in
                            try await submitSchoolRequest(schoolName: schoolName)
                        },
                        onRetry: {
                            Task { await sessionManager.bootstrapCommunityUser(force: true) }
                        }
                    )
                    .leafyAdaptiveContentWidth(maxWidth: 560, horizontalPadding: AppSpacing.page)
                    .padding(.top, 72)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(LeafyPageBackground())
            .tint(AppTheme.accent(for: themeColorPreference))
            .leafyNavigationBarHidden()
            .leafySheet(isPresented: $showingComposer) {
                CommunityComposerSheet { message in
                    communityRefreshID = UUID()
                    operationAlert = .success(message)
                }
                    .presentationDetents([.medium, .large])
            }
            .leafySheet(isPresented: $showingCommunityProfileEditor) {
                CommunityProfileEditorSheet()
                    .presentationDetents([.medium, .large])
            }
            .leafySheet(isPresented: $showingCommunityTerms) {
                CommunityTermsAgreementSheet {
                    hasAcceptedCommunityTerms = true
                    operationAlert = .success(L10n.text("设置已保存。", language: leafyLanguage))
                }
                    .presentationDetents([.large])
            }
            .leafySheet(isPresented: $showingCommunitySearch) {
                CommunitySearchSheet()
                    .presentationDetents([.medium, .large])
            }
            .leafySheet(isPresented: $showingNotifications) {
                CommunityNotificationsSheet(
                    repository: dependencies.communityRepository,
                    onOpenPost: { post in
                        showingNotifications = false
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(250))
                            selectedPost = post
                            await refreshUnreadNotificationCount()
                        }
                    },
                    onUnreadStateChanged: {
                        Task { @MainActor in
                            await refreshUnreadNotificationCount()
                        }
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .leafySheet(item: $selectedPost) { post in
                RealCommunityPostDetailSheet(post: post) { _ in
                    communityRefreshID = UUID()
                } onPostRemoved: {
                    selectedPost = nil
                    communityRefreshID = UUID()
                }
                    .presentationDetents([.medium, .large])
            }
            .alert(L10n.text("社区操作失败", language: leafyLanguage), isPresented: Binding(
                get: { communityActionError != nil },
                set: { if !$0 { communityActionError = nil } }
            )) {
                Button(L10n.text("知道了", language: leafyLanguage), role: .cancel) {}
            } message: {
                Text(communityActionError ?? "")
            }
            .leafyOperationAlert($operationAlert)
            .task {
                CommunityDiagnostics.log.info("CommunityRootView startup task began; options=\(CommunityDiagnosticsOptions.summary, privacy: .public)")
                guard !CommunityDiagnosticsOptions.disablesRootStartup else {
                    CommunityDiagnostics.log.info("CommunityRootView startup task skipped by diagnostics")
                    return
                }
                sessionManager.startBootstrapIfNeeded()
                guard !CommunityDiagnosticsOptions.disablesNotifications else {
                    CommunityDiagnostics.log.info("CommunityRootView notification refresh skipped by diagnostics")
                    return
                }
                Task {
                    try? await Task.sleep(for: .milliseconds(800))
                    await refreshUnreadNotificationCount()
                }
            }
            .onChange(of: showingNotifications) { _, isShowing in
                if !isShowing, !CommunityDiagnosticsOptions.disablesNotifications {
                    Task { await refreshUnreadNotificationCount() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .communityPublishTaskDidFinish)) { notification in
                if (notification.userInfo?["succeeded"] as? Bool) == true {
                    operationAlert = .success(L10n.text("帖子已发布。", language: leafyLanguage))
                } else {
                    operationAlert = .failure(
                        (notification.userInfo?["message"] as? String)
                            ?? L10n.text("帖子发布失败，可在社区顶部任务条中重试。", language: leafyLanguage)
                    )
                }
            }
            .onChange(of: appNavigation.requestedCommunityPostID) { _, postID in
                guard let postID else { return }
                Task { await openRequestedCommunityPost(id: postID) }
            }
            .onAppear {
                CommunityDiagnostics.log.info("CommunityRootView appeared")
                guard let postID = appNavigation.requestedCommunityPostID else { return }
                Task { await openRequestedCommunityPost(id: postID) }
            }
        }
    }

    private var shouldShowCommunityFeed: Bool {
        if ActiveCampusContext.descriptor.id == .bjfu && ActiveCampusContext.identity?.isCustom != true {
            return sessionManager.profile != nil
        }
        return sessionManager.hasApprovedCommunityAccess
    }

    private var communityHeaderContentInset: CGFloat {
        let baseInset = LeafyRootChromeMetrics.reservedHeight
        guard isTopicFilterPresented, isCommunityFeedAtTop else { return baseInset }
        return baseInset + communityTopicFilterHeight + LeafyRootChromeMetrics.contentSpacing
    }

    @MainActor
    private func selectInitialCampus(_ campus: CommunityCampusOption) async {
        guard !isSubmittingSchoolRequest else { return }
        isSubmittingSchoolRequest = true
        defer { isSubmittingSchoolRequest = false }

        do {
            _ = try await sessionManager.selectCommunityCampus(campusID: campus.id)
            operationAlert = .success(
                L10n.text(
                    "已加入 %@ 社区。之后如需更换学校，请在个人资料中提交审核。",
                    language: leafyLanguage,
                    campus.displayName
                )
            )
        } catch {
            communityActionError = error.localizedDescription
        }
    }

    @MainActor
    private func submitSchoolRequest(schoolName: String) async throws {
        guard !isSubmittingSchoolRequest else { return }
        isSubmittingSchoolRequest = true
        defer { isSubmittingSchoolRequest = false }

        _ = try await sessionManager.submitCampusMembershipRequest(schoolName: schoolName)
        communityActionError = nil
        operationAlert = .success(L10n.text("学校申请已提交，审核通过后会自动进入对应学校社区。", language: leafyLanguage))
    }

    private var communityHeader: some View {
        LeafyGlassGroup(spacing: 10 * leafyControlScale) {
            VStack(alignment: .leading, spacing: 8 * leafyControlScale) {
                HStack(spacing: AppSpacing.compact) {
                    communitySearchButton

                    HStack(spacing: 9) {
                        LeafyGlassIconButton(
                            systemName: isTopicFilterPresented ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle",
                            accessibilityLabel: L10n.text("筛选话题", language: leafyLanguage),
                            action: toggleTopicFilter
                        )

                        LeafyGlassIconButton(
                            systemName: "bell",
                            showsBadge: notificationBadgeViewModel.unreadCount > 0,
                            accessibilityLabel: L10n.text("通知", language: leafyLanguage),
                            action: {
                                showingNotifications = true
                            }
                        )

                        LeafyGlassIconButton(
                            systemName: "plus",
                            isLoading: isPreparingComposer,
                            accessibilityLabel: L10n.text("发布", language: leafyLanguage),
                            action: handleComposerTapped
                        )
                    }
                }
                .frame(height: LeafyRootChromeMetrics.controlDiameter)

                if isTopicFilterPresented {
                    CommunityTopicFilterBar(
                        selectedCategory: $selectedCommunityCategory,
                        isShowingHotPosts: $isShowingHotPosts,
                        contentFilter: $communityFeedContentFilter
                    )
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: CommunityTopicFilterHeightPreferenceKey.self,
                                value: geometry.size.height
                            )
                        }
                    }
                    .onPreferenceChange(CommunityTopicFilterHeightPreferenceKey.self) { height in
                        guard abs(communityTopicFilterHeight - height) > 0.5 else { return }
                        communityTopicFilterHeight = height
                    }
                    .transition(accessibilityReduceMotion
                        ? .opacity
                        : .move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, LeafyRootChromeMetrics.horizontalInset)
        .animation(
            accessibilityReduceMotion ? nil : .easeOut(duration: 0.18),
            value: isTopicFilterPresented
        )
    }

    private var communitySearchButton: some View {
        let shape = Capsule()

        return Button {
            showingCommunitySearch = true
        } label: {
            HStack(spacing: 8 * leafyControlScale) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.tertiaryText)

                Text(L10n.text("搜索帖子", language: leafyLanguage))
                    .leafyBody()
                    .foregroundStyle(AppTheme.secondaryText)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14 * leafyControlScale)
            .frame(maxWidth: .infinity)
            .frame(height: LeafyRootChromeMetrics.controlDiameter)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .contentShape(shape)
        .leafyGlassSurface(in: shape, isInteractive: true)
        .accessibilityLabel(L10n.text("搜索帖子", language: leafyLanguage))
    }

    private func toggleTopicFilter() {
        if accessibilityReduceMotion {
            isTopicFilterPresented.toggle()
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                isTopicFilterPresented.toggle()
            }
        }
    }

    private var communityAccessGate: CommunityAccessGate {
        CommunityAccessGate(
            sessionManager: sessionManager,
            termsChecker: dependencies.communityRepository
        )
    }

    private var canPresentComposerImmediately: Bool {
        hasAcceptedCommunityTerms == true
            && sessionManager.currentUserID != nil
            && !sessionManager.requiresProfileCompletion
            && sessionManager.hasApprovedCommunityAccess
    }

    @MainActor
    private func handleComposerTapped() {
        guard !isPreparingComposer else { return }
        if canPresentComposerImmediately {
            showingComposer = true
            return
        }

        isPreparingComposer = true
        Task { await prepareComposer() }
    }

    @MainActor
    private func prepareComposer() async {
        defer { isPreparingComposer = false }
        switch await communityAccessGate.evaluate(.postCreation) {
        case .allowed:
            showingComposer = true
        case .requiresProfileCompletion:
            showingCommunityProfileEditor = true
        case .requiresTermsAcceptance:
            showingCommunityTerms = true
        case .failed(let message):
            communityActionError = message
        }
    }

    @MainActor
    private func refreshUnreadNotificationCount() async {
        guard !CommunityDiagnosticsOptions.disablesNotifications else {
            notificationBadgeViewModel.stop(reset: true)
            return
        }
        await notificationBadgeViewModel.refresh()
    }

    @MainActor
    private func openRequestedCommunityPost(id postID: UUID) async {
        do {
            try await dependencies.communityRepository.ensureAnonymousSession()
            guard let post = try await dependencies.communityRepository.fetchPost(postID: postID) else {
                appNavigation.requestedCommunityPostID = nil
                communityActionError = L10n.text("帖子已不存在或不可见。", language: leafyLanguage)
                return
            }
            appNavigation.requestedCommunityPostID = nil
            selectedPost = post
        } catch {
            appNavigation.requestedCommunityPostID = nil
            communityActionError = error.localizedDescription
        }
    }
}

private struct CommunityTopicFilterHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct CommunityDiagnosticsShellView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Image(systemName: "stethoscope")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 48, height: 48)
                .background(AppTheme.accentSoft, in: Circle())

            Text("社区诊断空壳")
                .leafyHeadline()
                .foregroundStyle(AppTheme.primaryText)

            Text("已跳过社区会话、条款、Feed 和通知初始化。")
                .leafyBody()
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.section)
        .leafyCardStyle()
    }
}

private struct CommunityCampusRequestGateView: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference
    let profile: CommunityProfile?
    let isBootstrapping: Bool
    let bootstrapError: String?
    let isSubmitting: Bool
    let onSelectCampus: (CommunityCampusOption) -> Void
    let onSubmitNewSchool: (String) async throws -> Void
    let onRetry: () -> Void

    private var status: CommunityAccessStatus {
        profile?.communityAccessStatus ?? .general
    }

    private var iconName: String {
        switch status {
        case .pending:
            return "hourglass"
        case .rejected:
            return "exclamationmark.triangle"
        case .approved:
            return "checkmark.seal"
        case .general:
            return "building.2"
        }
    }

    private var title: String {
        if isBootstrapping && profile == nil {
            return L10n.text("正在同步社区身份", language: leafyLanguage)
        }
        if bootstrapError != nil && profile == nil {
            return L10n.text("社区身份同步失败", language: leafyLanguage)
        }
        switch status {
        case .pending:
            return L10n.text("学校申请审核中", language: leafyLanguage)
        case .rejected:
            return L10n.text("当前为通用模式", language: leafyLanguage)
        case .approved:
            return L10n.text("社区身份已通过", language: leafyLanguage)
        case .general:
            return L10n.text("选择学校社区", language: leafyLanguage)
        }
    }

    private var detail: String {
        if let bootstrapError, profile == nil {
            return bootstrapError
        }
        switch status {
        case .pending:
            let school = profile?.communitySchoolName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return school.isEmpty
                ? L10n.text("申请通过后会自动进入对应学校社区。", language: leafyLanguage)
                : L10n.text("%@ 的社区申请正在审核，审核通过后会自动进入学校社区。", language: leafyLanguage, school)
        case .rejected:
            return L10n.text("学校申请未通过。当前处于通用模式，社区功能暂不可用。", language: leafyLanguage)
        case .approved:
            return L10n.text("正在进入学校社区。", language: leafyLanguage)
        case .general:
            return L10n.text("通用入口可以继续使用本地学业功能；首次选择已有学校社区会立即生效，之后更换学校需要审核。", language: leafyLanguage)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.card) {
            Image(systemName: iconName)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(AppTheme.accent(for: themeColorPreference))
                .frame(width: 56, height: 56)
                .background(AppTheme.accent(for: themeColorPreference).opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: AppSpacing.micro) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if status == .rejected,
               let reason = profile?.communityRejectionReason?.trimmingCharacters(in: .whitespacesAndNewlines),
               !reason.isEmpty {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(AppSpacing.compact)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
            }

            if profile != nil && status != .pending {
                CommunityCampusSelectionPanel(
                    mode: .initial,
                    isSubmitting: isSubmitting,
                    onSelectCampus: onSelectCampus,
                    onSubmitNewSchool: onSubmitNewSchool
                )
            }

            if profile == nil, bootstrapError != nil {
                Button(L10n.text("重试同步", language: leafyLanguage)) {
                    onRetry()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBootstrapping)
            }
        }
        .padding(AppSpacing.section)
        .leafyCardStyle()
    }
}

enum CommunityCampusSelectionMode: Equatable {
    case initial
    case change(currentSchoolName: String?)

    func emptyResultMessage(language: AppLanguagePreference) -> String {
        switch self {
        case .initial:
            return L10n.text("暂时没有可直接加入的学校社区，你仍可以申请新增学校。", language: language)
        case .change:
            return L10n.text("暂时没有其他可更换的学校社区。", language: language)
        }
    }

    func confirmationTitle(language: AppLanguagePreference) -> String {
        switch self {
        case .initial:
            return L10n.text("确认加入这个学校社区？", language: language)
        case .change:
            return L10n.text("提交更换学校申请？", language: language)
        }
    }

    func confirmationMessage(for campus: CommunityCampusOption, language: AppLanguagePreference) -> String {
        switch self {
        case .initial:
            return L10n.text("你将加入“%@”社区。之后如果要更换学校，需要在个人资料中提交审核。", language: language, campus.displayName)
        case .change(let currentSchoolName):
            let current = currentSchoolName?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let current, !current.isEmpty {
                return L10n.text("你将申请从“%@”更换到“%@”。审核通过前仍保留当前学校社区。", language: language, current, campus.displayName)
            }
            return L10n.text("你将申请更换到“%@”。审核通过前不会改变当前学校社区。", language: language, campus.displayName)
        }
    }
}

struct CommunityCampusSelectionPanel: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference
    @State private var campusOptions: [CommunityCampusOption] = []
    @State private var selectedCampus: CommunityCampusOption?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var pendingConfirmation: CommunityCampusOption?
    @State private var isNewSchoolRequestPresented = false

    let mode: CommunityCampusSelectionMode
    let isSubmitting: Bool
    let onSelectCampus: (CommunityCampusOption) -> Void
    var onSubmitNewSchool: ((String) async throws -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            if let errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorMessage)
                        .microCaption()
                        .foregroundStyle(AppTheme.danger)
                    Button(L10n.text("重新加载", language: leafyLanguage)) {
                        Task { await loadCampuses() }
                    }
                    .buttonStyle(.bordered)
                }
            }

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(L10n.text("正在加载学校社区", language: leafyLanguage))
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if campusOptions.isEmpty {
                Text(mode.emptyResultMessage(language: leafyLanguage))
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            } else {
                VStack(spacing: 8) {
                    ForEach(campusOptions) { campus in
                        Button {
                            selectedCampus = campus
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(campus.displayName)
                                        .leafyBody()
                                        .foregroundStyle(AppTheme.primaryText)
                                    Text(campus.shortName)
                                        .microCaption()
                                        .foregroundStyle(AppTheme.secondaryText)
                                }
                                Spacer()
                                Image(systemName: selectedCampus?.id == campus.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedCampus?.id == campus.id ? AppTheme.accent(for: themeColorPreference) : AppTheme.tertiaryText)
                            }
                            .padding(12)
                            .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button {
                if let selectedCampus {
                    pendingConfirmation = selectedCampus
                }
            } label: {
                HStack(spacing: 8) {
                    if isSubmitting {
                        ProgressView()
                    }
                    Text(primaryActionTitle)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent(for: themeColorPreference))
            .disabled(selectedCampus == nil || isSubmitting)

            if let onSubmitNewSchool {
                Button {
                    isNewSchoolRequestPresented = true
                } label: {
                    Label(L10n.text("申请新增学校", language: leafyLanguage), systemImage: "building.2.crop.circle.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isSubmitting)
                .leafySheet(isPresented: $isNewSchoolRequestPresented) {
                    CommunityNewSchoolRequestSheet(onSubmit: onSubmitNewSchool)
                        .presentationDetents([.medium, .large])
                }
            }
        }
        .task {
            await loadCampuses()
        }
        .confirmationDialog(
            mode.confirmationTitle(language: leafyLanguage),
            isPresented: Binding(
                get: { pendingConfirmation != nil },
                set: { if !$0 { pendingConfirmation = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingConfirmation
        ) { campus in
            Button(primaryActionTitle) {
                pendingConfirmation = nil
                onSelectCampus(campus)
            }
            Button(L10n.text("取消", language: leafyLanguage), role: .cancel) {
                pendingConfirmation = nil
            }
        } message: { campus in
            Text(mode.confirmationMessage(for: campus, language: leafyLanguage))
        }
    }

    private var primaryActionTitle: String {
        switch mode {
        case .initial:
            return L10n.text("确认加入学校社区", language: leafyLanguage)
        case .change:
            return L10n.text("提交更换申请", language: leafyLanguage)
        }
    }

    @MainActor
    private func loadCampuses() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            campusOptions = try await CommunitySessionManager.shared.searchCommunityCampuses(
                query: "",
                limit: 50
            )
            errorMessage = nil
        } catch {
            campusOptions = []
            errorMessage = error.localizedDescription
        }
    }
}

private struct CommunityNewSchoolRequestSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyLanguage) private var leafyLanguage
    @FocusState private var isSchoolNameFocused: Bool

    let onSubmit: (String) async throws -> Void

    @State private var schoolName = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var trimmedSchoolName: String {
        schoolName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.text("学校全称", language: leafyLanguage), text: $schoolName)
                        .leafyDisableAutocapitalization()
                        .autocorrectionDisabled()
                        .focused($isSchoolNameFocused)
                } footer: {
                    Text(L10n.text("请填写学校官方全称。提交后需要管理员审核，审核通过后会自动进入对应学校社区。", language: leafyLanguage))
                }

                if let errorMessage {
                    Section(L10n.text("提交失败", language: leafyLanguage)) {
                        Text(errorMessage)
                            .foregroundStyle(AppTheme.danger)
                    }
                }
            }
            .navigationTitle(L10n.text("申请新增学校", language: leafyLanguage))
            .leafyInlineNavigationTitle()
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("取消", language: leafyLanguage)) {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text(L10n.text("提交申请", language: leafyLanguage))
                        }
                    }
                    .disabled(trimmedSchoolName.isEmpty || isSubmitting)
                }
            }
            .onAppear {
                isSchoolNameFocused = true
            }
        }
    }

    @MainActor
    private func submit() async {
        guard !trimmedSchoolName.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            try await onSubmit(trimmedSchoolName)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
