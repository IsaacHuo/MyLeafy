import SafariServices
import SwiftUI
import SwiftData

struct PostgraduateInfoSectionView: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \PostgraduateTarget.updatedAt, order: .reverse) private var targets: [PostgraduateTarget]

    @State private var sources: [PostgraduateSource] = []
    @State private var isLoadingSources = false
    @State private var sourceError: String?
    @State private var browserItem: PostgraduateBrowserItem?
    @State private var targetSheetItem: PostgraduateTargetSheetItem?
    @State private var targetPendingDeletion: PostgraduateTarget?
    @State private var operationAlert: LeafyOperationAlert?
    @State private var expandedTimelineNodeIDs: Set<String> = []

    private var featuredSources: [PostgraduateSource] {
        PostgraduateSourcePresentation.sortedSources(for: selectedTarget, from: visibleSources)
    }

    private var activeTargets: [PostgraduateTarget] {
        PostgraduateTargetSelector.sortedActiveTargets(from: targets)
    }

    private var archivedTargets: [PostgraduateTarget] {
        PostgraduateTargetSelector.sortedArchivedTargets(from: targets)
    }

    private var selectedTarget: PostgraduateTarget? {
        PostgraduateTargetSelector.primaryTarget(from: targets)
    }

    private var timelineExamYear: Int {
        selectedTarget?.examYear ?? Calendar.current.component(.year, from: Date()) + 1
    }

    private var timelineNodes: [PostgraduateTimelineNode] {
        PostgraduateTimelineBuilder.nodes(forExamYear: timelineExamYear)
    }

    private var isCustomCampus: Bool {
        ActiveCampusContext.identity?.isCustom == true
    }

    private var visibleOfficialLinks: [PostgraduateOfficialLink] {
        Self.officialLinks.filter { link in
            !isCustomCampus || !link.isBJFUSpecific
        }
    }

    private var visibleSources: [PostgraduateSource] {
        sources.filter { source in
            !isCustomCampus || !source.isBJFUSpecific
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.card) {
            LeafySectionTitle(
                "考研信息",
                subtitle: isCustomCampus
                    ? "聚合研招网、学信网和通用公共来源，避免混入特定学校入口。"
                    : "聚合研招网、学信网、学校研究生院和已维护来源，优先解决官方入口分散和流程查找成本。"
            )

            targetsSection
            timelineSection
            officialQuerySection
            sourcesSection
        }
        .task {
            await loadRemoteData()
        }
        .sheet(item: $browserItem) { item in
            PostgraduateSafariView(url: item.url)
        }
        .sheet(item: $targetSheetItem) { item in
            PostgraduateTargetEditorSheet(item: item) { draft in
                saveTarget(draft, for: item.target)
            }
        }
        .confirmationDialog(
            "删除考研目标？",
            isPresented: Binding(
                get: { targetPendingDeletion != nil },
                set: { if !$0 { targetPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let target = targetPendingDeletion {
                    deleteTarget(target)
                }
                targetPendingDeletion = nil
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("目标只保存在本机，删除后无法恢复。")
        }
        .leafyOperationAlert($operationAlert)
    }

    private var officialQuerySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            AcademicDetailSectionHeader(title: "官方查询")
            AcademicDetailCard {
                VStack(spacing: 0) {
                    ForEach(Array(visibleOfficialLinks.enumerated()), id: \.element.id) { index, link in
                        if index > 0 {
                            AcademicDetailDivider()
                        }
                        PostgraduateOfficialLinkRow(link: link) {
                            browserItem = PostgraduateBrowserItem(url: link.url)
                        }
                    }
                }
            }
        }
    }

    private var targetsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            HStack {
                AcademicDetailSectionHeader(title: "我的考研目标")
                Spacer()
                PostgraduateSmallButton(title: "新建目标", systemName: "plus") {
                    targetSheetItem = .new
                }
            }

            if activeTargets.isEmpty {
                AcademicDetailCard {
                    PostgraduateMessageRow(
                        icon: "scope",
                        title: "先添加一个目标",
                        detail: "记录目标学校、专业和年份后，时间线和公共来源会自动围绕这个目标排序。"
                    )
                }
            } else {
                AcademicDetailCard {
                    VStack(spacing: 0) {
                        ForEach(Array(activeTargets.enumerated()), id: \.element.id) { index, target in
                            if index > 0 {
                                AcademicDetailDivider()
                            }

                            PostgraduateTargetRow(
                                target: target,
                                isSelected: target.id == selectedTarget?.id,
                                editAction: { targetSheetItem = .edit(target) },
                                focusAction: { toggleFocus(target) },
                                archiveAction: { archiveTarget(target) },
                                deleteAction: { targetPendingDeletion = target }
                            )
                        }
                    }
                }
            }

            if !archivedTargets.isEmpty {
                AcademicDetailCard {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("已归档目标")
                            .microCaption()
                            .fontWeight(.semibold)
                            .foregroundStyle(AppTheme.secondaryText)
                            .padding(.bottom, 8)

                        ForEach(Array(archivedTargets.enumerated()), id: \.element.id) { index, target in
                            if index > 0 {
                                AcademicDetailDivider()
                            }

                            PostgraduateTargetRow(
                                target: target,
                                isSelected: false,
                                editAction: { targetSheetItem = .edit(target) },
                                focusAction: { restoreTarget(target) },
                                archiveAction: { restoreTarget(target) },
                                deleteAction: { targetPendingDeletion = target }
                            )
                        }
                    }
                }
            }
        }
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            AcademicDetailSectionHeader(title: "考研时间线")
            AcademicDetailCard {
                VStack(alignment: .leading, spacing: 0) {
                    Text(timelineSubtitle)
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 8)

                    ForEach(Array(timelineNodes.enumerated()), id: \.element.id) { index, node in
                        if index > 0 {
                            AcademicDetailDivider()
                        }

                        PostgraduateTimelineRow(
                            node: node,
                            isExpanded: expandedTimelineNodeIDs.contains(node.id),
                            toggleAction: { toggleTimelineNode(node) },
                            openURL: { url in
                                browserItem = PostgraduateBrowserItem(url: url)
                            }
                        )
                    }
                }
            }
        }
    }

    private var timelineSubtitle: String {
        if let selectedTarget {
            return "按 \(selectedTarget.displayTitleForPostgraduateSection) · \(selectedTarget.examYear) 考研周期展示，具体日期以官方公告为准。"
        }
        return "默认展示 \(timelineExamYear) 考研周期；添加目标后会按目标年份和专业来源排序。"
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            HStack {
                AcademicDetailSectionHeader(title: selectedTarget == nil ? "已维护来源" : "匹配来源")
                Spacer()
                PostgraduateSmallButton(title: isLoadingSources ? "刷新中" : "刷新", systemName: "arrow.clockwise") {
                    Task { await loadRemoteData() }
                }
                .disabled(isLoadingSources)
            }

            AcademicDetailCard {
                VStack(alignment: .leading, spacing: 12) {
                    if isLoadingSources {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("正在拉取已发布来源")
                                .leafyBody()
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }

                    if let sourceError {
                        PostgraduateMessageRow(
                            icon: "wifi.exclamationmark",
                            title: "公共来源暂时不可用",
                            detail: sourceError
                        )
                    }

                    if featuredSources.isEmpty {
                        PostgraduateMessageRow(
                            icon: "checkmark.seal",
                            title: selectedTarget == nil ? "先使用官方入口" : "暂无匹配来源",
                            detail: sourceFallbackText
                        )
                    } else {
                        if let selectedTarget {
                            Text("已按 \(selectedTarget.displayTitleForPostgraduateSection) 优先排序。")
                                .microCaption()
                                .foregroundStyle(AppTheme.secondaryText)
                        }

                        VStack(spacing: 0) {
                            ForEach(Array(featuredSources.enumerated()), id: \.element.id) { index, source in
                                if index > 0 {
                                    AcademicDetailDivider()
                                }

                                PostgraduateSourceRow(source: source) { url in
                                    browserItem = PostgraduateBrowserItem(url: url)
                                }
                            }
                        }
                    }

                    Text("目标只保存在本机；公共来源来自官方或后台维护后的信息。")
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
    }

    private var sourceFallbackText: String {
        if selectedTarget != nil {
            return isCustomCampus
                ? "当前目标还没有匹配到通用公共来源，可先使用官方查询入口。"
                : "当前目标还没有匹配到已维护来源，可先使用研招网、学信网和学校研究生院入口。"
        }
        return isCustomCampus
            ? "已维护来源不可用时，仍可从上方研招网和学信网入口继续查询。"
            : "已维护来源不可用时，仍可从上方研招网、学信网和学校研究生院入口继续查询。"
    }

    private func saveTarget(_ draft: PostgraduateTargetDraft, for target: PostgraduateTarget?) {
        if let target {
            target.school = draft.school
            target.unit = draft.unit
            target.major = draft.major
            target.direction = draft.direction
            target.examYear = draft.examYear
            target.subjects = draft.subjects
            target.scoreAndPlanNote = draft.scoreAndPlanNote
            target.personalNote = draft.personalNote
            target.updatedAt = Date()
            save(successMessage: "考研目标已保存！")
        } else {
            modelContext.insert(
                PostgraduateTarget(
                    school: draft.school,
                    unit: draft.unit,
                    major: draft.major,
                    direction: draft.direction,
                    examYear: draft.examYear,
                    subjects: draft.subjects,
                    scoreAndPlanNote: draft.scoreAndPlanNote,
                    personalNote: draft.personalNote
                )
            )
            save(successMessage: "考研目标已添加！")
        }
    }

    private func toggleFocus(_ target: PostgraduateTarget) {
        if target.state == .focused {
            target.state = .active
            target.updatedAt = Date()
            save(successMessage: "已取消聚焦。")
            return
        }

        for item in targets where item.state == .focused {
            item.state = .active
            item.updatedAt = Date()
        }
        target.state = .focused
        target.updatedAt = Date()
        save(successMessage: "已设为当前看板目标。")
    }

    private func archiveTarget(_ target: PostgraduateTarget) {
        target.state = .archived
        target.updatedAt = Date()
        save(successMessage: "考研目标已归档。")
    }

    private func restoreTarget(_ target: PostgraduateTarget) {
        target.state = .active
        target.updatedAt = Date()
        save(successMessage: "考研目标已恢复。")
    }

    private func deleteTarget(_ target: PostgraduateTarget) {
        modelContext.delete(target)
        save(successMessage: "考研目标已删除。")
    }

    private func toggleTimelineNode(_ node: PostgraduateTimelineNode) {
        if expandedTimelineNodeIDs.contains(node.id) {
            expandedTimelineNodeIDs.remove(node.id)
        } else {
            expandedTimelineNodeIDs.insert(node.id)
        }
    }

    private func save(successMessage: String) {
        do {
            try modelContext.save()
            operationAlert = .success(L10n.text(successMessage, language: leafyLanguage))
        } catch {
            operationAlert = .failure(error.localizedDescription)
        }
    }

    @MainActor
    private func loadRemoteData() async {
        guard !isLoadingSources else { return }
        isLoadingSources = true
        defer { isLoadingSources = false }

        if ReviewDemoMode.isEnabled {
            sources = Self.demoSources
            sourceError = nil
            return
        }

        do {
            sources = try await PostgraduateInfoService.shared.fetchPublishedSources()
            sourceError = nil
        } catch {
            sourceError = error.localizedDescription
        }
    }
}

private struct PostgraduateOfficialLinkRow: View {
    let link: PostgraduateOfficialLink
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                LeafyIconBadge(systemName: link.icon, tint: AppTheme.accentSecondary)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 6) {
                    Text(link.title)
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)
                    Text(link.subtitle)
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "safari")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct PostgraduateTargetRow: View {
    let target: PostgraduateTarget
    let isSelected: Bool
    let editAction: () -> Void
    let focusAction: () -> Void
    let archiveAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            LeafyIconBadge(systemName: target.state.icon, tint: target.state.tint)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    PostgraduatePill(text: "\(target.examYear)", tint: AppTheme.accentSecondary)
                    PostgraduatePill(text: target.state.title, tint: target.state.tint)
                    if isSelected {
                        PostgraduatePill(text: "当前看板", tint: AppTheme.accent)
                    }
                }

                Text(target.displayTitleForPostgraduateSection)
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)
                    .multilineTextAlignment(.leading)

                if !target.targetSubtitle.isEmpty {
                    Text(target.targetSubtitle)
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !target.subjects.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(target.subjects)
                        .leafyBody()
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                if !target.scoreAndPlanNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(target.scoreAndPlanNote)
                        .microCaption()
                        .foregroundStyle(AppTheme.tertiaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                Button("编辑", systemImage: "pencil", action: editAction)
                if target.isArchived {
                    Button("恢复", systemImage: "arrow.uturn.backward", action: archiveAction)
                } else {
                    Button(target.state == .focused ? "取消聚焦" : "标记聚焦", systemImage: "star", action: focusAction)
                    Button("归档", systemImage: "archivebox", action: archiveAction)
                }
                Button(role: .destructive, action: deleteAction) {
                    Label("删除", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .frame(width: 34, height: 34)
            }
        }
        .padding(.vertical, 14)
    }
}

