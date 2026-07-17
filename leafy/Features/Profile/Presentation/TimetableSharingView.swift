import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct TimetableSharingView: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Query private var courses: [Course]
    @ObservedObject private var sessionManager = CommunitySessionManager.shared

    @State private var mySnapshot: SharedTimetableSnapshot?
    @State private var viewableSnapshots: [SharedTimetableSnapshot] = []
    @State private var members: [TimetableShareMember] = []
    @State private var invites: [TimetableInvite] = []
    @State private var generatedInvite: TimetableInvite?
    @State private var isLoading = false
    @State private var isPublishing = false
    @State private var isCreatingInvite = false
    @State private var pendingInviteCode: String?
    @State private var didPresentInitialInvite = false
    @State private var operationAlert: LeafyOperationAlert?
    @State private var showingAcceptSheet = false
    @State private var showingStopSharingConfirmation = false

    private let service = TimetableSharingService.shared
    private let initialInviteCode: String?

    init(initialInviteCode: String? = nil) {
        let normalizedCode = TimetableSharingService.normalizeInviteCode(initialInviteCode ?? "")
        self.initialInviteCode = normalizedCode.isEmpty ? nil : normalizedCode
    }

    private var canUseSharing: Bool {
        guard sessionManager.profile != nil else { return false }
        return !sessionManager.requiresProfileCompletion
    }

    private var activeInvites: [TimetableInvite] {
        let now = Date()
        return invites.filter { invite in
            invite.acceptedBy == nil && (invite.expiresDate ?? .distantPast) > now
        }
    }

    var body: some View {
        List {
            if !canUseSharing {
                Section {
                    sharingRequirementView
                }
                .listRowBackground(AppTheme.cardBackground)
            }

            Section {
                if viewableSnapshots.isEmpty {
                    Text("还没有可查看的课表。点右上角加号，粘贴对方发来的邀请码。")
                        .foregroundStyle(AppTheme.secondaryText)
                } else {
                    ForEach(viewableSnapshots) { snapshot in
                        NavigationLink {
                            SharedTimetableGridDetailView(snapshot: snapshot)
                        } label: {
                            SharedTimetableSnapshotRow(snapshot: snapshot)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await leave(snapshot) }
                            } label: {
                                Label("移除", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text("我可以查看")
            }
            .listRowBackground(AppTheme.cardBackground)

            Section {
                stepRow(index: 1, title: "发布课表", detail: "上传当前课程安排。")
                stepRow(index: 2, title: "生成邀请码", detail: "把 7 天有效的邀请码发给对方。")
                stepRow(index: 3, title: "对方接受", detail: "对方点右上角加号，粘贴邀请码。")
            } header: {
                Text("三步共享")
            } footer: {
                Text("发布后，只要你之后重新同步课表，已共享的课表数据会自动更新。")
            }
            .listRowBackground(AppTheme.cardBackground)

            Section {
                ownerStatusView

                Button {
                    Task { await publishSnapshot() }
                } label: {
                    rowLabel(
                        icon: "icloud.and.arrow.up.fill",
                        title: isPublishing ? "发布中" : "发布/更新我的课表",
                        detail: courses.isEmpty ? "本地暂无课程" : L10n.text("%d 门课程", language: leafyLanguage, courses.count)
                    )
                }
                .disabled(!canUseSharing || courses.isEmpty || isPublishing)

                Button {
                    Task { await createInvite() }
                } label: {
                    rowLabel(
                        icon: "link.badge.plus",
                        title: isCreatingInvite ? "生成中" : "生成 7 天邀请码",
                        detail: mySnapshot == nil ? "先发布课表" : "单次接受"
                    )
                }
                .disabled(!canUseSharing || mySnapshot == nil || isCreatingInvite)

                if !activeInvites.isEmpty {
                    Text(L10n.text("当前有 %d 个未使用且未过期的邀请码。出于隐私保护，旧邀请码不会再次显示明文。", language: leafyLanguage, activeInvites.count))
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                }

                if members.isEmpty {
                    Text("还没有同学可以查看你的课表。生成邀请码并发给对方，对方同意后会出现在这里。")
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                } else {
                    ForEach(members) { member in
                        TimetableShareMemberRow(member: member) {
                            Task { await revoke(member) }
                        }
                    }
                }

            } header: {
                Text("我的共享")
            } footer: {
                Text("共享课表只包含课程安排，不包含成绩、考试、备注、提醒或收藏。")
            }
            .listRowBackground(AppTheme.cardBackground)

            Section {
                Button(role: .destructive) {
                    showingStopSharingConfirmation = true
                } label: {
                    rowLabel(
                        icon: "person.2.slash.fill",
                        title: "停止共享",
                        detail: "撤销所有查看权限",
                        tint: AppTheme.danger,
                        titleColor: AppTheme.danger,
                        detailColor: AppTheme.danger
                    )
                }
                .disabled(!canUseSharing || (members.isEmpty && activeInvites.isEmpty))
            }
            .listRowBackground(AppTheme.cardBackground)

            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
                .listRowBackground(AppTheme.cardBackground)
            }
        }
        .leafyInsetGroupedListStyle()
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 760, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(LeafyPageBackground())
        .navigationTitle("共享课表")
        .toolbar {
            ToolbarItem(placement: .leafyTrailing) {
                Button {
                    pendingInviteCode = nil
                    showingAcceptSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加共享课表")
                .disabled(!canUseSharing)
            }
        }
        .task {
            await bootstrapAndLoad()
            presentInitialInviteIfNeeded()
        }
        .refreshable {
            await load()
        }
        .sheet(isPresented: $showingAcceptSheet) {
            AcceptTimetableInviteSheet(initialCode: pendingInviteCode ?? "") { snapshot in
                operationAlert = .success(L10n.text("共享课表已添加！", language: leafyLanguage))
                Task { await load() }
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $generatedInvite) { invite in
            TimetableInviteShareSheet(invite: invite, ownerName: sessionManager.profile?.limitedResolvedDisplayName ?? L10n.text(ActiveCampusContext.descriptor.defaultStudentDisplayName, language: leafyLanguage))
                .presentationDetents([.medium])
        }
        .leafyOperationAlert($operationAlert)
        .confirmationDialog("停止共享课表？", isPresented: $showingStopSharingConfirmation, titleVisibility: .visible) {
            Button("停止共享", role: .destructive) {
                Task { await stopSharing() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会撤销所有同学的查看权限，并让未使用的邀请码立即失效。已发布的课表仍只对你自己可见。")
        }
    }

    private var sharingRequirementView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                LeafyIconBadge(systemName: "person.crop.circle.badge.checkmark")
                VStack(alignment: .leading, spacing: 4) {
                    Text("需要社区身份")
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)
                    Text(L10n.text(requirementText, language: leafyLanguage))
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            if sessionManager.isBootstrapping {
                ProgressView()
            }

            if let error = sessionManager.bootstrapError {
                Text(error)
                    .microCaption()
                    .foregroundStyle(AppTheme.danger)
            }
        }
        .padding(.vertical, 6)
    }

    private var requirementText: String {
        if sessionManager.profile == nil {
            return "共享课表会使用你的社区资料展示昵称和头像。请稍等社区身份初始化完成。"
        }

        return "共享课表需要先在“我的”顶部完善社区昵称。共享页不会主动展示学号。"
    }

    private var ownerStatusView: some View {
        HStack(spacing: 12) {
            LeafyIconBadge(systemName: mySnapshot == nil ? "calendar.badge.exclamationmark" : "calendar.badge.checkmark")

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text(mySnapshot == nil ? "尚未发布课表" : "已发布课表", language: leafyLanguage))
                    .leafyBody()
                    .foregroundStyle(AppTheme.primaryText)

                Text(L10n.text(ownerStatusDetail, language: leafyLanguage))
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer()
        }
    }

    private var ownerStatusDetail: String {
        guard let mySnapshot else {
            return "发布后才能生成邀请码。"
        }

        let dateText = mySnapshot.publishedDate.map { DateFormatters.headerWithTime.string(from: $0) } ?? mySnapshot.publishedRelativeText
        return L10n.text("%d 门课程 · %@", language: leafyLanguage, mySnapshot.courseCount, dateText)
    }

    private func stepRow(index: Int, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Text("\(index)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textOnAccent)
                .frame(width: 30, height: 30)
                .background(AppTheme.accent, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.text(title, language: leafyLanguage))
                    .leafyBody()
                    .foregroundStyle(AppTheme.primaryText)
                Text(L10n.text(detail, language: leafyLanguage))
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    private func presentInitialInviteIfNeeded() {
        guard !didPresentInitialInvite,
              let initialInviteCode,
              !initialInviteCode.isEmpty else { return }

        didPresentInitialInvite = true
        pendingInviteCode = initialInviteCode
        showingAcceptSheet = true
    }

    private func rowLabel(
        icon: String,
        title: String,
        detail: String,
        tint: Color = AppTheme.accent,
        titleColor: Color = AppTheme.primaryText,
        detailColor: Color = AppTheme.secondaryText
    ) -> some View {
        HStack(spacing: 12) {
            LeafyIconBadge(systemName: icon, tint: tint)
            Text(L10n.text(title, language: leafyLanguage))
                .leafyBody()
                .foregroundStyle(titleColor)
            Spacer()
            Text(L10n.text(detail, language: leafyLanguage))
                .microCaption()
                .foregroundStyle(detailColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @MainActor
    private func bootstrapAndLoad() async {
        await sessionManager.bootstrapCommunityUser()
        await load()
    }

    @MainActor
    private func load() async {
        guard canUseSharing else { return }
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            async let snapshot = service.fetchMySnapshot()
            async let shared = service.fetchViewableSnapshots()
            async let viewerMembers = service.fetchMyShareMembers()
            async let ownerInvites = service.fetchMyInvites()

            mySnapshot = try await snapshot
            viewableSnapshots = try await shared
            members = try await viewerMembers
            invites = try await ownerInvites
        } catch {
            operationAlert = .failure(error.localizedDescription)
        }
    }

    @MainActor
    private func publishSnapshot() async {
        guard !isPublishing else { return }
        let snapshotCourses = courses.map(SharedTimetableCourse.init(course:))
        isPublishing = true
        defer { isPublishing = false }

        do {
            mySnapshot = try await service.publishSnapshot(courses: snapshotCourses)
            invites = try await service.fetchMyInvites()
            operationAlert = .success(L10n.text("课表已发布！", language: leafyLanguage))
        } catch {
            operationAlert = .failure(error.localizedDescription)
        }
    }

    @MainActor
    private func createInvite() async {
        guard !isCreatingInvite else { return }
        isCreatingInvite = true
        defer { isCreatingInvite = false }

        do {
            let invite = try await service.createInvite()
            generatedInvite = invite
            invites = try await service.fetchMyInvites()
            operationAlert = .success(L10n.text("邀请码已生成！", language: leafyLanguage))
        } catch {
            operationAlert = .failure(error.localizedDescription)
        }
    }

    @MainActor
    private func revoke(_ member: TimetableShareMember) async {
        do {
            try await service.revokeShare(viewerID: member.viewerID)
            members.removeAll { $0.id == member.id }
            operationAlert = .success(L10n.text("查看权限已撤销！", language: leafyLanguage))
        } catch {
            operationAlert = .failure(error.localizedDescription)
        }
    }

    @MainActor
    private func stopSharing() async {
        do {
            try await service.stopSharing()
            members = []
            invites = []
            operationAlert = .success(L10n.text("已停止共享！", language: leafyLanguage))
        } catch {
            operationAlert = .failure(error.localizedDescription)
        }
    }

    @MainActor
    private func leave(_ snapshot: SharedTimetableSnapshot) async {
        do {
            try await service.leaveShare(ownerID: snapshot.ownerID)
            viewableSnapshots.removeAll { $0.id == snapshot.id }
            operationAlert = .success(L10n.text("共享课表已移除！", language: leafyLanguage))
        } catch {
            operationAlert = .failure(error.localizedDescription)
        }
    }
}

private struct SharedTimetableSnapshotRow: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let snapshot: SharedTimetableSnapshot

    var body: some View {
        HStack(spacing: 12) {
            CommunityAvatarView(profile: snapshot.owner, size: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.ownerDisplayName)
                    .leafyBody()
                    .foregroundStyle(AppTheme.primaryText)
                Text(L10n.text("%d 门课程 · %@", language: leafyLanguage, snapshot.courseCount, snapshot.publishedRelativeText))
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }
}

private struct TimetableShareMemberRow: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let member: TimetableShareMember
    let revokeAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CommunityAvatarView(profile: member.viewer, size: 38)

            VStack(alignment: .leading, spacing: 4) {
                Text(member.viewerDisplayName)
                    .leafyBody()
                    .foregroundStyle(AppTheme.primaryText)
                Text(L10n.text("可以查看你的共享课表", language: leafyLanguage))
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer()

            Button(role: .destructive, action: revokeAction) {
                Text(L10n.text("撤销", language: leafyLanguage))
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderless)
        }
    }
}

private struct TimetableInviteShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyLanguage) private var leafyLanguage

    let invite: TimetableInvite
    let ownerName: String

    private var shareText: String {
        invite.shareText(ownerName: ownerName, language: leafyLanguage)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppSpacing.card) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("邀请码")
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)

                    Text(invite.code ?? "")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .textSelection(.enabled)
                        .foregroundStyle(AppTheme.primaryText)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .leafyCardStyle()

                Text("邀请码 7 天内有效，只能被一位同学接受。旧邀请码不会再次显示明文。")
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)

                HStack(spacing: 12) {
                    Button {
                        LeafyClipboard.string = invite.code
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.accent)

                    if let shareURL = invite.shareURL {
                        ShareLink(
                            item: shareURL,
                            subject: Text("\(ownerName) 的共享课表"),
                            message: Text(shareText)
                        ) {
                            Label("分享", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.accent)
                    } else {
                        ShareLink(item: shareText) {
                            Label("分享", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.accent)
                    }
                }

                Spacer()
            }
            .padding(AppSpacing.page)
            .background(LeafyPageBackground())
            .navigationTitle("分享邀请码")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct AcceptTimetableInviteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyLanguage) private var leafyLanguage

    @State private var code: String
    @State private var isAccepting = false
    @State private var errorMessage: String?

    let onAccepted: (SharedTimetableSnapshot) -> Void
    private let service = TimetableSharingService.shared

    init(initialCode: String = "", onAccepted: @escaping (SharedTimetableSnapshot) -> Void) {
        _code = State(initialValue: TimetableSharingService.normalizeInviteCode(initialCode))
        self.onAccepted = onAccepted
    }

    private var normalizedCode: String {
        TimetableSharingService.normalizeInviteCode(code)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppSpacing.card) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("输入邀请码")
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)

                    TextField("12 位邀请码", text: $code)
                        .leafyUppercaseAutocapitalization()
                        .autocorrectionDisabled()
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .padding(14)
                        .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                        .onChange(of: code) { _, newValue in
                            let normalized = TimetableSharingService.normalizeInviteCode(newValue)
                            if normalized != newValue {
                                code = normalized
                            }
                        }

                    Button {
                        if let paste = LeafyClipboard.string {
                            code = TimetableSharingService.normalizeInviteCode(paste)
                        }
                    } label: {
                        Label("粘贴邀请码", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.accent)

                    Text("接受后你可以查看对方发布的课程安排。对方可随时撤销查看权限。")
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .padding(18)
                .leafyCardStyle()

                if let errorMessage {
                    Text(errorMessage)
                        .microCaption()
                        .foregroundStyle(AppTheme.danger)
                }

                Spacer()
            }
            .padding(AppSpacing.page)
            .background(LeafyPageBackground())
            .navigationTitle("添加共享课表")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .leafyTrailing) {
                    Button(L10n.text(isAccepting ? "接受中" : "接受", language: leafyLanguage)) {
                        Task { await accept() }
                    }
                    .disabled(isAccepting || normalizedCode.count != 12)
                }
            }
        }
    }

    @MainActor
    private func accept() async {
        guard !isAccepting else { return }
        isAccepting = true
        defer { isAccepting = false }

        do {
            let snapshot = try await service.acceptInvite(code: normalizedCode)
            onAccepted(snapshot)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SharedTimetableGridDetailView: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.colorScheme) private var colorScheme
    let snapshot: SharedTimetableSnapshot

    @State private var currentWeek = SemesterConfig.currentWeek()
    @State private var scrollToWeek: Int? = SemesterConfig.currentWeek()
    @State private var isAwayFromCurrentWeek = false
    @State private var selectedCourseContext: SharedTimetableGridCourseContext?

    private let totalClasses = 13
    private var totalWeeks: Int { SemesterConfig.supportedWeeks }
    private var overviewRowSpacing: CGFloat { 1.5 * leafyControlScale }
    private var overviewCardInset: CGFloat { 1.5 * leafyControlScale }
    private var overviewMinimumRowHeight: CGFloat { 26 * leafyControlScale }
    private var overviewBottomClearance: CGFloat { 16 * leafyControlScale }
    private var axisWidth: CGFloat { 34 * leafyControlScale }
    private var headerHeight: CGFloat { 52 * leafyControlScale }
    private var timetableHorizontalPadding: CGFloat { 4 * leafyControlScale }
    private var timetableDaySpacing: CGFloat { 5 * leafyControlScale }
    private var timetableWeekSpacing: CGFloat { 6 * leafyControlScale }
    private var allowsTimetableAgendaFallback: Bool {
#if os(macOS)
        true
#else
        UIDevice.current.userInterfaceIdiom == .pad
#endif
    }
    private var visibleDayRange: ClosedRange<Int> { 1...7 }

    var body: some View {
        VStack(spacing: AppSpacing.compact) {
            if snapshot.courses.isEmpty {
                ContentUnavailableView(
                    "暂无课表",
                    systemImage: "calendar",
                    description: Text("对方发布的课表里还没有课程。")
                )
                .padding(.horizontal, AppSpacing.page)
            } else {
                timetableContent
            }
        }
        .padding(.top, AppSpacing.compact)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LeafyPageBackground())
        .navigationTitle(snapshot.ownerDisplayName)
        .leafyInlineNavigationTitle()
        .toolbar {
            ToolbarItemGroup(placement: .leafyTrailing) {
                if isAwayFromCurrentWeek {
                    toolbarReturnButton
                        .transition(returnButtonTransition)
                }
                toolbarWeekMenu
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isAwayFromCurrentWeek)
        .onAppear {
            syncReturnButtonVisibility()
        }
        .onChange(of: currentWeek) { _, newValue in
            syncReturnButtonVisibility(for: newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: .semesterRuntimeConfigDidChange)) { _ in
            applySemesterRuntimeConfig(SemesterConfig.current)
        }
        .onReceive(NotificationCenter.default.publisher(for: .nationalCalendarRuntimeConfigDidChange)) { _ in
            currentWeek = SemesterConfig.currentWeek()
        }
        .sheet(item: $selectedCourseContext) { context in
            SharedTimetableGridCourseDetailSheet(context: context)
                .presentationDetents([.medium])
        }
    }

    private var toolbarReturnButton: some View {
        Button("回到") {
            returnToCurrentWeek()
        }
    }

    private var toolbarWeekMenu: some View {
        Menu {
            ForEach(1...totalWeeks, id: \.self) { week in
                Button(weekMenuTitle(week)) {
                    currentWeek = week
                    scrollToWeek = week
                    syncReturnButtonVisibility(for: week)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(weekTitle(currentWeek))
                Image(systemName: "chevron.down")
            }
        }
    }

    private var returnButtonTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.92)),
            removal: .opacity
                .combined(with: .scale(scale: 0.92))
        )
    }

    private var timetableContent: some View {
        GeometryReader { geometry in
            let metrics = layoutMetrics(for: geometry.size)

            Group {
                switch metrics.mode {
                case .weekGrid:
                    TimetableScrollContainer(
                        axisWidth: axisWidth,
                        headerHeight: headerHeight,
                        totalWeeks: totalWeeks,
                        weekStride: metrics.weekStride,
                        dayColumnWidth: metrics.dayColumnWidth,
                        rowHeight: metrics.rowHeight,
                        rowSpacing: metrics.rowSpacing,
                        allowsVerticalScroll: metrics.allowsVerticalScroll,
                        currentWeek: $currentWeek,
                        scrollToWeek: $scrollToWeek,
                        isAwayFromCurrentWeek: $isAwayFromCurrentWeek,
                        containerID: "shared-timetable-\(snapshot.id.uuidString)",
                        corner: {
                            cornerHeader
                                .frame(width: axisWidth, height: headerHeight)
                        },
                        header: {
                            HStack(alignment: .top, spacing: metrics.weekSpacing) {
                                ForEach(1...totalWeeks, id: \.self) { week in
                                    HStack(alignment: .top, spacing: metrics.daySpacing) {
                                        ForEach(Array(visibleDayRange), id: \.self) { day in
                                            dayHeader(day: day, week: week)
                                                .frame(width: metrics.dayColumnWidth, height: headerHeight)
                                        }
                                    }
                                }
                            }
                        },
                        axis: {
                            timeAxis(metrics: metrics)
                        },
                        body: {
                            HStack(alignment: .top, spacing: metrics.weekSpacing) {
                                ForEach(1...totalWeeks, id: \.self) { week in
                                    HStack(alignment: .top, spacing: metrics.daySpacing) {
                                        ForEach(Array(visibleDayRange), id: \.self) { day in
                                            dayColumnBody(day: day, week: week, width: metrics.dayColumnWidth, metrics: metrics)
                                        }
                                    }
                                }
                            }
                            .frame(height: metrics.gridHeight, alignment: .topLeading)
                        }
                    )
                    .frame(width: metrics.containerWidth, height: metrics.containerHeight, alignment: .topLeading)
                    .padding(.horizontal, metrics.horizontalPadding)

                case .agendaList:
                    sharedAgendaList
                        .onAppear {
                            scrollToWeek = nil
                            syncReturnButtonVisibility(for: currentWeek)
                        }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
    }

    private func layoutMetrics(for size: CGSize) -> SharedTimetableGridLayoutMetrics {
        let responsiveMetrics = TimetableResponsiveLayout.metrics(
            for: size,
            dayCount: visibleDayRange.count,
            totalClasses: totalClasses,
            axisWidth: axisWidth,
            headerHeight: headerHeight,
            horizontalPadding: timetableHorizontalPadding,
            daySpacing: timetableDaySpacing,
            weekSpacing: timetableWeekSpacing,
            rowSpacing: overviewRowSpacing,
            minimumRowHeight: overviewMinimumRowHeight,
            cardInset: overviewCardInset,
            laneSpacing: 2 * leafyControlScale,
            bottomClearance: overviewBottomClearance,
            controlScale: leafyControlScale,
            interPaneSpacing: AppSpacing.micro,
            allowsAgendaList: allowsTimetableAgendaFallback
        )

        return SharedTimetableGridLayoutMetrics(
            rowHeight: responsiveMetrics.rowHeight,
            rowSpacing: responsiveMetrics.rowSpacing,
            cardInset: responsiveMetrics.cardInset,
            laneSpacing: responsiveMetrics.laneSpacing,
            dayColumnWidth: responsiveMetrics.dayColumnWidth,
            daySpacing: responsiveMetrics.daySpacing,
            weekSpacing: responsiveMetrics.weekSpacing,
            gridHeight: responsiveMetrics.gridHeight,
            allowsVerticalScroll: responsiveMetrics.allowsVerticalScroll,
            weekStride: responsiveMetrics.weekStride,
            containerWidth: responsiveMetrics.containerWidth,
            containerHeight: responsiveMetrics.containerHeight,
            horizontalPadding: responsiveMetrics.horizontalPadding,
            mode: responsiveMetrics.mode
        )
    }

    private var cornerHeader: some View {
        RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
            .fill(AppTheme.cardBackground)
            .overlay(
                Text(monthString())
                    .font(.system(size: 10 * leafyControlScale, weight: .regular))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                    .stroke(AppTheme.separator, lineWidth: 1)
            )
    }

    private func timeAxis(metrics: SharedTimetableGridLayoutMetrics) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(1...totalClasses, id: \.self) { classIndex in
                VStack(spacing: 0) {
                    Text("\(classIndex)")
                        .font(.system(size: 15 * leafyControlScale, weight: .semibold))
                    Text("节")
                        .font(.system(size: 9 * leafyControlScale, weight: .regular))
                }
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: axisWidth, height: metrics.rowHeight)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                        .fill(AppTheme.cardBackground.opacity(0.52))
                )
                .position(
                    x: axisWidth * 0.5,
                    y: yPosition(forClass: classIndex, metrics: metrics) + metrics.rowHeight * 0.5
                )
            }
        }
        .frame(width: axisWidth, height: metrics.gridHeight, alignment: .topLeading)
    }

    private func dayColumnBody(day: Int, week: Int, width: CGFloat, metrics: SharedTimetableGridLayoutMetrics) -> some View {
        let layouts = layoutsForDay(day, week: week)

        return ZStack(alignment: .topLeading) {
            timetableGridBackground(width: width, metrics: metrics)

            ForEach(layouts) { layout in
                let blockHeight = heightForCourse(layout.course, metrics: metrics)
                let blockWidth = widthForLayout(layout, availableWidth: width, metrics: metrics)

                SharedTimetableGridCourseBlockView(
                    course: layout.course,
                    height: blockHeight,
                    width: blockWidth,
                    isCompact: true
                )
                .position(
                    x: xOffsetForLayout(layout, availableWidth: width, metrics: metrics) + blockWidth * 0.5,
                    y: yOffset(for: layout.course, metrics: metrics) + blockHeight * 0.5
                )
                .onTapGesture {
                    selectedCourseContext = SharedTimetableGridCourseContext(
                        course: layout.course,
                        week: week,
                        day: day,
                        date: dateFor(dayOfWeek: day, in: week)
                    )
                }
            }
        }
        .frame(width: width, height: metrics.gridHeight, alignment: .topLeading)
    }

    private var sharedAgendaList: some View {
        VStack(spacing: AppSpacing.compact) {
            sharedAgendaHeader

            ScrollView(showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: AppSpacing.compact) {
                    ForEach(Array(visibleDayRange), id: \.self) { day in
                        sharedAgendaDaySection(day: day)
                    }
                }
                .padding(.horizontal, AppSpacing.page)
                .padding(.bottom, AppSpacing.page)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var sharedAgendaHeader: some View {
        HStack(spacing: AppSpacing.compact) {
            Button {
                moveAgendaWeek(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16 * leafyControlScale, weight: .semibold))
                    .frame(width: 40 * leafyControlScale, height: 40 * leafyControlScale)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("上一周")
            .disabled(currentWeek <= 1)

            VStack(spacing: 2 * leafyControlScale) {
                Text(weekTitle(currentWeek))
                    .font(.system(size: 17 * leafyControlScale, weight: .bold))
                    .foregroundStyle(AppTheme.primaryText)
                Text(sharedAgendaWeekRangeText)
                    .font(.system(size: 11 * leafyControlScale, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity)

            Button {
                moveAgendaWeek(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16 * leafyControlScale, weight: .semibold))
                    .frame(width: 40 * leafyControlScale, height: 40 * leafyControlScale)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("下一周")
            .disabled(currentWeek >= totalWeeks)
        }
        .padding(.horizontal, AppSpacing.page)
        .padding(.vertical, 8 * leafyControlScale)
        .background(AppTheme.cardBackground.opacity(0.82), in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                .stroke(AppTheme.separator, lineWidth: 1)
        )
        .padding(.horizontal, AppSpacing.page)
    }

    private func sharedAgendaDaySection(day: Int) -> some View {
        let date = dateFor(dayOfWeek: day, in: currentWeek)
        let courses = snapshot.courses
            .filter { $0.weeks.contains(currentWeek) && $0.dayOfWeek == day }
            .sorted { lhs, rhs in
                let leftStart = lhs.duration.min() ?? 0
                let rightStart = rhs.duration.min() ?? 0
                if leftStart == rightStart {
                    return (lhs.duration.max() ?? 0) < (rhs.duration.max() ?? 0)
                }
                return leftStart < rightStart
            }

        return VStack(alignment: .leading, spacing: 10 * leafyControlScale) {
            HStack(spacing: 8 * leafyControlScale) {
                VStack(alignment: .leading, spacing: 2 * leafyControlScale) {
                    Text(dayTitle(day))
                        .font(.system(size: 15 * leafyControlScale, weight: .bold))
                        .foregroundStyle(Calendar.current.isDateInToday(date) ? AppTheme.accentEmphasis : AppTheme.primaryText)
                    Text(DateFormatters.chineseDay.string(from: date))
                        .font(.system(size: 11 * leafyControlScale, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer()
            }

            if courses.isEmpty {
                Text("当天没有课程安排")
                    .font(.system(size: 13 * leafyControlScale, weight: .medium))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4 * leafyControlScale)
            } else {
                VStack(spacing: 8 * leafyControlScale) {
                    ForEach(courses) { course in
                        sharedAgendaCourseRow(course, day: day, date: date)
                    }
                }
            }
        }
        .padding(14 * leafyControlScale)
        .background(AppTheme.cardBackground.opacity(0.92), in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .stroke(AppTheme.separator, lineWidth: 1)
        )
    }

    private func sharedAgendaCourseRow(_ course: SharedTimetableCourse, day: Int, date: Date) -> some View {
        Button {
            selectedCourseContext = SharedTimetableGridCourseContext(
                course: course,
                week: currentWeek,
                day: day,
                date: date
            )
        } label: {
            HStack(alignment: .top, spacing: 10 * leafyControlScale) {
                VStack(spacing: 2 * leafyControlScale) {
                    Text(course.durationText(language: leafyLanguage))
                        .font(.system(size: 12 * leafyControlScale, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(courseTimeText(course))
                        .font(.system(size: 9.5 * leafyControlScale, weight: .medium))
                        .foregroundStyle(AppTheme.tertiaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .frame(width: 58 * leafyControlScale)

                VStack(alignment: .leading, spacing: 4 * leafyControlScale) {
                    Text(course.displayCourseName)
                        .font(.system(size: 14.5 * leafyControlScale, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(2)
                    Text(course.locationText)
                        .font(.system(size: 12 * leafyControlScale, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(systemName: "book.closed.fill")
                    .font(.system(size: 14 * leafyControlScale, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 24 * leafyControlScale, height: 24 * leafyControlScale)
            }
            .padding(10 * leafyControlScale)
            .background(AppTheme.accent.opacity(colorScheme == .dark ? 0.18 : 0.11), in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var sharedAgendaWeekRangeText: String {
        let start = dateFor(dayOfWeek: 1, in: currentWeek)
        let end = dateFor(dayOfWeek: 7, in: currentWeek)
        return "\(DateFormatters.chineseDay.string(from: start)) - \(DateFormatters.chineseDay.string(from: end))"
    }

    private func moveAgendaWeek(by delta: Int) {
        let nextWeek = min(max(currentWeek + delta, 1), totalWeeks)
        guard nextWeek != currentWeek else { return }
        currentWeek = nextWeek
        scrollToWeek = nextWeek
        syncReturnButtonVisibility(for: nextWeek)
    }

    private func courseTimeText(_ course: SharedTimetableCourse) -> String {
        let periods = course.duration.sorted()
        guard let first = periods.first else { return "" }
        let last = periods.last ?? first
        guard let start = TimetablePeriodSchedule.slot(for: first)?.startText else { return "" }
        guard let end = TimetablePeriodSchedule.slot(for: last)?.endText else { return start }
        return "\(start)\n\(end)"
    }

    private func dayHeader(day: Int, week: Int) -> some View {
        let date = dateFor(dayOfWeek: day, in: week)
        let today = Calendar.current.isDateInToday(date)
        let event = SchoolCalendarEvent.event(on: date)

        return VStack(spacing: 1) {
            Text(dayTitle(day))
                .font(.system(size: 12 * leafyControlScale, weight: .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .allowsTightening(true)
            Text(dateString(for: day, in: week))
                .font(.system(size: 9.5 * leafyControlScale, weight: .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
            if let event {
                Text(event.title)
                    .font(.system(size: 8.5 * leafyControlScale, weight: .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
            }
        }
        .foregroundStyle(today ? AppTheme.textOnAccent : dayHeaderForeground(event: event))
        .frame(maxWidth: .infinity, minHeight: headerHeight)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                .fill(dayHeaderFill(today: today, event: event))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                .stroke(today || event != nil ? Color.clear : AppTheme.separator, lineWidth: 1)
        )
    }

    private func timetableGridBackground(width: CGFloat, metrics: SharedTimetableGridLayoutMetrics) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(1...totalClasses, id: \.self) { classIndex in
                let isBreakBoundary = classIndex == 5 || classIndex == 9
                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                    .fill(backgroundFillColor(for: classIndex))
                    .frame(width: width, height: metrics.rowHeight)
                    .opacity(isBreakBoundary ? 1 : 0.72)
                    .position(
                        x: width * 0.5,
                        y: yPosition(forClass: classIndex, metrics: metrics) + metrics.rowHeight * 0.5
                    )
            }
        }
        .frame(width: width, height: metrics.gridHeight, alignment: .topLeading)
    }

    private func layoutsForDay(_ day: Int, week: Int) -> [SharedTimetableGridCourseLayout] {
        let dayCourses = snapshot.courses
            .filter { $0.weeks.contains(week) && $0.dayOfWeek == day }
            .sorted { lhs, rhs in
                let leftStart = lhs.duration.min() ?? 0
                let rightStart = rhs.duration.min() ?? 0
                if leftStart == rightStart {
                    return (lhs.duration.max() ?? 0) < (rhs.duration.max() ?? 0)
                }
                return leftStart < rightStart
            }

        guard !dayCourses.isEmpty else { return [] }

        var result: [SharedTimetableGridCourseLayout] = []
        var cluster: [SharedTimetableCourse] = []
        var clusterMaxEnd = 0

        func flushCluster() {
            guard !cluster.isEmpty else { return }
            result.append(contentsOf: layoutsForCluster(cluster))
            cluster.removeAll()
            clusterMaxEnd = 0
        }

        for course in dayCourses {
            let start = course.duration.min() ?? 0
            let end = course.duration.max() ?? 0

            if cluster.isEmpty {
                cluster = [course]
                clusterMaxEnd = end
                continue
            }

            if start <= clusterMaxEnd {
                cluster.append(course)
                clusterMaxEnd = max(clusterMaxEnd, end)
            } else {
                flushCluster()
                cluster = [course]
                clusterMaxEnd = end
            }
        }

        flushCluster()
        return result
    }

    private func layoutsForCluster(_ cluster: [SharedTimetableCourse]) -> [SharedTimetableGridCourseLayout] {
        var laneEndings: [Int] = []
        var placements: [(SharedTimetableCourse, Int)] = []

        for course in cluster {
            let start = course.duration.min() ?? 0
            let end = course.duration.max() ?? 0

            if let reusableLane = laneEndings.firstIndex(where: { $0 < start }) {
                laneEndings[reusableLane] = end
                placements.append((course, reusableLane))
            } else {
                laneEndings.append(end)
                placements.append((course, laneEndings.count - 1))
            }
        }

        return placements.map { course, laneIndex in
            SharedTimetableGridCourseLayout(course: course, laneIndex: laneIndex, laneCount: max(1, laneEndings.count))
        }
    }

    private func widthForLayout(_ layout: SharedTimetableGridCourseLayout, availableWidth: CGFloat, metrics: SharedTimetableGridLayoutMetrics) -> CGFloat {
        let totalSpacing = CGFloat(max(layout.laneCount - 1, 0)) * metrics.laneSpacing
        let laneWidth = (availableWidth - totalSpacing - metrics.cardInset * 2) / CGFloat(layout.laneCount)
        return max(laneWidth, 1)
    }

    private func xOffsetForLayout(_ layout: SharedTimetableGridCourseLayout, availableWidth: CGFloat, metrics: SharedTimetableGridLayoutMetrics) -> CGFloat {
        let laneWidth = widthForLayout(layout, availableWidth: availableWidth, metrics: metrics)
        return metrics.cardInset + CGFloat(layout.laneIndex) * (laneWidth + metrics.laneSpacing)
    }

    private func heightForCourse(_ course: SharedTimetableCourse, metrics: SharedTimetableGridLayoutMetrics) -> CGFloat {
        let count = max(course.duration.count, 1)
        let rawHeight = CGFloat(count) * metrics.rowHeight + CGFloat(count - 1) * metrics.rowSpacing - metrics.cardInset * 2
        return max(rawHeight, metrics.rowHeight * 0.7)
    }

    private func yOffset(for course: SharedTimetableCourse, metrics: SharedTimetableGridLayoutMetrics) -> CGFloat {
        guard let start = course.duration.min() else { return 0 }
        return yPosition(forClass: start, metrics: metrics) + metrics.cardInset
    }

    private func yPosition(forClass classIndex: Int, metrics: SharedTimetableGridLayoutMetrics) -> CGFloat {
        CGFloat(max(classIndex - 1, 0)) * (metrics.rowHeight + metrics.rowSpacing)
    }

    private func dayHeaderFill(today: Bool, event: SchoolCalendarEvent?) -> Color {
        if today { return AppTheme.accent }
        guard let event else { return AppTheme.cardBackground }

        switch event.academicCategory {
        case .winterBreak:
            return Color.cyan.opacity(colorScheme == .dark ? 0.24 : 0.18)
        case .summerBreak:
            return Color.yellow.opacity(colorScheme == .dark ? 0.24 : 0.20)
        case .importantDate, .semesterEnd:
            return AppTheme.fill.opacity(0.82)
        case .publicHoliday, nil:
            break
        }

        switch event.kind {
        case .holiday:
            return colorScheme == .dark ? AppTheme.accent.opacity(0.26) : AppTheme.accentSoft.opacity(0.72)
        case .closure:
            return AppTheme.warning.opacity(0.24)
        case .solarTerm:
            return solarTermFill(for: event)
        }
    }

    private func dayHeaderForeground(event: SchoolCalendarEvent?) -> Color {
        guard let event else { return AppTheme.primaryText }
        switch event.academicCategory {
        case .winterBreak:
            return Color.cyan.opacity(colorScheme == .dark ? 0.92 : 0.78)
        case .summerBreak:
            return Color.yellow.opacity(colorScheme == .dark ? 0.92 : 0.78)
        case .importantDate, .semesterEnd:
            return AppTheme.secondaryText
        case .publicHoliday, nil:
            break
        }
        switch event.kind {
        case .holiday:
            return AppTheme.accentEmphasis
        case .closure:
            return AppTheme.warning
        case .solarTerm:
            return solarTermForeground(for: event)
        }
    }

    private func solarTermFill(for event: SchoolCalendarEvent) -> Color {
        switch event.solarTermSeason {
        case .spring:
            return Color.green.opacity(colorScheme == .dark ? 0.22 : 0.18)
        case .summer:
            return Color.yellow.opacity(colorScheme == .dark ? 0.24 : 0.24)
        case .autumn:
            return Color.orange.opacity(colorScheme == .dark ? 0.24 : 0.20)
        case .winter:
            return Color.cyan.opacity(colorScheme == .dark ? 0.24 : 0.18)
        case nil:
            return AppTheme.fill.opacity(0.82)
        }
    }

    private func solarTermForeground(for event: SchoolCalendarEvent) -> Color {
        switch event.solarTermSeason {
        case .spring:
            return Color.green.opacity(colorScheme == .dark ? 0.92 : 0.78)
        case .summer:
            return Color.yellow.opacity(colorScheme == .dark ? 0.92 : 0.78)
        case .autumn:
            return Color.orange.opacity(colorScheme == .dark ? 0.92 : 0.82)
        case .winter:
            return Color.cyan.opacity(colorScheme == .dark ? 0.92 : 0.78)
        case nil:
            return AppTheme.secondaryText
        }
    }

    private func backgroundFillColor(for classIndex: Int) -> Color {
        if classIndex == 5 || classIndex == 9 {
            return colorScheme == .dark ? AppTheme.accent.opacity(0.18) : AppTheme.accentSoft.opacity(0.38)
        }
        return AppTheme.cardBackground.opacity(0.36)
    }

    private func syncReturnButtonVisibility(for visibleWeek: Int? = nil) {
        let week = visibleWeek ?? currentWeek
        isAwayFromCurrentWeek = week != SemesterConfig.currentWeek()
    }

    private func returnToCurrentWeek() {
        let week = SemesterConfig.currentWeek()
        currentWeek = week
        isAwayFromCurrentWeek = false
        scrollToWeek = week
    }

    private func applySemesterRuntimeConfig(_ config: SemesterRuntimeConfig) {
        let week = SemesterConfig.currentWeek(config: config)
        currentWeek = week
        isAwayFromCurrentWeek = false
        scrollToWeek = week
    }

    private func dateFor(dayOfWeek: Int, in week: Int) -> Date {
        let calendar = Calendar.current
        let startOfSemester = SemesterConfig.startOfSemesterDate
        var comp = DateComponents()
        comp.day = (week - 1) * 7 + (dayOfWeek - 1)
        return calendar.date(byAdding: comp, to: startOfSemester) ?? Date()
    }

    private func monthString() -> String {
        let date = dateFor(dayOfWeek: 1, in: currentWeek)
        let month = Calendar.current.component(.month, from: date)
        return "\(month)月"
    }

    private func weekTitle(_ week: Int) -> String {
        L10n.text("第 %d 周", language: leafyLanguage, week)
    }

    private func weekMenuTitle(_ week: Int) -> String {
        weekTitle(week) + (week == SemesterConfig.currentWeek() ? L10n.text(" (本周)", language: leafyLanguage) : "")
    }

    private func dayTitle(_ day: Int) -> String {
        leafyLanguage.weekdayTitle(for: day)
    }

    private func dateString(for dayOfWeek: Int, in week: Int) -> String {
        let components = Calendar.current.dateComponents(
            [.month, .day],
            from: dateFor(dayOfWeek: dayOfWeek, in: week)
        )
        return String(format: "%02d-%02d", components.month ?? 1, components.day ?? 1)
    }
}

private struct SharedTimetableGridLayoutMetrics: Equatable {
    let rowHeight: CGFloat
    let rowSpacing: CGFloat
    let cardInset: CGFloat
    let laneSpacing: CGFloat
    let dayColumnWidth: CGFloat
    let daySpacing: CGFloat
    let weekSpacing: CGFloat
    let gridHeight: CGFloat
    let allowsVerticalScroll: Bool
    let weekStride: CGFloat
    let containerWidth: CGFloat
    let containerHeight: CGFloat
    let horizontalPadding: CGFloat
    let mode: TimetableAdaptiveMode
}

private struct SharedTimetableGridCourseLayout: Identifiable {
    let course: SharedTimetableCourse
    let laneIndex: Int
    let laneCount: Int

    var id: UUID { course.id }
}

private struct SharedTimetableGridCourseContext: Identifiable {
    let course: SharedTimetableCourse
    let week: Int
    let day: Int
    let date: Date

    var id: String {
        "\(course.id.uuidString)-\(week)-\(day)"
    }
}

private struct SharedTimetableGridCourseBlockView: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference
    @AppStorage("appThemeColorPreference") private var appThemeColorPreferenceRaw = AppThemeColorPreference.green.rawValue

    let course: SharedTimetableCourse
    let height: CGFloat
    let width: CGFloat
    let isCompact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: contentSpacing) {
            Text(course.displayCourseName)
                .font(.system(size: courseNameFontSize, weight: isCompact ? .semibold : .regular))
                .lineSpacing(isCompact ? 0 : 2)
                .foregroundStyle(AppTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .lineLimit(isCompact ? compactCourseNameLineLimit : nil)
                .minimumScaleFactor(isCompact ? 0.82 : 1)
                .allowsTightening(isCompact)

            Text(course.locationText)
                .font(.system(size: locationFontSize, weight: isCompact ? .medium : .regular))
                .lineSpacing(isCompact ? 0 : 2)
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(isCompact ? 1 : 2)
                .minimumScaleFactor(isCompact ? 0.5 : 0.82)
                .allowsTightening(true)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(courseBackground)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(AppTheme.separator, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(
            color: Color.black.opacity(isCompact ? 0.02 : 0.05),
            radius: isCompact ? 1 : 4,
            y: isCompact ? 0 : 2
        )
        .contextMenu {
            Label(course.teacher.isEmpty ? L10n.text("未填写教师", language: leafyLanguage) : course.teacher, systemImage: "person")
            Label(course.locationText, systemImage: "mappin.and.ellipse")
            Label(course.weeksText(language: leafyLanguage), systemImage: "calendar")
        }
    }

    private var cornerRadius: CGFloat {
        isCompact ? AppRadius.small * 0.72 : AppRadius.small
    }

    private var contentSpacing: CGFloat {
        (isCompact ? 2 * compactContentScale : 6) * leafyControlScale
    }

    private var courseNameFontSize: CGFloat {
        (isCompact ? 8 * compactContentScale : 11) * leafyControlScale
    }

    private var locationFontSize: CGFloat {
        (isCompact ? 6.8 * compactContentScale : 11) * leafyControlScale
    }

    private var horizontalPadding: CGFloat {
        (isCompact ? 3.5 * compactPaddingScale : 10) * leafyControlScale
    }

    private var topPadding: CGFloat {
        (isCompact ? 5 * compactPaddingScale : 10) * leafyControlScale
    }

    private var bottomPadding: CGFloat {
        (isCompact ? 2.5 * compactPaddingScale : 10) * leafyControlScale
    }

    private var compactCourseNameLineLimit: Int {
        if height < 44 * leafyControlScale { return 1 }
        if height < 64 * leafyControlScale { return 2 }
        if height < 112 * leafyControlScale { return 3 }
        return 4
    }

    private var compactContentScale: CGFloat {
        guard isCompact else { return 1 }
        let baselineHeight = 82 * leafyControlScale
        guard height > baselineHeight else { return 1 }
        let progress = (height - baselineHeight) / max(44 * leafyControlScale, 1)
        return 1 + min(progress, 1) * 0.16
    }

    private var compactPaddingScale: CGFloat {
        min(compactContentScale, 1.12)
    }

    private var courseBackground: Color {
        if colorScheme == .dark {
            return AppTheme.accent(for: themeColorPreference).opacity(isCompact ? 0.26 : 0.3)
        }

        return AppTheme.courseCardColor(
            for: course.displayCourseName + course.teacher,
            themeColorPreferenceRaw: appThemeColorPreferenceRaw
        )
        .opacity(isCompact ? 0.82 : 0.9)
    }
}

private struct SharedTimetableGridCourseDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyLanguage) private var leafyLanguage
    let context: SharedTimetableGridCourseContext

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.course.displayCourseName)
                            .leafyHeadline()
                            .foregroundStyle(AppTheme.primaryText)
                        Text("\(context.course.dayTitle(language: leafyLanguage)) · \(context.course.durationText(language: leafyLanguage))")
                            .microCaption()
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(AppTheme.cardBackground)

                Section("课程信息") {
                    LabeledContent("教师", value: context.course.teacher.isEmpty ? "未填写" : context.course.teacher)
                    LabeledContent("地点", value: context.course.locationText)
                    LabeledContent("周次", value: context.course.weeksText(language: leafyLanguage))
                    LabeledContent("节次", value: context.course.durationText(language: leafyLanguage))
                    LabeledContent("日期", value: dateText)
                }
                .listRowBackground(AppTheme.cardBackground)
            }
            .leafyInsetGroupedListStyle()
            .scrollContentBackground(.hidden)
            .background(LeafyPageBackground())
            .navigationTitle("课程详情")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: leafyLanguage.localeIdentifier)
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: context.date)
    }
}

private struct SharedTimetableSnapshotDetailView: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    let snapshot: SharedTimetableSnapshot

    @State private var currentWeek = SemesterConfig.currentWeek()

    private var weekCourses: [SharedTimetableCourse] {
        snapshot.courses
            .filter { $0.weeks.contains(currentWeek) }
            .sorted { lhs, rhs in
                if lhs.dayOfWeek != rhs.dayOfWeek { return lhs.dayOfWeek < rhs.dayOfWeek }
                return (lhs.duration.min() ?? 0) < (rhs.duration.min() ?? 0)
            }
    }

    private var daysWithCourses: [Int] {
        Array(Set(weekCourses.map(\.dayOfWeek))).sorted()
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    CommunityAvatarView(profile: snapshot.owner, size: 52)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(snapshot.ownerDisplayName)
                            .leafyHeadline()
                            .foregroundStyle(AppTheme.primaryText)
                        Text("\(snapshot.courseCount) 门课程 · \(snapshot.publishedRelativeText)")
                            .microCaption()
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
            }
            .listRowBackground(AppTheme.cardBackground)

            if weekCourses.isEmpty {
                Section("第 \(currentWeek) 周") {
                    Text("这一周没有课程安排。")
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .listRowBackground(AppTheme.cardBackground)
            } else {
                ForEach(daysWithCourses, id: \.self) { day in
                    Section(dayTitle(day)) {
                        ForEach(weekCourses.filter { $0.dayOfWeek == day }) { course in
                            SharedTimetableCourseRow(course: course)
                        }
                    }
                    .listRowBackground(AppTheme.cardBackground)
                }
            }
        }
        .leafyInsetGroupedListStyle()
        .scrollContentBackground(.hidden)
        .background(LeafyPageBackground())
        .navigationTitle("共享课表")
        .toolbar {
            ToolbarItem(placement: .leafyTrailing) {
                Menu {
                    ForEach(1...SemesterConfig.supportedWeeks, id: \.self) { week in
                        Button(weekTitle(week)) {
                            currentWeek = week
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(weekTitle(currentWeek))
                        Image(systemName: "chevron.down")
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .semesterRuntimeConfigDidChange)) { _ in
            currentWeek = SemesterConfig.currentWeek()
        }
    }

    private func weekTitle(_ week: Int) -> String {
        L10n.text("第 %d 周", language: leafyLanguage, week)
    }

    private func dayTitle(_ day: Int) -> String {
        SharedTimetableCourse(
            courseName: "",
            teacher: "",
            room: "",
            location: "",
            dayOfWeek: day,
            weeks: [],
            duration: []
        )
        .dayTitle(language: leafyLanguage)
    }
}

private struct SharedTimetableCourseRow: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    let course: SharedTimetableCourse

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(course.displayCourseName)
                .leafyHeadline()
                .foregroundStyle(AppTheme.primaryText)

            Label(course.durationText(language: leafyLanguage), systemImage: "clock")
                .microCaption()
                .foregroundStyle(AppTheme.secondaryText)

            Label(course.locationText, systemImage: "mappin.and.ellipse")
                .microCaption()
                .foregroundStyle(AppTheme.secondaryText)

            if !course.teacher.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label(course.teacher, systemImage: "person")
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Text(course.weeksText(language: leafyLanguage))
                .microCaption()
                .foregroundStyle(AppTheme.tertiaryText)
        }
        .padding(.vertical, 4)
    }
}