private struct PostgraduateTimelineRow: View {
    let node: PostgraduateTimelineNode
    let isExpanded: Bool
    let toggleAction: () -> Void
    let openURL: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggleAction) {
                timelineHeader
            }
            .buttonStyle(.plain)

            if isExpanded {
                timelineDetail
                    .padding(.leading, 44)
                    .padding(.trailing, 2)
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isExpanded)
    }

    private var timelineHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            LeafyIconBadge(systemName: node.icon, tint: node.status.tint)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    PostgraduatePill(text: node.periodText, tint: AppTheme.accentSecondary)
                    PostgraduatePill(text: node.status.title, tint: node.status.tint)
                }

                Text(node.title)
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.tertiaryText)
                .frame(width: 32, height: 32)
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private var timelineDetail: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(node.detail)
                .leafyBody()
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.leading)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Text(node.nextStep)
                .microCaption()
                .foregroundStyle(AppTheme.secondaryText)

            if let url = node.actionURL {
                Button {
                    openURL(url)
                } label: {
                    Label(node.actionTitle, systemImage: "safari")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(AppTheme.softFill, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct PostgraduateSourceRow: View {
    let source: PostgraduateSource
    let openURL: (URL) -> Void

    var body: some View {
        Button {
            if let url = source.sourceURL {
                openURL(url)
            }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                LeafyIconBadge(systemName: source.sourceKind.icon, tint: source.trustLevel.tint)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        PostgraduatePill(text: source.trustLevel.title, tint: source.trustLevel.tint)
                        PostgraduatePill(text: source.sourceKind.title, tint: AppTheme.accentSecondary)
                    }

                    Text(source.title)
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)
                        .multilineTextAlignment(.leading)

                    if !source.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(source.summary)
                            .leafyBody()
                            .foregroundStyle(AppTheme.secondaryText)
                            .multilineTextAlignment(.leading)
                            .lineSpacing(3)
                            .lineLimit(3)
                    }

                    Text(source.scopeText)
                        .microCaption()
                        .foregroundStyle(AppTheme.tertiaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "safari")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct PostgraduateMessageRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            LeafyIconBadge(systemName: icon, tint: AppTheme.accentSecondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)
                Text(detail)
                    .leafyBody()
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
    }
}

private struct PostgraduateSmallButton: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let title: String
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.system(size: 13 * leafyControlScale, weight: .semibold))
                .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                .padding(.horizontal, 10 * leafyControlScale)
                .padding(.vertical, 7 * leafyControlScale)
                .background(AppTheme.softFill, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct PostgraduatePill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .microCaption()
            .fontWeight(.semibold)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

#if canImport(UIKit)
private struct PostgraduateSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
#else
private typealias PostgraduateSafariView = LeafyExternalBrowserView
#endif

private struct PostgraduateBrowserItem: Identifiable {
    let id = UUID()
    let url: URL
}

private enum PostgraduateTargetSheetItem: Identifiable {
    case new
    case edit(PostgraduateTarget)

    var id: String {
        switch self {
        case .new:
            return "new"
        case .edit(let target):
            return target.id.uuidString
        }
    }

    var target: PostgraduateTarget? {
        switch self {
        case .new:
            return nil
        case .edit(let target):
            return target
        }
    }
}

private struct PostgraduateTargetDraft {
    var school: String
    var unit: String
    var major: String
    var direction: String
    var examYear: Int
    var subjects: String
    var scoreAndPlanNote: String
    var personalNote: String

    init(target: PostgraduateTarget? = nil) {
        school = target?.school ?? ""
        unit = target?.unit ?? ""
        major = target?.major ?? ""
        direction = target?.direction ?? ""
        examYear = target?.examYear ?? Calendar.current.component(.year, from: Date()) + 1
        subjects = target?.subjects ?? ""
        scoreAndPlanNote = target?.scoreAndPlanNote ?? ""
        personalNote = target?.personalNote ?? ""
    }

    mutating func trimWhitespace() {
        school = school.trimmingCharacters(in: .whitespacesAndNewlines)
        unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        major = major.trimmingCharacters(in: .whitespacesAndNewlines)
        direction = direction.trimmingCharacters(in: .whitespacesAndNewlines)
        subjects = subjects.trimmingCharacters(in: .whitespacesAndNewlines)
        scoreAndPlanNote = scoreAndPlanNote.trimmingCharacters(in: .whitespacesAndNewlines)
        personalNote = personalNote.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct PostgraduateTargetEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let item: PostgraduateTargetSheetItem
    let onSave: (PostgraduateTargetDraft) -> Void

    @State private var draft: PostgraduateTargetDraft

    private var isSaveDisabled: Bool {
        draft.school.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(item: PostgraduateTargetSheetItem, onSave: @escaping (PostgraduateTargetDraft) -> Void) {
        self.item = item
        self.onSave = onSave
        _draft = State(initialValue: PostgraduateTargetDraft(target: item.target))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("目标") {
                    TextField("学校", text: $draft.school)
                    TextField("院系", text: $draft.unit)
                    TextField("专业", text: $draft.major)
                    TextField("方向", text: $draft.direction)
                    Stepper("目标年份 \(draft.examYear)", value: $draft.examYear, in: 2000...2100)
                }

                Section("考试信息") {
                    TextField("考试科目", text: $draft.subjects, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("分数线、招生计划或判断依据", text: $draft.scoreAndPlanNote, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section("个人备注") {
                    TextField("备注", text: $draft.personalNote, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle(item.target == nil ? "新建考研目标" : "编辑考研目标")
            .leafyInlineNavigationTitle()
            .scrollDismissesKeyboard(.immediately)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var trimmedDraft = draft
                        trimmedDraft.trimWhitespace()
                        onSave(trimmedDraft)
                        dismiss()
                    }
                    .disabled(isSaveDisabled)
                }
            }
        }
    }
}

private struct PostgraduateOfficialLink: Identifiable {
    let title: String
    let subtitle: String
    let icon: String
    let urlString: String

    var id: String { urlString }
    var url: URL { URL(string: urlString)! }

    var isBJFUSpecific: Bool {
        let text = "\(title) \(subtitle) \(urlString)".lowercased()
        return text.contains("北京林业大学") || text.contains("bjfu")
    }
}

private extension PostgraduateInfoSectionView {
    static let officialLinks = [
        PostgraduateOfficialLink(title: "中国研究生招生信息网", subtitle: "报名、调剂、招生目录、政策公告", icon: "magnifyingglass", urlString: "https://yz.chsi.com.cn/"),
        PostgraduateOfficialLink(title: "硕士专业目录", subtitle: "查询招生单位、专业、研究方向和考试科目", icon: "list.bullet.rectangle", urlString: "https://yz.chsi.com.cn/zsml/"),
        PostgraduateOfficialLink(title: "统考网报", subtitle: "网上报名、报名信息确认与流程入口", icon: "square.and.pencil", urlString: "https://yz.chsi.com.cn/wap/yzwb/"),
        PostgraduateOfficialLink(title: "网上调剂", subtitle: "调剂意向采集和调剂服务系统入口", icon: "arrow.triangle.branch", urlString: "https://yz.chsi.com.cn/yztj/"),
        PostgraduateOfficialLink(title: "北京林业大学研究生院", subtitle: "校内通知、招生简章与复试录取信息", icon: "building.columns", urlString: "https://graduate.bjfu.edu.cn/")
    ]

    static let demoSources = [
        PostgraduateSource(
            id: UUID(),
            title: "北京林业大学 2026 年硕士研究生招生简章",
            summary: "包含招生计划、报名条件、考试安排和联系方式。",
            sourceURLString: "https://graduate.bjfu.edu.cn/",
            sourceKindRawValue: PostgraduateSourceKind.admissionNotice.rawValue,
            trustLevelRawValue: PostgraduateSourceTrustLevel.official.rawValue,
            school: "北京林业大学",
            unit: nil,
            major: nil,
            examYear: 2026,
            publishedAt: nil,
            verifiedAt: ISO8601DateFormatter().string(from: Date()),
            status: "published",
            createdAt: nil,
            updatedAt: nil
        ),
        PostgraduateSource(
            id: UUID(),
            title: "研招网硕士专业目录",
            summary: "用于核对招生单位、专业、研究方向和考试科目。",
            sourceURLString: "https://yz.chsi.com.cn/zsml/",
            sourceKindRawValue: PostgraduateSourceKind.majorCatalog.rawValue,
            trustLevelRawValue: PostgraduateSourceTrustLevel.official.rawValue,
            school: nil,
            unit: nil,
            major: nil,
            examYear: nil,
            publishedAt: nil,
            verifiedAt: ISO8601DateFormatter().string(from: Date()),
            status: "published",
            createdAt: nil,
            updatedAt: nil
        )
    ]
}

private extension PostgraduateSourceKind {
    var title: String {
        switch self {
        case .admissionNotice:
            return "招生简章"
        case .majorCatalog:
            return "专业目录"
        case .scoreLine:
            return "分数线"
        case .enrollmentPlan:
            return "招生计划"
        case .bibliography:
            return "参考书目"
        case .retest:
            return "复试"
        case .registration:
            return "报名流程"
        case .other:
            return "其他"
        }
    }

    var icon: String {
        switch self {
        case .admissionNotice:
            return "doc.text"
        case .majorCatalog:
            return "list.bullet.rectangle"
        case .scoreLine:
            return "chart.line.uptrend.xyaxis"
        case .enrollmentPlan:
            return "number"
        case .bibliography:
            return "books.vertical"
        case .retest:
            return "person.2.wave.2"
        case .registration:
            return "square.and.pencil"
        case .other:
            return "link"
        }
    }
}

private extension PostgraduateSourceTrustLevel {
    var title: String {
        switch self {
        case .official:
            return "官方"
        case .curated:
            return "维护"
        case .verifiedUser:
            return "核验"
        }
    }

    var tint: Color {
        switch self {
        case .official:
            return AppTheme.accent
        case .curated:
            return AppTheme.accentSecondary
        case .verifiedUser:
            return AppTheme.warning
        }
    }
}

private extension PostgraduateTarget {
    var displayTitleForPostgraduateSection: String {
        let parts = [school, major]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "未命名目标" : parts.joined(separator: " · ")
    }

    var targetSubtitle: String {
        [unit, direction]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

private extension PostgraduateTargetState {
    var title: String {
        switch self {
        case .active:
            return "活跃"
        case .focused:
            return "聚焦"
        case .archived:
            return "归档"
        }
    }

    var icon: String {
        switch self {
        case .active:
            return "scope"
        case .focused:
            return "star.fill"
        case .archived:
            return "archivebox"
        }
    }

    var tint: Color {
        switch self {
        case .active:
            return AppTheme.accentSecondary
        case .focused:
            return AppTheme.accent
        case .archived:
            return AppTheme.tertiaryText
        }
    }
}

private extension PostgraduateTimelineStatus {
    var title: String {
        switch self {
        case .completed:
            return "已过"
        case .current:
            return "当前"
        case .upcoming:
            return "未开始"
        }
    }

    var tint: Color {
        switch self {
        case .completed:
            return AppTheme.tertiaryText
        case .current:
            return AppTheme.warning
        case .upcoming:
            return AppTheme.accentSecondary
        }
    }
}
