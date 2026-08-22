import Charts
import PhotosUI
import QuickLook
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

extension ScheduleDestination {
    var title: String {
        switch self {
        case .memos: return "全部随记"
        case .scheduleHub: return "日程"
        case .customSchedules: return "我的日程"
        case .dailyReview: return "每日回顾"
        case .tags: return "标签"
        case .export: return "导出随记"
        case .statistics: return "记录日迹"
        case .scheduleReports: return "日程推送"
        case .trash: return "回收站"
        case .timetableProcessing: return "课表处理"
        }
    }

    var systemImage: String {
        switch self {
        case .memos: return "square.grid.2x2"
        case .scheduleHub: return "calendar.day.timeline.left"
        case .customSchedules: return "calendar.badge.plus"
        case .dailyReview: return "sparkles"
        case .tags: return "number"
        case .export: return "square.and.arrow.up"
        case .statistics: return "chart.bar.xaxis"
        case .scheduleReports: return "bell.badge"
        case .trash: return "trash"
        case .timetableProcessing: return "slider.horizontal.3"
        }
    }
}

enum SchedulePrimaryContentPresentation: Equatable {
    case standalone
    case daytraceRoot
}

enum ScheduleRootTopBarLayout: Equatable {
    case regular
    case combinedActions
    case stacked

    static func resolve(viewportWidth: CGFloat, usesAccessibilitySizes: Bool) -> Self {
        if usesAccessibilitySizes {
            return .stacked
        }
        return viewportWidth <= 350 ? .combinedActions : .regular
    }

}

struct ScheduleRootView: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var scaledPickerHeight = LeafyRootChromeMetrics.controlDiameter
    @EnvironmentObject private var appNavigation: AppNavigationCoordinator
    @State private var compactPath: [ScheduleDestination] = []
    @State private var primarySection: SchedulePrimarySection = .memos
    @State private var showsMenu = false
    @State private var newSchedulePresentation: CustomScheduleEditorPresentation?

    var body: some View {
        NavigationStack(path: $compactPath) {
            primaryView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(LeafyPageBackground())
                .leafyNavigationBarHidden()
                .safeAreaInset(edge: .top, spacing: 0) {
                    rootTopBar
                }
                .navigationDestination(for: ScheduleDestination.self) { destination in
                    destinationView(destination)
                        .leafyNavigationBarVisible()
                }
        }
        .leafySheet(isPresented: $showsMenu) {
            NavigationStack {
                ScheduleSidebar(selection: Binding(
                    get: { nil },
                    set: { destination in
                        guard let destination else { return }
                        showsMenu = false
                        openDestination(destination)
                    }
                ), presentation: .modal)
            }
            .presentationDetents([.medium, .large])
        }
        .leafySheet(item: $newSchedulePresentation) { presentation in
            CustomScheduleEditorSheet(presentation: presentation)
                .presentationDetents([.medium, .large])
        }
        .onAppear { consumeRequestedDestination() }
        .onChange(of: appNavigation.requestedScheduleDestination) { _, _ in
            consumeRequestedDestination()
        }
    }

    private var primaryView: some View {
        ZStack {
            ScheduleMemoFeedView(presentation: .daytraceRoot)
                .opacity(primarySection == .memos ? 1 : 0)
                .allowsHitTesting(primarySection == .memos)
                .accessibilityHidden(primarySection != .memos)

            if primarySection == .schedules {
                CustomScheduleListView(presentation: .daytraceRoot)
                    .transition(.opacity)
            } else if primarySection == .reports {
                ScheduleReportsView(presentation: .daytraceRoot)
                    .transition(.opacity)
            }
        }
    }

    private var rootTopBar: some View {
        GeometryReader { geometry in
            let layout = ScheduleRootTopBarLayout.resolve(
                viewportWidth: geometry.size.width,
                usesAccessibilitySizes: dynamicTypeSize.isAccessibilitySize
            )

            Group {
                switch layout {
                case .regular:
                    HStack(spacing: AppSpacing.compact) {
                        rootMenuButton
                        Spacer(minLength: 0)
                        rootSectionPicker(expands: false, usesCompactLabels: false)
                        Spacer(minLength: 0)
                        rootNewScheduleButton
                    }
                case .combinedActions:
                    HStack(spacing: AppSpacing.compact) {
                        rootCombinedActionsMenu
                        rootSectionPicker(expands: true, usesCompactLabels: true)
                    }
                case .stacked:
                    VStack(spacing: AppSpacing.compact) {
                        HStack {
                            rootMenuButton
                            Spacer()
                            rootNewScheduleButton
                        }
                        rootSectionPicker(expands: true, usesCompactLabels: false)
                    }
                }
            }
            .padding(.horizontal, LeafyRootChromeMetrics.horizontalInset)
        }
        .frame(height: rootTopBarHeight)
    }

    private var rootTopBarHeight: CGFloat {
        guard dynamicTypeSize.isAccessibilitySize else {
            return LeafyRootChromeMetrics.controlDiameter
        }
        return LeafyRootChromeMetrics.controlDiameter
            + AppSpacing.compact
            + max(scaledPickerHeight, LeafyRootChromeMetrics.controlDiameter)
    }

    private var rootMenuButton: some View {
        LeafyRootCircularToolbarButton(
            systemName: "line.3.horizontal",
            accessibilityLabel: L10n.text("打开日迹记录菜单", language: leafyLanguage)
        ) {
            showsMenu = true
        }
    }

    private var rootNewScheduleButton: some View {
        LeafyRootCircularToolbarButton(
            systemName: "plus",
            accessibilityLabel: L10n.text("添加自定日程", language: leafyLanguage)
        ) {
            presentNewSchedule()
        }
    }

    private var rootCombinedActionsMenu: some View {
        Menu {
            Button(
                L10n.text("打开日迹记录菜单", language: leafyLanguage),
                systemImage: "line.3.horizontal"
            ) {
                showsMenu = true
            }
            Button(
                L10n.text("添加自定日程", language: leafyLanguage),
                systemImage: "calendar.badge.plus"
            ) {
                presentNewSchedule()
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: LeafyRootChromeMetrics.iconPointSize, weight: .semibold))
                .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                .frame(
                    width: LeafyRootChromeMetrics.controlDiameter,
                    height: LeafyRootChromeMetrics.controlDiameter
                )
                .contentShape(Circle())
                .leafyGlassSurface(in: Circle(), isInteractive: true)
        }
        .accessibilityLabel(L10n.text("日迹操作", language: leafyLanguage))
    }

    private func rootSectionPicker(expands: Bool, usesCompactLabels: Bool) -> some View {
        primarySectionButtons(expands: expands, usesCompactLabels: usesCompactLabels)
            .padding(4)
            .fixedSize(horizontal: !expands, vertical: false)
            .frame(maxWidth: expands ? .infinity : nil)
            .frame(minHeight: dynamicTypeSize.isAccessibilitySize
                ? max(scaledPickerHeight, LeafyRootChromeMetrics.controlDiameter)
                : LeafyRootChromeMetrics.controlDiameter)
            .leafyGlassSurface(
                in: Capsule(),
                fallbackFill: Color(uiColor: .secondarySystemBackground),
                isInteractive: true
            )
            .layoutPriority(1)
    }

    private func primarySectionButtons(expands: Bool, usesCompactLabels: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(SchedulePrimarySection.allCases) { section in
                Button {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                        primarySection = section
                    }
                } label: {
                    Text(L10n.text(section.title, language: leafyLanguage))
                        .font(.body.weight(primarySection == section ? .semibold : .regular))
                        .foregroundStyle(
                            primarySection == section
                                ? AppTheme.accentEmphasis(for: themeColorPreference)
                                : AppTheme.primaryText
                        )
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .minimumScaleFactor(usesCompactLabels ? 0.85 : 1)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, usesCompactLabels ? 4 : 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .zIndex(1)
                .accessibilityAddTraits(primarySection == section ? .isSelected : [])
            }
        }
    }

    private func presentNewSchedule() {
        newSchedulePresentation = .importantDate(
            nil,
            defaultContext: CustomScheduleDefaultContext.make(),
            allowsModeSelection: true
        )
    }

    @ViewBuilder
    private func destinationView(_ destination: ScheduleDestination) -> some View {
        switch destination {
        case .memos:
            ScheduleMemoFeedView()
                .navigationTitle("日迹")
        case .scheduleHub:
            CustomScheduleListView()
        case .customSchedules:
            CustomScheduleListView()
        case .dailyReview:
            ScheduleMemoReviewView()
        case .tags:
            ScheduleMemoTagsView()
        case .export:
            ScheduleMemoExportView()
        case .statistics:
            ScheduleMemoStatisticsView()
        case .scheduleReports:
            ScheduleReportsView()
        case .trash:
            ScheduleMemoTrashView()
        case .timetableProcessing:
            TimetableProcessingView()
        }
    }

    private func openDestination(_ destination: ScheduleDestination) {
        switch destination {
        case .memos:
            primarySection = .memos
        case .scheduleHub, .customSchedules:
            primarySection = .schedules
        case .scheduleReports:
            primarySection = .reports
        default:
            compactPath.append(destination)
        }
    }

    private func consumeRequestedDestination() {
        guard let destination = appNavigation.requestedScheduleDestination else { return }
        compactPath.removeAll()
        openDestination(destination)
        appNavigation.requestedScheduleDestination = nil
    }
}

private enum SchedulePrimarySection: String, CaseIterable, Identifiable {
    case memos
    case schedules
    case reports

    var id: String { rawValue }

    var title: String {
        switch self {
        case .memos: return "随记"
        case .schedules: return "日程"
        case .reports: return "推送"
        }
    }
}

private struct ScheduleSidebar: View {
    enum Presentation: Equatable {
        case sidebar
        case modal
    }

    @Binding var selection: ScheduleDestination?
    var presentation: Presentation = .sidebar
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Query private var memos: [ScheduleMemo]
    @State private var selectedStatisticsDate: Date?

    var body: some View {
        Group {
            if presentation == .modal {
                sidebarList
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(AppTheme.modalBackground)
            } else {
                sidebarList
                    .listStyle(.sidebar)
            }
        }
        .leafySheet(isPresented: Binding(
            get: { selectedStatisticsDate != nil },
            set: { if !$0 { selectedStatisticsDate = nil } }
        )) {
            NavigationStack {
                ScheduleMemoDayView(date: selectedStatisticsDate ?? Date())
            }
        }
    }

    private var sidebarList: some View {
        List(selection: $selection) {
            if presentation == .modal {
                Section {
                    ScheduleMemoStatisticsSummary(
                        statistics: .make(memos: memos),
                        compact: true,
                        onSelectDate: { selectedStatisticsDate = $0 }
                    )
                    .listRowInsets(EdgeInsets(
                        top: AppSpacing.section,
                        leading: AppSpacing.page,
                        bottom: AppSpacing.compact,
                        trailing: AppSpacing.page
                    ))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }

            Section("记录") {
                if presentation != .modal {
                    row(.memos)
                }
                row(.statistics)
                row(.dailyReview)
                row(.tags)
                row(.export)
                row(.trash)
            }
        }
    }

    private func row(_ destination: ScheduleDestination) -> some View {
        Label(L10n.text(destination.title, language: leafyLanguage), systemImage: destination.systemImage)
            .tag(destination)
            .contentShape(Rectangle())
            .onTapGesture { selection = destination }
            .accessibilityAddTraits(selection == destination ? .isSelected : [])
    }
}

private enum ScheduleMemoFilter: String, CaseIterable, Identifiable {
    case all
    case withImages
    case linked

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "全部"
        case .withImages: return "有图片"
        case .linked: return "已关联日程"
        }
    }
}

struct ScheduleMemoMediaIndex {
    let imagesByMemoID: [UUID: [ScheduleMemoImage]]
    let attachmentsByMemoID: [UUID: [ScheduleMemoAttachment]]
    let audioByMemoID: [UUID: ScheduleMemoAudio]

    init(
        images: [ScheduleMemoImage],
        attachments: [ScheduleMemoAttachment],
        audioRecords: [ScheduleMemoAudio]
    ) {
        imagesByMemoID = Dictionary(grouping: images, by: \.memoID).mapValues {
            $0.sorted { $0.sortOrder < $1.sortOrder }
        }
        attachmentsByMemoID = Dictionary(grouping: attachments, by: \.memoID).mapValues {
            $0.sorted { $0.sortOrder < $1.sortOrder }
        }
        audioByMemoID = Dictionary(grouping: audioRecords, by: \.memoID).compactMapValues(\.first)
    }
}

private enum ScheduleMemoFeedPresentationItem: Identifiable {
    case memo(ScheduleMemo)
    case schedule(PersonalScheduleFeedItem)

    var id: String {
        switch self {
        case .memo(let memo): return "memo-\(memo.id.uuidString)"
        case .schedule(let schedule): return schedule.id
        }
    }

    var createdAt: Date {
        switch self {
        case .memo(let memo): return memo.createdAt
        case .schedule(let schedule): return schedule.createdAt
        }
    }

    var updatedAt: Date {
        switch self {
        case .memo(let memo): return memo.updatedAt
        case .schedule(let schedule): return schedule.updatedAt
        }
    }

    var isPinned: Bool {
        guard case .memo(let memo) = self else { return false }
        return memo.isPinned
    }
}

struct ScheduleMemoFeedView: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.modelContext) private var modelContext
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference
    @Environment(\.openURL) private var openURL
    @Query private var memos: [ScheduleMemo]
    @Query private var images: [ScheduleMemoImage]
    @Query private var attachments: [ScheduleMemoAttachment]
    @Query private var audioRecords: [ScheduleMemoAudio]
    @Query private var reminders: [TimetableCellReminder]
    @State private var searchText = ""
    @State private var selectedTag: String?
    @State private var filter: ScheduleMemoFilter = .all
    @State private var sort: ScheduleMemoSort = .newest
    @State private var editingMemo: ScheduleMemo?
    @State private var convertingMemo: ScheduleMemo?
    @State private var editingSchedulePresentation: CustomScheduleEditorPresentation?
    @State private var shareCardSource: ScheduleMemoShareCardPreviewSource?
    @State private var submissionFallback: ScheduleMemoSubmissionDraft?
    @State private var importantDates = CustomScheduleStore.load()
    @State private var detailMemo: ScheduleMemo?
    @State private var composerHeight: CGFloat = 0
    @State private var presentedAlert: ScheduleMemoFeedAlert?
    @State private var searchRevealHeight: CGFloat = 1
    @State private var searchRevealProgress: CGFloat = 0
    @State private var daytraceScrollPosition: ScheduleMemoFeedAnchor?
    @State private var hasPositionedDaytraceFeed = false
    @State private var isPositioningDaytraceFeed = false
    @StateObject private var audioPlayback = ScheduleMemoAudioPlaybackController()

    private let initialTag: String?
    private let presentation: SchedulePrimaryContentPresentation

    init(
        initialTag: String? = nil,
        presentation: SchedulePrimaryContentPresentation = .standalone
    ) {
        self.initialTag = initialTag
        self.presentation = presentation
        _selectedTag = State(initialValue: initialTag)
    }

    private func visibleFeedItems(using mediaIndex: ScheduleMemoMediaIndex) -> [ScheduleMemoFeedPresentationItem] {
        let byID = Dictionary(uniqueKeysWithValues: memos.map { ($0.id, $0) })
        let records = memos.map { memo in
            ScheduleMemoSearchRecord(
                id: memo.id,
                title: memo.title ?? "",
                body: memo.body,
                tags: memo.tags,
                attachmentNames: mediaIndex.attachmentsByMemoID[memo.id, default: []]
                    .map(\.originalFilename),
                createdAt: memo.createdAt,
                updatedAt: memo.updatedAt,
                pinnedAt: memo.pinnedAt,
                isTrashed: memo.isTrashed,
                imageCount: mediaIndex.imagesByMemoID[memo.id, default: []].count,
                isLinked: memo.linkedScheduleKind != nil && memo.linkedScheduleID != nil
            )
        }
        let visibleMemos = ScheduleMemoSearchEngine.results(
            in: records,
            query: searchText,
            tag: selectedTag,
            requiresImages: filter == .withImages,
            requiresLink: filter == .linked,
            sort: sort
        ).compactMap { byID[$0.id] }

        var items = visibleMemos.map(ScheduleMemoFeedPresentationItem.memo)
        let linkedScheduleKeys = Set(memos.compactMap { memo -> String? in
            guard !memo.isTrashed,
                  let kind = memo.linkedScheduleKind,
                  let stableID = memo.linkedScheduleID else { return nil }
            return "\(kind.rawValue):\(stableID)"
        })

        if selectedTag == nil, filter != .withImages {
            let reminderItems = reminders.compactMap { reminder -> PersonalScheduleFeedItem? in
                guard let createdAt = reminder.createdAt,
                      let startsAt = reminder.resolvedStartDate,
                      !linkedScheduleKeys.contains("\(ScheduleMemoLinkKind.timetableReminder.rawValue):\(reminder.id.uuidString)")
                else { return nil }
                let endsAt = reminder.resolvedEndDate ?? startsAt.addingTimeInterval(45 * 60)
                return PersonalScheduleFeedItem(
                    source: .timetableReminder(reminder.id),
                    title: reminder.title,
                    note: reminder.noteText,
                    location: reminder.locationText,
                    startsAt: startsAt,
                    endsAt: endsAt,
                    createdAt: createdAt,
                    updatedAt: reminder.updatedAt,
                    minutesBefore: reminder.minutesBefore
                )
            }
            let importantDateItems = importantDates.compactMap { event -> PersonalScheduleFeedItem? in
                guard let createdAt = event.createdAt,
                      !linkedScheduleKeys.contains("\(ScheduleMemoLinkKind.importantDate.rawValue):\(event.id)")
                else { return nil }
                return PersonalScheduleFeedItem(
                    source: .importantDate(event.id),
                    title: event.title,
                    note: event.noteText,
                    location: event.locationText,
                    startsAt: event.startsAt,
                    endsAt: event.endsAt ?? event.startsAt.addingTimeInterval(45 * 60),
                    createdAt: createdAt,
                    updatedAt: event.updatedAt ?? createdAt,
                    minutesBefore: event.minutesBefore
                )
            }
            items.append(contentsOf: (reminderItems + importantDateItems)
                .filter { $0.matches(searchText) }
                .map(ScheduleMemoFeedPresentationItem.schedule))
        }

        return items.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            switch sort {
            case .newest: return lhs.createdAt > rhs.createdAt
            case .oldest: return lhs.createdAt < rhs.createdAt
            case .recentlyUpdated: return lhs.updatedAt > rhs.updatedAt
            }
        }
    }

    var body: some View {
        let mediaIndex = ScheduleMemoMediaIndex(
            images: images,
            attachments: attachments,
            audioRecords: audioRecords
        )
        configuredFeed(using: mediaIndex)
        .leafySheet(item: $editingMemo) { memo in
            if memo.kind == .audio {
                ScheduleMemoEditorView(memo: memo)
            } else {
                ScheduleMemoAdvancedEditorView(memo: memo)
            }
        }
        .leafySheet(item: $convertingMemo) { memo in
            CustomScheduleEditorSheet(
                presentation: .importantDate(
                    nil,
                    defaultContext: defaultTimetableContext(),
                    prefillTitle: memoTitle(memo.body),
                    prefillNote: memo.body
                ),
                onSaved: { reference in
                    memo.linkedScheduleKind = reference.kind
                    memo.linkedScheduleID = reference.stableID
                    memo.updatedAt = Date()
                    try? modelContext.save()
                    importantDates = CustomScheduleStore.load()
                }
            )
        }
        .leafySheet(item: $editingSchedulePresentation, onDismiss: {
            importantDates = CustomScheduleStore.load()
        }) { presentation in
            CustomScheduleEditorSheet(presentation: presentation)
                .presentationDetents([.medium, .large])
        }
        .leafySheet(item: $shareCardSource) { source in
            ScheduleMemoShareCardPreviewSheet(source: source)
        }
        .navigationDestination(isPresented: Binding(
            get: { detailMemo != nil },
            set: { if !$0 { detailMemo = nil } }
        )) {
            if let detailMemo {
                ScheduleMemoDetailView(
                    memo: detailMemo,
                    images: mediaIndex.imagesByMemoID[detailMemo.id, default: []],
                    attachments: mediaIndex.attachmentsByMemoID[detailMemo.id, default: []],
                    audio: mediaIndex.audioByMemoID[detailMemo.id],
                    audioPlayback: audioPlayback,
                    linkedSchedule: linkedSchedule(for: detailMemo),
                    onEdit: { editingMemo = detailMemo },
                    onConvert: { convertingMemo = detailMemo },
                    onShareCard: { makeShareCard(for: detailMemo) },
                    onSubmit: { submit(detailMemo) },
                    onPin: { togglePin(detailMemo) },
                    onTrash: {
                        requestTrash(detailMemo, closesDetail: true)
                    }
                )
                .leafyNavigationBarVisible()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .customScheduleEventsDidChange)) { _ in
            importantDates = CustomScheduleStore.load()
        }
        .alert(item: $presentedAlert) { alert in
            switch alert {
            case .trash(let request):
                Alert(
                    title: Text("移到回收站？"),
                    message: Text("这条随记会移到回收站，你可以稍后恢复。"),
                    primaryButton: .destructive(Text("移到回收站")) {
                        confirmTrash(request)
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            case .failure(_, let message):
                Alert(
                    title: Text("操作失败"),
                    message: Text(message),
                    dismissButton: .default(Text("知道了"))
                )
            }
        }
        .confirmationDialog(
            "无法打开邮箱 App",
            isPresented: Binding(
                get: { submissionFallback != nil },
                set: { if !$0 { submissionFallback = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let draft = submissionFallback {
                Button("复制投稿内容") {
                    UIPasteboard.general.string = draft.body
                    submissionFallback = nil
                }
                Button("复制投稿邮箱") {
                    UIPasteboard.general.string = ScheduleMemoSubmissionDraft.recipient
                    submissionFallback = nil
                }
            }
            Button("取消", role: .cancel) { submissionFallback = nil }
        } message: {
            Text("请复制投稿内容，稍后发送至 \(ScheduleMemoSubmissionDraft.recipient)。")
        }
    }

    @ViewBuilder
    private func configuredFeed(using mediaIndex: ScheduleMemoMediaIndex) -> some View {
        if presentation == .daytraceRoot {
            daytraceRootFeed(using: mediaIndex)
        } else {
            memoScrollView(using: mediaIndex)
                .background(LeafyPageBackground())
                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "搜索随记"
                )
                .safeAreaInset(edge: .bottom) {
                    ScheduleMemoComposer()
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        filterMenu
                    }
                }
        }
    }

    @ViewBuilder
    private func daytraceRootFeed(using mediaIndex: ScheduleMemoMediaIndex) -> some View {
        memoScrollView(using: mediaIndex)
            .background(LeafyPageBackground())
            .scheduleMemoComposerOverlay(height: $composerHeight)
    }

    private func memoScrollView(using mediaIndex: ScheduleMemoMediaIndex) -> some View {
        GeometryReader { viewport in
            ScrollView {
                VStack(spacing: 0) {
                    if presentation == .daytraceRoot {
                        searchFilterBar
                            .padding(.top, AppSpacing.compact)
                            .opacity(hasPositionedDaytraceFeed ? searchRevealProgress : 0)
                            .allowsHitTesting(
                                hasPositionedDaytraceFeed && searchRevealProgress >= 0.99
                            )
                            .accessibilityHidden(
                                !hasPositionedDaytraceFeed || searchRevealProgress < 0.99
                            )
                            .background {
                                GeometryReader { geometry in
                                    let frame = geometry.frame(
                                        in: .named(ScheduleMemoFeedCoordinateSpace.scroll)
                                    )
                                    Color.clear.preference(
                                        key: ScheduleMemoSearchRevealGeometryPreferenceKey.self,
                                        value: ScheduleMemoSearchRevealGeometry(
                                            height: geometry.size.height,
                                            minY: frame.minY
                                        )
                                    )
                                }
                            }
                            .id(ScheduleMemoFeedAnchor.search)

                        Color.clear
                            .frame(height: AppSpacing.card)
                            .id(ScheduleMemoFeedAnchor.cardsStart)
                    }

                    memoCards(using: mediaIndex)
                        .leafyAdaptiveContentWidth(maxWidth: 760)
                }
                .scrollTargetLayout()
                .frame(
                    minHeight: viewport.size.height
                        + (presentation == .daytraceRoot ? searchRevealHeight : 0),
                    alignment: .top
                )
                .padding(.bottom, AppSpacing.card)
            }
            .coordinateSpace(name: ScheduleMemoFeedCoordinateSpace.scroll)
            .scrollPosition(id: $daytraceScrollPosition, anchor: .top)
            .scrollTargetBehavior(ScheduleMemoSearchRevealTargetBehavior(
                isEnabled: presentation == .daytraceRoot,
                revealHeight: searchRevealHeight
            ))
            .scrollBounceBehavior(.always, axes: .vertical)
            .opacity(presentation == .daytraceRoot && !hasPositionedDaytraceFeed ? 0 : 1)
            .onPreferenceChange(ScheduleMemoSearchRevealGeometryPreferenceKey.self) { geometry in
                guard presentation == .daytraceRoot, geometry.height > 0 else { return }

                if abs(searchRevealHeight - geometry.height) > 0.5 {
                    searchRevealHeight = geometry.height
                }

                let progress = min(
                    max((geometry.minY + geometry.height) / geometry.height, 0),
                    1
                )
                if abs(searchRevealProgress - progress) > 0.001 {
                    searchRevealProgress = progress
                }

                guard !hasPositionedDaytraceFeed, !isPositioningDaytraceFeed else { return }
                isPositioningDaytraceFeed = true
                Task { @MainActor in
                    await Task.yield()
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        searchRevealProgress = 0
                        daytraceScrollPosition = .cardsStart
                    }
                    await Task.yield()
                    hasPositionedDaytraceFeed = true
                    isPositioningDaytraceFeed = false
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func memoCards(using mediaIndex: ScheduleMemoMediaIndex) -> some View {
        let visibleItems = visibleFeedItems(using: mediaIndex)
        return LazyVStack(spacing: AppSpacing.card) {
            filterSummary
            if visibleItems.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "还没有随记" : "没有找到随记",
                    systemImage: searchText.isEmpty ? "square.and.pencil" : "magnifyingglass",
                    description: Text(searchText.isEmpty ? "在下方快速记下一句话、一个想法或一张图片。" : "试试清除筛选或换一个关键词。")
                )
                .padding(.top, 72)
            } else {
                ForEach(visibleItems) { item in
                    switch item {
                    case .memo(let memo):
                        ScheduleMemoCard(
                            memo: memo,
                            images: mediaIndex.imagesByMemoID[memo.id, default: []],
                            attachments: mediaIndex.attachmentsByMemoID[memo.id, default: []],
                            audio: mediaIndex.audioByMemoID[memo.id],
                            audioPlayback: audioPlayback,
                            linkedSchedule: linkedSchedule(for: memo),
                            onOpen: { detailMemo = memo },
                            onTag: { selectedTag = $0 },
                            onEdit: { editingMemo = memo },
                            onConvert: { convertingMemo = memo },
                            onShareCard: { makeShareCard(for: memo) },
                            onSubmit: { submit(memo) },
                            onPin: { togglePin(memo) },
                            onTrash: { requestTrash(memo) }
                        )
                    case .schedule(let schedule):
                        PersonalScheduleMemoCard(schedule: schedule) {
                            openScheduleEditor(for: schedule)
                        }
                    }
                }
            }

            if presentation == .daytraceRoot {
                Color.clear
                    .frame(height: composerHeight + AppSpacing.card)
                    .accessibilityHidden(true)
            }
        }
    }

    private var searchFilterBar: some View {
        LeafyGlassGroup(spacing: AppSpacing.compact) {
            HStack(spacing: AppSpacing.compact) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryText)

                    TextField("搜索随记", text: $searchText)
                        .font(.body)
                        .submitLabel(.search)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AppTheme.tertiaryText)
                                .frame(width: 32, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清除搜索")
                    }
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 44)
                .leafyGlassSurface(
                    in: Capsule(),
                    fallbackFill: Color(uiColor: .secondarySystemBackground),
                    isInteractive: true
                )

                filterMenu
                    .leafyGlassSurface(
                        in: Circle(),
                        fallbackFill: Color(uiColor: .secondarySystemBackground),
                        isInteractive: true
                    )
            }
        }
        .padding(.horizontal, AppSpacing.page)
    }

    private var filterMenu: some View {
        Menu {
            Picker("筛选", selection: $filter) {
                ForEach(ScheduleMemoFilter.allCases) {
                    Text(L10n.text($0.title, language: leafyLanguage)).tag($0)
                }
            }
            Picker("排序", selection: $sort) {
                ForEach(ScheduleMemoSort.allCases) {
                    Text(L10n.text($0.title, language: leafyLanguage)).tag($0)
                }
            }
        } label: {
            Image(systemName: filter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("筛选与排序")
    }

    @ViewBuilder
    private var filterSummary: some View {
        let showsSelectedTag = selectedTag != nil && selectedTag != initialTag
        if showsSelectedTag || filter != .all {
            HStack(spacing: 8) {
                if let selectedTag, showsSelectedTag {
                    Text("#\(selectedTag)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(
                            AppTheme.accent(for: themeColorPreference),
                            in: Capsule()
                        )

                    Button {
                        self.selectedTag = nil
                    } label: {
                        Label("全部随记", systemImage: "arrow.uturn.backward")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                    }
                    .buttonStyle(.plain)
                    .leafyCapsuleChipSurface(isSelected: false)
                }
                if filter != .all {
                    Button {
                        filter = .all
                    } label: {
                        Text("\(L10n.text(filter.title, language: leafyLanguage))  ×")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                    }
                    .buttonStyle(.plain)
                    .leafyCapsuleChipSurface(isSelected: true)
                }
                Spacer()
            }
        }
    }

    private func linkedSchedule(for memo: ScheduleMemo) -> ScheduleMemoLinkedSchedule? {
        guard let kind = memo.linkedScheduleKind,
              let stableID = memo.linkedScheduleID else { return nil }

        switch kind {
        case .timetableReminder:
            guard let reminder = reminders.first(where: { $0.id.uuidString == stableID }) else {
                return .missing
            }
            return ScheduleMemoLinkedSchedule(
                title: reminder.title,
                startsAt: reminder.resolvedStartDate,
                endsAt: reminder.resolvedEndDate,
                location: reminder.locationText,
                isMissing: false
            )
        case .importantDate:
            guard let event = importantDates.first(where: { $0.id == stableID }) else {
                return .missing
            }
            return ScheduleMemoLinkedSchedule(
                title: event.title,
                startsAt: event.startsAt,
                endsAt: event.endsAt,
                location: event.locationText,
                isMissing: false
            )
        }
    }

    private func openScheduleEditor(for schedule: PersonalScheduleFeedItem) {
        switch schedule.source {
        case .timetableReminder(let id):
            guard let reminder = reminders.first(where: { $0.id == id }) else { return }
            let context = TimetableCellReminderContext(
                week: reminder.week,
                day: reminder.dayOfWeek,
                period: reminder.displayStartPeriod,
                date: reminder.resolvedStartDate ?? schedule.startsAt,
                occupiedPeriods: [],
                totalPeriods: TimetablePeriodSchedule.slots.count,
                reminder: reminder,
                allowsDateSelection: true
            )
            editingSchedulePresentation = .timetable(context, allowsModeSelection: false)
        case .importantDate(let id):
            guard let event = importantDates.first(where: { $0.id == id }) else { return }
            editingSchedulePresentation = .importantDate(
                event,
                defaultContext: defaultTimetableContext(for: event.startsAt),
                allowsModeSelection: false
            )
        }
    }

    private func memoImages(for memo: ScheduleMemo) -> [ScheduleMemoImage] {
        images.filter { $0.memoID == memo.id }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func memoAttachments(for memo: ScheduleMemo) -> [ScheduleMemoAttachment] {
        attachments.filter { $0.memoID == memo.id }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func memoAudio(for memo: ScheduleMemo) -> ScheduleMemoAudio? {
        audioRecords.first { $0.memoID == memo.id }
    }

    private func makeShareCard(for memo: ScheduleMemo) {
        do {
            shareCardSource = ScheduleMemoShareCardPreviewSource(
                snapshot: try ScheduleMemoShareCardSnapshot.make(
                    memo: memo,
                    images: memoImages(for: memo),
                    attachments: memoAttachments(for: memo)
                )
            )
        } catch {
            presentedAlert = .failure(id: UUID(), message: error.localizedDescription)
        }
    }

    private func submit(_ memo: ScheduleMemo) {
        let draft = ScheduleMemoSubmissionDraft.make(
            title: memo.kind == .article ? memo.title : nil,
            source: memo.body,
            tags: memo.tags,
            createdAt: memo.createdAt,
            updatedAt: memo.updatedAt,
            attachmentNames: Dictionary(uniqueKeysWithValues: memoAttachments(for: memo).map {
                ($0.id, $0.originalFilename)
            })
        )
        guard let url = draft.mailtoURL else {
            submissionFallback = draft
            return
        }
        openURL(url) { accepted in
            guard !accepted else { return }
            Task { @MainActor in submissionFallback = draft }
        }
    }

    private func togglePin(_ memo: ScheduleMemo) {
        memo.pinnedAt = memo.pinnedAt == nil ? Date() : nil
        memo.updatedAt = Date()
        try? modelContext.save()
    }

    private func requestTrash(_ memo: ScheduleMemo, closesDetail: Bool = false) {
        Task { @MainActor in
            await Task.yield()
            presentedAlert = .trash(.init(memo: memo, closesDetail: closesDetail))
        }
    }

    private func confirmTrash(_ request: ScheduleMemoTrashRequest) {
        do {
            if let audio = memoAudio(for: request.memo), audioPlayback.currentAudioID == audio.id {
                audioPlayback.stop()
            }
            try ScheduleMemoDeletionService.moveToTrash(request.memo, in: modelContext)
            if request.closesDetail, detailMemo?.id == request.memo.id {
                detailMemo = nil
            }
        } catch {
            Task { @MainActor in
                await Task.yield()
                presentedAlert = .failure(id: UUID(), message: error.localizedDescription)
            }
        }
    }
}

private enum ScheduleMemoFeedAnchor: Hashable {
    case search
    case cardsStart
}

private enum ScheduleMemoFeedCoordinateSpace: Hashable {
    case scroll
}

private struct ScheduleMemoSearchRevealGeometry: Equatable {
    var height: CGFloat = 0
    var minY: CGFloat = 0
}

private struct ScheduleMemoSearchRevealGeometryPreferenceKey: PreferenceKey {
    static var defaultValue = ScheduleMemoSearchRevealGeometry()

    static func reduce(
        value: inout ScheduleMemoSearchRevealGeometry,
        nextValue: () -> ScheduleMemoSearchRevealGeometry
    ) {
        let next = nextValue()
        if next.height > 0 {
            value = next
        }
    }
}

private struct ScheduleMemoSearchRevealTargetBehavior: ScrollTargetBehavior {
    let isEnabled: Bool
    let revealHeight: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard isEnabled, revealHeight > 1 else { return }

        let proposedY = target.rect.minY
        guard proposedY < revealHeight else { return }

        let clampedY = min(max(proposedY, 0), revealHeight)
        target.rect.origin.y = clampedY < revealHeight / 2 ? 0 : revealHeight
        target.anchor = .top
    }
}

private enum ScheduleMemoFeedAlert: Identifiable {
    case trash(ScheduleMemoTrashRequest)
    case failure(id: UUID, message: String)

    var id: String {
        switch self {
        case .trash(let request):
            return "trash-\(request.id.uuidString)"
        case .failure(let id, _):
            return "failure-\(id.uuidString)"
        }
    }
}

private struct ScheduleMemoTrashRequest: Identifiable {
    let memo: ScheduleMemo
    let closesDetail: Bool

    var id: UUID { memo.id }
}

struct ScheduleMemoLinkedSchedule {
    let title: String
    let startsAt: Date?
    let endsAt: Date?
    let location: String
    let isMissing: Bool

    static let missing = ScheduleMemoLinkedSchedule(
        title: "原日程已删除",
        startsAt: nil,
        endsAt: nil,
        location: "",
        isMissing: true
    )

    private var deadline: Date? { endsAt ?? startsAt }

    var countdownText: String? {
        guard !isMissing, let deadline else { return nil }
        guard deadline > Date() else { return "已截止" }
        return CountdownEventRow.countdownDescription(for: deadline)
    }

    var deadlineText: String? {
        guard !isMissing, let deadline else { return nil }
        return "截止 \(DateFormatters.headerWithTime.string(from: deadline))"
    }
}

private struct ScheduleMemoCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let memo: ScheduleMemo
    let images: [ScheduleMemoImage]
    let attachments: [ScheduleMemoAttachment]
    let audio: ScheduleMemoAudio?
    let audioPlayback: ScheduleMemoAudioPlaybackController
    let linkedSchedule: ScheduleMemoLinkedSchedule?
    let onOpen: (() -> Void)?
    let onTag: ((String) -> Void)?
    let onEdit: (() -> Void)?
    let onConvert: (() -> Void)?
    let onShareCard: (() -> Void)?
    let onSubmit: () -> Void
    let onPin: (() -> Void)?
    let onTrash: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if memo.kind == .article {
                Text(memo.displayTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if linkedSchedule == nil, !memo.body.isEmpty {
                Text(ScheduleMemoMarkdownParser.plainText(from: memo.body))
                    .leafyBody()
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(memo.kind == .article ? 3 : 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ScheduleMemoPhotoStrip(images: images, layout: .feed)

            if let audio {
                ScheduleMemoAudioPlayerBar(audio: audio, controller: audioPlayback)
            }

            if !attachments.isEmpty {
                VStack(spacing: 6) {
                    ForEach(attachments) { attachment in
                        ScheduleMemoAttachmentRow(attachment: attachment, isInteractive: false)
                    }
                }
            }

            if !memo.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(memo.tags, id: \.self) { tag in
                            Group {
                                if let onTag {
                                    Button { onTag(tag) } label: { tagLabel(tag) }
                                        .buttonStyle(.plain)
                                } else {
                                    tagLabel(tag)
                                }
                            }
                            .background(
                                AppTheme.accent(for: themeColorPreference),
                                in: Capsule()
                            )
                        }
                    }
                }
            }

            if let linkedSchedule {
                linkedScheduleSummary(linkedSchedule)
            }

            HStack(spacing: 8) {
                if memo.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityLabel("已置顶")
                }
                Text(memo.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .microCaption()
                    .foregroundStyle(AppTheme.tertiaryText)
                Spacer()
                actionsMenu
            }
        }
        .padding(.top, 14)
        .padding(.horizontal, 14)
        .padding(.bottom, 7)
        .background(
            AppTheme.cardElevated,
            in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                .stroke(AppTheme.separator, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        .onTapGesture { onOpen?() }
        .accessibilityHint(onOpen == nil ? "" : "打开随记详情")
    }

    private var actionsMenu: some View {
        Menu {
            if let onPin {
                Button(memo.isPinned ? "取消置顶" : "置顶", systemImage: "pin", action: onPin)
            }
            if let onEdit {
                Button("编辑", systemImage: "pencil", action: onEdit)
            }
            if let onConvert {
                Button(linkedSchedule == nil ? "转为日程" : "重新创建日程", systemImage: "calendar.badge.plus", action: onConvert)
            }
            if memo.kind != .audio, let onShareCard {
                Button("转为图文卡片", systemImage: "rectangle.on.rectangle.angled", action: onShareCard)
            }
            Button("投稿", systemImage: "envelope", action: onSubmit)
            if let onTrash {
                Button("移到回收站", systemImage: "trash", role: .destructive, action: onTrash)
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("随记操作")
    }

    private func tagLabel(_ tag: String) -> some View {
        Text("#\(tag)")
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Capsule())
    }

    private func linkedScheduleSummary(_ schedule: ScheduleMemoLinkedSchedule) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(
                    schedule.title,
                    systemImage: schedule.isMissing ? "link.badge.plus" : "calendar.badge.clock"
                )
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(schedule.isMissing ? AppTheme.warning : AppTheme.primaryText)

                Spacer(minLength: 8)

                if let countdownText = schedule.countdownText {
                    Text(countdownText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accentEmphasis)
                }
            }

            if let deadlineText = schedule.deadlineText {
                HStack(spacing: 10) {
                    Label(deadlineText, systemImage: "clock")
                    if !schedule.location.isEmpty {
                        Label(schedule.location, systemImage: "mappin")
                            .lineLimit(1)
                    }
                }
                .microCaption()
                .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            AppTheme.accent(for: themeColorPreference)
                .opacity(colorScheme == .dark ? 0.12 : 0.07),
            in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
        )
    }
}

private struct ScheduleMemoPhotoStrip: View {
    enum Layout {
        case feed
        case detail
    }

    let images: [ScheduleMemoImage]
    let layout: Layout

    @ViewBuilder
    var body: some View {
        if !images.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: AppSpacing.micro) {
                    ForEach(Array(images.prefix(ScheduleMemoImageStore.maximumImageCount))) { imageRecord in
                        photoCell(imageRecord)
                    }
                }
            }
        }
    }

    private var cellLength: CGFloat {
        switch layout {
        case .feed: 104
        case .detail: 140
        }
    }

    private func photoCell(_ imageRecord: ScheduleMemoImage) -> some View {
        Group {
            if let image = ScheduleMemoImageStore.image(named: imageRecord.localFilename) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .frame(width: cellLength, height: cellLength)
        .background(AppTheme.softFill)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .clipped()
        .accessibilityLabel("随记图片")
    }
}

private struct ScheduleMemoAttachmentRow: View {
    let attachment: ScheduleMemoAttachment
    var isInteractive = true

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "doc")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.accent)
            Text(attachment.originalFilename)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(AppTheme.primaryText)
            Spacer(minLength: 6)
            if isInteractive {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 38)
        .background(AppTheme.cardBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct PersonalScheduleMemoCard: View {
    let schedule: PersonalScheduleFeedItem
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(schedule.title, systemImage: "calendar.badge.clock")
                        .font(.headline)
                        .foregroundStyle(AppTheme.primaryText)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.tertiaryText)
                }

                if !schedule.note.isEmpty {
                    Text(schedule.note)
                        .leafyBody()
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label(dateRangeText, systemImage: "clock")
                    if !schedule.location.isEmpty {
                        Label(schedule.location, systemImage: "mappin")
                            .lineLimit(1)
                    }
                    if schedule.minutesBefore > 0 {
                        Label("提前 \(schedule.minutesBefore) 分钟提醒", systemImage: "bell.fill")
                    }
                }
                .microCaption()
                .foregroundStyle(AppTheme.secondaryText)

                Text("创建于 \(schedule.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .microCaption()
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            .padding(.top, 14)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppTheme.cardElevated,
                in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                    .stroke(AppTheme.separator, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("打开日程编辑")
    }

    private var dateRangeText: String {
        let start = DateFormatters.headerWithTime.string(from: schedule.startsAt)
        let end = DateFormatters.headerWithTime.string(from: schedule.endsAt)
        return "\(start) - \(end)"
    }
}

private struct ScheduleMemoPreviewFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ScheduleMemoDetailView: View {
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let memo: ScheduleMemo
    let images: [ScheduleMemoImage]
    let attachments: [ScheduleMemoAttachment]
    let audio: ScheduleMemoAudio?
    let audioPlayback: ScheduleMemoAudioPlaybackController
    let linkedSchedule: ScheduleMemoLinkedSchedule?
    let onEdit: () -> Void
    let onConvert: () -> Void
    let onShareCard: () -> Void
    let onSubmit: () -> Void
    let onPin: () -> Void
    let onTrash: () -> Void

    @State private var previewFile: ScheduleMemoPreviewFile?

    private var markdownResources: ScheduleMemoMarkdownResourceSet {
        var imageMap: [UUID: UIImage] = [:]
        for image in images {
            if let value = ScheduleMemoImageStore.image(named: image.localFilename) {
                imageMap[image.id] = value
            }
        }
        return .init(
            images: imageMap,
            imageOrder: images.map(\.id),
            attachmentNames: Dictionary(uniqueKeysWithValues: attachments.map { ($0.id, $0.originalFilename) }),
            attachmentOrder: attachments.map(\.id)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.card) {
                if memo.kind == .article {
                    Text(memo.displayTitle)
                        .font(.largeTitle.bold())
                        .foregroundStyle(AppTheme.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if memo.kind == .audio, !memo.body.isEmpty {
                    Text(memo.body)
                        .leafyBody()
                        .foregroundStyle(AppTheme.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                } else if memo.kind != .audio {
                    ScheduleMemoRichMarkdownView(
                        source: memo.body,
                        resources: markdownResources,
                        onOpenAttachment: { id in
                            guard let attachment = attachments.first(where: { $0.id == id }),
                                  let url = ScheduleMemoAttachmentStore.fileURL(for: attachment) else { return }
                            previewFile = .init(url: url)
                        }
                    )
                }

                if let audio {
                    ScheduleMemoAudioPlayerBar(audio: audio, controller: audioPlayback)
                }

                if let linkedSchedule {
                    VStack(alignment: .leading, spacing: 7) {
                        Label(linkedSchedule.title, systemImage: "bell.fill")
                            .font(.headline)
                        if let deadline = linkedSchedule.deadlineText {
                            Text(deadline)
                                .microCaption()
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        if !linkedSchedule.location.isEmpty {
                            Label(linkedSchedule.location, systemImage: "mappin")
                                .microCaption()
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        AppTheme.accent(for: themeColorPreference).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                    )
                }

                Divider()
                Text(memo.createdAt.formatted(date: .long, time: .shortened))
                    .microCaption()
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            .leafyAdaptiveContentWidth(maxWidth: 720)
            .padding(.vertical, AppSpacing.card)
        }
        .background(LeafyPageBackground())
        .navigationTitle("随记详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) {
                    detailActionsMenu
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    detailActionsMenu
                }
            }
        }
        .leafySheet(item: $previewFile) { file in
            NavigationStack {
                ScheduleMemoDocumentPreview(url: file.url)
                    .navigationTitle(file.url.lastPathComponent)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private var detailActionsMenu: some View {
        Menu {
            Button("编辑", systemImage: "pencil", action: onEdit)
            Button(linkedSchedule == nil ? "转为日程" : "重新创建日程", systemImage: "calendar.badge.plus", action: onConvert)
            if memo.kind != .audio {
                Button("生成图文卡片", systemImage: "rectangle.on.rectangle.angled", action: onShareCard)
            }
            Button(memo.isPinned ? "取消置顶" : "置顶", systemImage: "pin", action: onPin)
            Button("投稿", systemImage: "envelope", action: onSubmit)
            Button("移到回收站", systemImage: "trash", role: .destructive, action: onTrash)
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .leafyGlassSurface(in: Circle(), isInteractive: true)
        }
        .buttonStyle(.plain)
        .buttonBorderShape(.circle)
        .accessibilityLabel("随记详情操作")
    }
}

private struct ScheduleMemoDraftImage: Identifiable {
    let id = UUID()
    let data: Data
    let image: UIImage
    let pickerItem: PhotosPickerItem?

    init(data: Data, image: UIImage, pickerItem: PhotosPickerItem? = nil) {
        self.data = data
        self.image = image
        self.pickerItem = pickerItem
    }
}

private struct ScheduleMemoDraftAttachment: Identifiable {
    let id = UUID()
    let originalFilename: String
    let typeIdentifier: String
    let data: Data
}

private struct ScheduleMemoComposerHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ScheduleMemoComposerOverlayModifier: ViewModifier {
    @Binding var height: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { viewport in
                    ScheduleMemoComposer(availableHeight: viewport.size.height)
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: ScheduleMemoComposerHeightPreferenceKey.self,
                                    value: proxy.size.height
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
            .onPreferenceChange(ScheduleMemoComposerHeightPreferenceKey.self) { newHeight in
                guard abs(height - newHeight) > 0.5 else { return }
                height = newHeight
            }
    }
}

private extension View {
    func scheduleMemoComposerOverlay(height: Binding<CGFloat>) -> some View {
        modifier(ScheduleMemoComposerOverlayModifier(height: height))
    }
}

private enum ScheduleMemoComposerError: LocalizedError {
    case tooManyAttachments

    var errorDescription: String? {
        "每条随记最多添加 3 个附件。"
    }
}

private enum ScheduleMemoComposerAddDestination: Equatable {
    case camera
    case photoLibrary
    case audioRecording
    case fileImporter
}

private nonisolated enum ScheduleMemoComposerPresentation: Equatable {
    case compact
    case expanded
    case fullscreen
}

private struct ScheduleMemoComposerTextHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ScheduleMemoComposerControlLayout: Layout {
    let presentation: ScheduleMemoComposerPresentation
    let expandedEditorHeight: CGFloat

    private let compactSpacing: CGFloat = 4
    private let toolbarSpacing: CGFloat = 8
    private let controlSize: CGFloat = 44
    private let trailingControlSpacing: CGFloat = 2

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let fallback = CGSize(width: 320, height: desiredHeight)
        let proposedSize = proposal.replacingUnspecifiedDimensions(by: fallback)
        return CGSize(width: proposedSize.width, height: presentation == .fullscreen ? proposedSize.height : desiredHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard subviews.count == 4 else { return }

        if presentation == .compact {
            placeCompactSubviews(in: bounds, subviews: subviews)
        } else {
            placeExpandedSubviews(in: bounds, subviews: subviews)
        }
    }

    private var desiredHeight: CGFloat {
        presentation == .compact ? controlSize : expandedEditorHeight + toolbarSpacing + controlSize
    }

    private func placeCompactSubviews(in bounds: CGRect, subviews: Subviews) {
        let addButtonX = bounds.minX
        let editorX = addButtonX + controlSize + compactSpacing
        let sendButtonX = bounds.maxX - controlSize
        let microphoneX = sendButtonX - trailingControlSpacing - controlSize
        let editorWidth = max(microphoneX - compactSpacing - editorX, 1)
        let y = bounds.minY + max((bounds.height - controlSize) / 2, 0)

        subviews[0].place(
            at: CGPoint(x: addButtonX, y: y),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: controlSize, height: controlSize)
        )
        subviews[1].place(
            at: CGPoint(x: editorX, y: y),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: editorWidth, height: controlSize)
        )
        subviews[2].place(
            at: CGPoint(x: microphoneX, y: y),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: controlSize, height: controlSize)
        )
        subviews[3].place(
            at: CGPoint(x: sendButtonX, y: y),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: controlSize, height: controlSize)
        )
    }

    private func placeExpandedSubviews(in bounds: CGRect, subviews: Subviews) {
        let toolbarY = bounds.maxY - controlSize
        let editorHeight = max(toolbarY - toolbarSpacing - bounds.minY, 1)
        let sendButtonX = bounds.maxX - controlSize
        let microphoneX = sendButtonX - trailingControlSpacing - controlSize

        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: toolbarY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: controlSize, height: controlSize)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: editorHeight)
        )
        subviews[2].place(
            at: CGPoint(x: microphoneX, y: toolbarY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: controlSize, height: controlSize)
        )
        subviews[3].place(
            at: CGPoint(x: sendButtonX, y: toolbarY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: controlSize, height: controlSize)
        )
    }
}

private struct ScheduleMemoInlinePhotoPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference
    @State private var transaction: ScheduleMemoPhotoSelectionTransaction<PhotosPickerItem>

    let maxSelectionCount: Int
    let onCommit: ([PhotosPickerItem]) -> Void
    let onShowAllPhotos: ([PhotosPickerItem]) -> Void

    init(
        selection: [PhotosPickerItem],
        maxSelectionCount: Int,
        onCommit: @escaping ([PhotosPickerItem]) -> Void,
        onShowAllPhotos: @escaping ([PhotosPickerItem]) -> Void
    ) {
        _transaction = State(initialValue: .init(committed: selection))
        self.maxSelectionCount = maxSelectionCount
        self.onCommit = onCommit
        self.onShowAllPhotos = onShowAllPhotos
    }

    var body: some View {
        PhotosPicker(
            selection: $transaction.pending,
            maxSelectionCount: maxSelectionCount,
            selectionBehavior: .continuousAndOrdered,
            matching: .images
        ) {
            Text("选择照片")
        }
        .photosPickerStyle(.inline)
        .photosPickerDisabledCapabilities(.selectionActions)
        .photosPickerAccessoryVisibility(.hidden, edges: .all)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            footerControls
                .padding(.horizontal, AppSpacing.page)
                .padding(.bottom, AppSpacing.card)
        }
    }

    private var footerControls: some View {
        HStack {
            closeButton
            Spacer(minLength: AppSpacing.card)
            selectionActionButton
        }
        .frame(height: LeafyRootChromeMetrics.controlDiameter)
    }

    private var closeButton: some View {
        Button {
            _ = transaction.cancel()
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .leafyGlassSurface(
            in: Circle(),
            fallbackFill: Color(uiColor: .secondarySystemBackground),
            isInteractive: true
        )
        .accessibilityLabel("关闭照片选择")
    }

    private var selectionActionButton: some View {
        let hasSelection = !transaction.pending.isEmpty
        return Button(action: performSelectionAction) {
            Text(hasSelection ? "添加 \(transaction.pending.count) 张照片" : "全部照片")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(
                    hasSelection
                        ? AppTheme.textOnAccent(for: themeColorPreference)
                        : AppTheme.primaryText
                )
                .padding(.horizontal, 18)
                .frame(height: LeafyRootChromeMetrics.controlDiameter)
        }
        .buttonStyle(.plain)
        .leafyGlassSurface(
            in: Capsule(),
            tint: hasSelection ? AppTheme.accent(for: themeColorPreference) : nil,
            fallbackFill: hasSelection
                ? AppTheme.accent(for: themeColorPreference)
                : Color(uiColor: .secondarySystemBackground),
            isInteractive: true
        )
        .accessibilityHint(
            hasSelection
                ? "添加已选择的照片并返回随记"
                : "打开完整照片图库"
        )
    }

    private func performSelectionAction() {
        if transaction.pending.isEmpty {
            showAllPhotos()
        } else {
            onCommit(transaction.commit())
            dismiss()
        }
    }

    private func showAllPhotos() {
        onShowAllPhotos(transaction.fullPickerSelection)
        dismiss()
    }
}

private struct ScheduleMemoComposer: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var speech = ScheduleMemoSpeechRecognizer()
    @State private var text = ""
    @State private var speechBase = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var fullPhotoItems: [PhotosPickerItem] = []
    @State private var draftImages: [ScheduleMemoDraftImage] = []
    @State private var draftAttachments: [ScheduleMemoDraftAttachment] = []
    @State private var presentation: ScheduleMemoComposerPresentation = .compact
    @State private var measuredTextHeight: CGFloat = 0
    @State private var showsAddMenu = false
    @State private var pendingAddDestination: ScheduleMemoComposerAddDestination?
    @State private var showsCamera = false
    @State private var showsInlinePhotoLibrary = false
    @State private var showsFullPhotoLibrary = false
    @State private var presentsFullPhotoLibraryAfterInlineDismissal = false
    @State private var isPreparingFullPhotoLibrarySelection = false
    @State private var showsAudioRecorder = false
    @State private var showsFileImporter = false
    @State private var focusesTextFieldAfterCamera = false
    @State private var errorMessage: String?
    @State private var errorTitle = "无法保存随记"
    @FocusState private var isEditorFocused: Bool

    let availableHeight: CGFloat

    init(availableHeight: CGFloat = UIScreen.main.bounds.height) {
        self.availableHeight = availableHeight
    }

    private static let editorFontSize: CGFloat = 20
    private static let editorLineHeight = UIFont.systemFont(ofSize: editorFontSize).lineHeight

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !draftImages.isEmpty
            || !draftAttachments.isEmpty
    }

    var body: some View {
        VStack(spacing: 8) {
            draftPreview
            composerControls
                .frame(height: presentation == .fullscreen ? nil : composerControlsHeight)
                .frame(maxHeight: presentation == .fullscreen ? .infinity : nil)
        }
        .padding(.horizontal, 8)
        .padding(.top, hasDraftContent ? 10 : 4)
        .padding(.bottom, 4)
        .frame(height: presentation == .fullscreen ? fullscreenHeight : nil, alignment: .bottom)
        .leafyGlassSurface(
            in: RoundedRectangle(cornerRadius: 28, style: .continuous),
            fallbackFill: AppTheme.cardBackground,
            isInteractive: true
        )
        .padding(.horizontal, AppSpacing.page)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .photosPicker(
            isPresented: $showsFullPhotoLibrary,
            selection: $fullPhotoItems,
            maxSelectionCount: photoLibrarySelectionLimit,
            matching: .images
        )
        .onChange(of: fullPhotoItems) { _, items in
            guard !isPreparingFullPhotoLibrarySelection else { return }
            Task { await commitPhotoSelection(items) }
        }
        .sheet(
            isPresented: $showsInlinePhotoLibrary,
            onDismiss: presentFullPhotoLibraryIfNeeded
        ) {
            ScheduleMemoInlinePhotoPickerSheet(
                selection: photoItems,
                maxSelectionCount: photoLibrarySelectionLimit,
                onCommit: { selection in
                    Task { await commitPhotoSelection(selection) }
                },
                onShowAllPhotos: { selection in
                    isPreparingFullPhotoLibrarySelection = true
                    fullPhotoItems = selection
                    presentsFullPhotoLibraryAfterInlineDismissal = true
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(36)
        }
        .sheet(isPresented: $showsCamera, onDismiss: {
            if focusesTextFieldAfterCamera {
                focusesTextFieldAfterCamera = false
                isEditorFocused = true
            }
        }) {
            ScheduleMemoCameraView { image in
                guard draftImages.count < ScheduleMemoImageStore.maximumImageCount,
                      let data = image.jpegData(compressionQuality: 0.9) else { return }
                draftImages.append(.init(data: data, image: image))
                focusesTextFieldAfterCamera = true
            }
            .presentationDetents([.fraction(0.62)])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(36)
            .presentationBackground(.black)
        }
        .leafySheet(isPresented: $showsAudioRecorder) {
            ScheduleMemoAudioRecorderSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: Self.allowedAttachmentTypes,
            allowsMultipleSelection: true,
            onCompletion: importAttachments
        )
        .onChange(of: speech.transcript) { _, transcript in
            text = speechBase + transcript
        }
        .onChange(of: speech.state) { _, state in
            if case .unavailable(let message) = state {
                errorTitle = "无法使用语音转写"
                errorMessage = message
            }
        }
        .onChange(of: isEditorFocused) { _, isFocused in
            updatePresentationForFocus(isFocused)
        }
        .onPreferenceChange(ScheduleMemoComposerTextHeightPreferenceKey.self) { newHeight in
            guard abs(measuredTextHeight - newHeight) > 0.5 else { return }
            measuredTextHeight = newHeight
            updatePresentationForMeasuredTextHeight(newHeight)
        }
        .alert(errorTitle, isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil; speech.clearMessage() } }
        )) {
            Button("好") { errorMessage = nil; speech.clearMessage() }
        } message: {
            Text(errorMessage ?? "")
        }
        .onDisappear {
            Task { await speech.stop() }
        }
    }

    private var hasDraftContent: Bool {
        !draftImages.isEmpty || !draftAttachments.isEmpty
    }

    private var explicitTextHeight: CGFloat {
        let lineCount = max(text.components(separatedBy: "\n").count, 1)
        return CGFloat(lineCount) * Self.editorLineHeight
    }

    private var effectiveTextHeight: CGFloat {
        max(measuredTextHeight, explicitTextHeight)
    }

    private var isLongText: Bool {
        effectiveTextHeight >= Self.editorLineHeight * 4 - 0.5
    }

    private var showsExpansionControl: Bool {
        presentation == .fullscreen || isLongText
    }

    private var fullscreenHeight: CGFloat {
        min(max(availableHeight * 0.8, 240), availableHeight)
    }

    private var compactEditorHeight: CGFloat {
        44
    }

    private var expandedEditorHeight: CGFloat {
        min(max(effectiveTextHeight + 18, compactEditorHeight), Self.editorLineHeight * 4 + 20)
    }

    private var composerControlsHeight: CGFloat {
        switch presentation {
        case .compact:
            compactEditorHeight
        case .expanded, .fullscreen:
            expandedEditorHeight + 8 + 44
        }
    }

    private var composerControls: some View {
        ScheduleMemoComposerControlLayout(
            presentation: presentation,
            expandedEditorHeight: expandedEditorHeight
        ) {
            addButton
            editor
            microphoneButton
            sendButton
        }
    }

    private var measurementText: String {
        if text.isEmpty {
            return " "
        }
        return text.hasSuffix("\n") ? text + " " : text
    }

    private var editorLeadingOffset: CGFloat {
        presentation == .compact ? 0 : 9
    }

    private var focusedEditorVerticalOffset: CGFloat {
        isEditorFocused ? 6 : 0
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("记点什么...")
                    .font(.system(size: Self.editorFontSize, weight: .regular))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .padding(.leading, 5 + editorLeadingOffset)
                    .padding(.trailing, 5)
                    .padding(.top, 8 + focusedEditorVerticalOffset)
                    .padding(.bottom, 8)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $text)
                .font(.system(size: Self.editorFontSize, weight: .regular))
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .padding(.leading, editorLeadingOffset)
                .padding(.trailing, showsExpansionControl ? 42 : 0)
                .padding(.top, focusedEditorVerticalOffset)
                .focused($isEditorFocused)

            if showsExpansionControl {
                HStack {
                    Spacer()
                    Button(action: toggleFullscreen) {
                        Image(systemName: presentation == .fullscreen
                              ? "arrow.down.right.and.arrow.up.left"
                              : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(presentation == .fullscreen ? "缩小编辑器" : "放大编辑器")
                }
                .transition(.scale(scale: 0.84, anchor: .topTrailing).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: showsExpansionControl)
        .animation(.easeOut(duration: 0.2), value: isEditorFocused)
        .background {
            GeometryReader { proxy in
                let textWidth = max(
                    proxy.size.width - editorLeadingOffset - (showsExpansionControl ? 54 : 12),
                    1
                )
                Color.clear.preference(
                    key: ScheduleMemoComposerTextHeightPreferenceKey.self,
                    value: measuredEditorTextHeight(for: textWidth)
                )
            }
        }
    }

    private func measuredEditorTextHeight(for width: CGFloat) -> CGFloat {
        let font = UIFont.systemFont(ofSize: Self.editorFontSize, weight: .regular)
        let bounds = (measurementText as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        let explicitLineCount = max(text.components(separatedBy: "\n").count, 1)
        return max(ceil(bounds.height), CGFloat(explicitLineCount) * Self.editorLineHeight)
    }

    private var addButton: some View {
        Button {
            showsAddMenu.toggle()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .regular))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .accessibilityLabel("添加内容")
        .popover(isPresented: $showsAddMenu, attachmentAnchor: .point(.top), arrowEdge: .bottom) {
            addMenu
                .onDisappear(perform: presentPendingAddDestination)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var microphoneButton: some View {
        Button {
            Task {
                if !speech.isListening { speechBase = text.isEmpty ? "" : text + " " }
                await speech.toggle()
            }
        } label: {
            Image(systemName: speech.isListening ? "stop.circle.fill" : "mic")
                .font(.system(size: 23, weight: .regular))
                .foregroundStyle(speech.isListening ? AppTheme.danger : AppTheme.primaryText)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(speech.isListening ? "停止语音转写" : "开始语音转写")
    }

    private var sendButton: some View {
        Button {
            Task {
                await speech.stop()
                save()
            }
        } label: {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(canSave ? AppTheme.accent : AppTheme.tertiaryText)
                .frame(width: 44, height: 44)
        }
        .disabled(!canSave)
        .accessibilityLabel("保存随记")
    }

    @ViewBuilder
    private var draftPreview: some View {
        if !draftImages.isEmpty || !draftAttachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(draftImages) { draft in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: draft.image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 104, height: 104)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .clipped()
                            removeButton(label: "移除图片") {
                                draftImages.removeAll { $0.id == draft.id }
                                if let pickerItem = draft.pickerItem {
                                    photoItems = ScheduleMemoPhotoSelection.removing(pickerItem, from: photoItems)
                                    fullPhotoItems = ScheduleMemoPhotoSelection.removing(pickerItem, from: fullPhotoItems)
                                }
                            }
                        }
                    }
                    ForEach(draftAttachments) { attachment in
                        HStack(spacing: 7) {
                            Image(systemName: "doc")
                                .foregroundStyle(AppTheme.accent)
                            Text(attachment.originalFilename)
                                .font(.caption)
                                .lineLimit(1)
                            removeButton(label: "移除附件") {
                                draftAttachments.removeAll { $0.id == attachment.id }
                            }
                        }
                        .padding(.leading, 10)
                        .frame(height: 44)
                        .background(AppTheme.cardBackground, in: Capsule())
                    }
                }
                .padding(.leading, AppSpacing.micro)
            }
        }
    }

    private func removeButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.7))
        }
        .frame(width: 44, height: 44)
        .accessibilityLabel(label)
    }

    private var addMenu: some View {
        VStack(spacing: 0) {
            addMenuButton("拍照", systemImage: "camera") {
                selectAddDestination(.camera)
            }

            addMenuButton("相册", systemImage: "photo") {
                selectAddDestination(.photoLibrary)
            }

            addMenuButton("录音", systemImage: "waveform") {
                selectAddDestination(.audioRecording)
            }

            addMenuButton("附件", systemImage: "paperclip") {
                selectAddDestination(.fileImporter)
            }
        }
        .padding(.vertical, 8)
        .frame(width: 260)
    }

    private func addMenuButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            addMenuLabel(title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }

    private func addMenuLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.primaryText)
                .frame(width: 32, height: 32)
            Text(title)
                .foregroundStyle(AppTheme.primaryText)
            Spacer()
        }
        .font(.system(size: 20, weight: .regular))
        .padding(.horizontal, 16)
        .frame(height: 56)
        .contentShape(Rectangle())
    }

    private func toggleFullscreen() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            presentation = presentation == .fullscreen ? .expanded : .fullscreen
        }
        Task { @MainActor in
            await Task.yield()
            isEditorFocused = true
        }
    }

    private func updatePresentationForFocus(_ isFocused: Bool) {
        if isFocused {
            guard presentation == .compact else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                presentation = .expanded
            }
            return
        }

        guard presentation == .expanded,
              !isLongText,
              !hasDraftContent,
              !speech.isListening,
              !showsAddMenu,
              pendingAddDestination == nil,
              !showsCamera,
              !showsInlinePhotoLibrary,
              !showsFullPhotoLibrary,
              !showsAudioRecorder,
              !showsFileImporter else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            presentation = .compact
        }
    }

    private func updatePresentationForMeasuredTextHeight(_ height: CGFloat) {
        let exceedsFourLines = height >= Self.editorLineHeight * 4 - 0.5
        if exceedsFourLines, presentation == .compact {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                presentation = .expanded
            }
        } else if !exceedsFourLines, !isEditorFocused, presentation == .expanded, !hasDraftContent {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                presentation = .compact
            }
        }
    }

    private func selectAddDestination(_ destination: ScheduleMemoComposerAddDestination) {
        pendingAddDestination = destination
        showsAddMenu = false
    }

    private func presentPendingAddDestination() {
        guard let destination = pendingAddDestination else { return }
        pendingAddDestination = nil
        Task { @MainActor in
            await Task.yield()
            switch destination {
            case .camera:
                showsCamera = true
            case .photoLibrary:
                guard remainingPhotoSelectionCount > 0 else {
                    errorTitle = "无法添加图片"
                    errorMessage = "每条随记最多添加 \(ScheduleMemoImageStore.maximumImageCount) 张图片。"
                    return
                }
                showsInlinePhotoLibrary = true
            case .audioRecording:
                await speech.stop()
                showsAudioRecorder = true
            case .fileImporter:
                showsFileImporter = true
            }
        }
    }

    private func presentFullPhotoLibraryIfNeeded() {
        guard presentsFullPhotoLibraryAfterInlineDismissal else { return }
        presentsFullPhotoLibraryAfterInlineDismissal = false
        Task { @MainActor in
            await Task.yield()
            showsFullPhotoLibrary = true
            await Task.yield()
            isPreparingFullPhotoLibrarySelection = false
        }
    }

    private var photoLibrarySelectionLimit: Int {
        max(remainingPhotoSelectionCount, 1)
    }

    private var remainingPhotoSelectionCount: Int {
        max(
            ScheduleMemoImageStore.maximumImageCount
                - draftImages.lazy.filter { $0.pickerItem == nil }.count,
            0
        )
    }

    private static let allowedAttachmentTypes: [UTType] = {
        let extensions = ["md", "txt", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "csv"]
        return [.pdf] + extensions.compactMap { UTType(filenameExtension: $0) }
    }()

    private func importAttachments(_ result: Result<[URL], Error>) {
        do {
            let remainingCount = max(3 - draftAttachments.count, 0)
            guard remainingCount > 0 else {
                throw ScheduleMemoComposerError.tooManyAttachments
            }
            let urls = try result.get()
            guard urls.count <= remainingCount else {
                throw ScheduleMemoComposerError.tooManyAttachments
            }
            for url in urls {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                draftAttachments.append(.init(
                    originalFilename: url.lastPathComponent,
                    typeIdentifier: (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.identifier)
                        ?? UTType.data.identifier,
                    data: try Data(contentsOf: url)
                ))
            }
        } catch {
            errorTitle = "无法添加附件"
            errorMessage = error.localizedDescription
        }
    }

    private func load(_ items: [PhotosPickerItem]) async {
        var loaded: [ScheduleMemoDraftImage] = []
        for item in items.prefix(ScheduleMemoImageStore.maximumImageCount) {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = ImageDataDecoder.decodedImage(from: data) else { continue }
            loaded.append(.init(data: data, image: image, pickerItem: item))
        }
        let capturedImages = draftImages.filter { $0.pickerItem == nil }
        draftImages = ScheduleMemoPhotoSelection.merging(
            pickerItems: loaded,
            capturedItems: capturedImages,
            maximumCount: ScheduleMemoImageStore.maximumImageCount
        )
    }

    @MainActor
    private func commitPhotoSelection(_ items: [PhotosPickerItem]) async {
        photoItems = items
        await load(items)
    }

    @MainActor
    private func save() {
        guard canSave else { return }
        persistMemo(kind: .quickMemo, title: nil, body: text)
    }

    @MainActor
    private func persistMemo(kind: ScheduleMemoKind, title: String?, body: String) {
        var filenames: [String] = []
        var storedAttachments: [ScheduleMemoAttachmentStore.StoredFile] = []
        do {
            for draft in draftImages {
                filenames.append(try ScheduleMemoImageStore.importImage(data: draft.data))
            }
            for attachment in draftAttachments {
                storedAttachments.append(try ScheduleMemoAttachmentStore.importData(
                    attachment.data,
                    originalFilename: attachment.originalFilename,
                    contentTypeIdentifier: attachment.typeIdentifier
                ))
            }
            let memo = ScheduleMemo(body: body, kind: kind, title: title)
            modelContext.insert(memo)
            for (index, filename) in filenames.enumerated() {
                modelContext.insert(ScheduleMemoImage(memoID: memo.id, sortOrder: index, localFilename: filename))
            }
            for (index, file) in storedAttachments.enumerated() {
                modelContext.insert(ScheduleMemoAttachment(
                    id: file.id,
                    memoID: memo.id,
                    sortOrder: index,
                    originalFilename: file.originalFilename,
                    localFilename: file.localFilename,
                    contentTypeIdentifier: file.contentTypeIdentifier
                ))
            }
            try modelContext.save()
            text = ""
            speechBase = ""
            photoItems = []
            fullPhotoItems = []
            draftImages = []
            draftAttachments = []
            presentation = .compact
            isEditorFocused = false
        } catch {
            try? ScheduleMemoImageStore.deleteFiles(named: filenames)
            try? ScheduleMemoAttachmentStore.deleteFiles(named: storedAttachments.map(\.localFilename))
            modelContext.rollback()
            errorTitle = "无法保存随记"
            errorMessage = error.localizedDescription
        }
    }
}

private struct ScheduleMemoEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let memo: ScheduleMemo
    @State private var bodyText: String
    @State private var errorMessage: String?

    init(memo: ScheduleMemo) {
        self.memo = memo
        _bodyText = State(initialValue: memo.body)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("录音备注") {
                    TextField("添加一句备注（可选）", text: $bodyText, axis: .vertical)
                        .lineLimit(5...14)
                }
                Section {
                    Text("正文里的 #标签 和 #学习/Swift 会自动成为标签。")
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .navigationTitle("编辑录音备注")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        memo.updateBody(bodyText)
                        do {
                            try modelContext.save()
                            dismiss()
                        } catch {
                            modelContext.rollback()
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            }
        }
        .alert("无法保存随记", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
}

private struct ScheduleMemoReviewView: View {
    @Environment(\.openURL) private var openURL
    @Query private var memos: [ScheduleMemo]
    @Query private var images: [ScheduleMemoImage]
    @Query private var attachments: [ScheduleMemoAttachment]
    @Query private var audioRecords: [ScheduleMemoAudio]
    @State private var page = 0
    @State private var shareCardSource: ScheduleMemoShareCardPreviewSource?
    @State private var submissionFallback: ScheduleMemoSubmissionDraft?
    @State private var operationAlert: LeafyOperationAlert?
    @StateObject private var audioPlayback = ScheduleMemoAudioPlaybackController()

    private var selection: [ScheduleMemo] {
        ScheduleMemoReviewEngine.selection(from: memos, page: page)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.card) {
                AcademicDetailCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("重逢旧想法").leafyHeadline()
                            Text("优先回顾历年同日，再从旧随记中稳定选取。")
                                .microCaption().foregroundStyle(AppTheme.secondaryText)
                        }
                        Spacer()
                        Button("换一组") { page += 1 }
                            .buttonStyle(.bordered)
                    }
                }
                if selection.isEmpty {
                    ContentUnavailableView("还没有可回顾的随记", systemImage: "sparkles", description: Text("记录会在未来的今天与你重逢。"))
                        .padding(.top, 60)
                } else {
                    ForEach(selection) { memo in
                        ScheduleMemoCard(
                            memo: memo,
                            images: images.filter { $0.memoID == memo.id }.sorted { $0.sortOrder < $1.sortOrder },
                            attachments: attachments.filter { $0.memoID == memo.id }.sorted { $0.sortOrder < $1.sortOrder },
                            audio: audioRecords.first { $0.memoID == memo.id },
                            audioPlayback: audioPlayback,
                            linkedSchedule: nil,
                            onOpen: nil,
                            onTag: nil,
                            onEdit: nil,
                            onConvert: nil,
                            onShareCard: {
                                do {
                                    let memoImages = images
                                        .filter { $0.memoID == memo.id }
                                        .sorted { $0.sortOrder < $1.sortOrder }
                                    let memoAttachments = attachments
                                        .filter { $0.memoID == memo.id }
                                        .sorted { $0.sortOrder < $1.sortOrder }
                                    shareCardSource = ScheduleMemoShareCardPreviewSource(
                                        snapshot: try ScheduleMemoShareCardSnapshot.make(
                                            memo: memo,
                                            images: memoImages,
                                            attachments: memoAttachments
                                        )
                                    )
                                } catch {
                                    operationAlert = .failure(error.localizedDescription)
                                }
                            },
                            onSubmit: { submit(memo) },
                            onPin: nil,
                            onTrash: nil
                        )
                    }
                }
            }
            .leafyAdaptiveContentWidth(maxWidth: 760)
            .padding(.vertical, AppSpacing.card)
        }
        .background(LeafyPageBackground())
        .navigationTitle("每日回顾")
        .leafySheet(item: $shareCardSource) { source in
            ScheduleMemoShareCardPreviewSheet(source: source)
        }
        .leafyOperationAlert($operationAlert)
        .confirmationDialog(
            "无法打开邮箱 App",
            isPresented: Binding(
                get: { submissionFallback != nil },
                set: { if !$0 { submissionFallback = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let draft = submissionFallback {
                Button("复制投稿内容") {
                    UIPasteboard.general.string = draft.body
                    submissionFallback = nil
                }
                Button("复制投稿邮箱") {
                    UIPasteboard.general.string = ScheduleMemoSubmissionDraft.recipient
                    submissionFallback = nil
                }
            }
            Button("取消", role: .cancel) { submissionFallback = nil }
        } message: {
            Text("请复制投稿内容，稍后发送至 \(ScheduleMemoSubmissionDraft.recipient)。")
        }
    }

    private func submit(_ memo: ScheduleMemo) {
        let memoAttachments = attachments.filter { $0.memoID == memo.id }
        let draft = ScheduleMemoSubmissionDraft.make(
            title: memo.kind == .article ? memo.title : nil,
            source: memo.body,
            tags: memo.tags,
            createdAt: memo.createdAt,
            updatedAt: memo.updatedAt,
            attachmentNames: Dictionary(uniqueKeysWithValues: memoAttachments.map { ($0.id, $0.originalFilename) })
        )
        guard let url = draft.mailtoURL else {
            submissionFallback = draft
            return
        }
        openURL(url) { accepted in
            guard !accepted else { return }
            Task { @MainActor in submissionFallback = draft }
        }
    }
}

private struct ScheduleMemoTagsView: View {
    @Query private var memos: [ScheduleMemo]

    private var tags: [(String, Int)] {
        var names: [String: String] = [:]
        var counts: [String: Int] = [:]
        for tag in memos.filter({ !$0.isTrashed }).flatMap(\.tags) {
            let key = tag.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            names[key] = names[key] ?? tag
            counts[key, default: 0] += 1
        }
        return counts.map { (names[$0.key] ?? $0.key, $0.value) }
            .sorted { $0.0.localizedCompare($1.0) == .orderedAscending }
    }

    var body: some View {
        List {
            if tags.isEmpty {
                ContentUnavailableView("还没有标签", systemImage: "number", description: Text("在随记正文中输入 #标签 即可自动整理。"))
            } else {
                ForEach(tags, id: \.0) { tag, count in
                    NavigationLink {
                        ScheduleMemoFeedView(initialTag: tag)
                            .navigationTitle("#\(tag)")
                    } label: {
                        Label {
                            HStack { Text(tag); Spacer(); Text("\(count)").foregroundStyle(.secondary) }
                        } icon: { Image(systemName: "number") }
                    }
                }
            }
        }
        .navigationTitle("标签")
    }
}

private struct ScheduleMemoExportArtifact: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ScheduleMemoExportView: View {
    @Query private var memos: [ScheduleMemo]
    @Query private var images: [ScheduleMemoImage]
    @State private var artifact: ScheduleMemoExportArtifact?
    @State private var operationAlert: LeafyOperationAlert?

    private var activeMemos: [ScheduleMemo] {
        memos.filter { !$0.isTrashed }
    }

    private var activeImageCount: Int {
        let memoIDs = Set(activeMemos.map(\.id))
        return images.lazy.filter { memoIDs.contains($0.memoID) }.count
    }

    var body: some View {
        List {
            Section {
                exportButton(
                    title: "导出为 TXT",
                    subtitle: "按时间整理随记正文、标题和标签",
                    systemImage: "doc.plaintext",
                    action: exportText
                )

                exportButton(
                    title: "导出图片压缩包",
                    subtitle: "将随记中的 \(activeImageCount) 张图片打包为 ZIP",
                    systemImage: "photo.stack",
                    action: exportImages
                )
            } footer: {
                Text("仅导出当前身份下未移入回收站的本地随记；导出不会上传或删除原始内容。")
            }
        }
        .navigationTitle("导出随记")
        .leafySheet(item: $artifact) { artifact in
            LeafySystemShare(activityItems: [artifact.url])
        }
        .leafyOperationAlert($operationAlert)
    }

    private func exportButton(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .foregroundStyle(AppTheme.primaryText)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 28)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func exportText() {
        do {
            artifact = .init(url: try ScheduleMemoExporter.exportText(memos: memos))
        } catch {
            operationAlert = .failure(error.localizedDescription)
        }
    }

    private func exportImages() {
        do {
            artifact = .init(url: try ScheduleMemoExporter.exportImageArchive(memos: memos, images: images))
        } catch {
            operationAlert = .failure(error.localizedDescription)
        }
    }
}


private struct ScheduleMemoStatisticsSummary: View {
    let statistics: ScheduleMemoStatistics
    var compact = false
    let onSelectDate: (Date) -> Void

    private let rows = Array(repeating: GridItem(.fixed(18), spacing: 5), count: 7)

    var body: some View {
        VStack(spacing: compact ? AppSpacing.compact : AppSpacing.card) {
            HStack(spacing: 10) {
                metric("随记", statistics.memoCount)
                metric("标签", statistics.tagCount)
                metric("记录天数", statistics.recordingDayCount)
            }

            AcademicDetailCard {
                VStack(alignment: .leading, spacing: compact ? 10 : 14) {
                    Text("最近 12 周").leafyHeadline()
                    LazyHGrid(rows: rows, spacing: 5) {
                        ForEach(statistics.activityDays) { day in
                            Button { onSelectDate(day.date) } label: {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(activityColor(day.count))
                                    .frame(width: 18, height: 18)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(day.date.formatted(date: .long, time: .omitted))，\(day.count) 条随记")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    Text("颜色越深，表示当天记录越多。点按日期查看当天随记。")
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
    }

    private func metric(_ title: String, _ value: Int) -> some View {
        VStack(spacing: 5) {
            Text("\(value)").font(.title2.bold()).foregroundStyle(AppTheme.primaryText)
            Text(title).microCaption().foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, compact ? 10 : 16)
        .leafyCardStyle()
    }

    private func activityColor(_ count: Int) -> Color {
        switch count {
        case 0: return AppTheme.softFill
        case 1: return AppTheme.accent.opacity(0.3)
        case 2: return AppTheme.accent.opacity(0.55)
        case 3: return AppTheme.accent.opacity(0.75)
        default: return AppTheme.accent
        }
    }
}

struct ScheduleMemoDayView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var memos: [ScheduleMemo]
    let date: Date

    private var dayMemos: [ScheduleMemo] {
        memos.filter { !$0.isTrashed && Calendar.current.isDate($0.createdAt, inSameDayAs: date) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        List(dayMemos) { memo in
            VStack(alignment: .leading, spacing: 7) {
                Text(memo.createdAt.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                Text(memo.body.isEmpty ? (memo.kind == .audio ? "录音随记" : "图片随记") : memo.body)
            }
        }
        .navigationTitle(date.formatted(date: .abbreviated, time: .omitted))
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
    }
}

private struct ScheduleMemoTrashView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var memos: [ScheduleMemo]
    @Query private var images: [ScheduleMemoImage]
    @Query private var audioRecords: [ScheduleMemoAudio]
    @State private var confirmsEmpty = false
    @State private var errorMessage: String?

    private var trashed: [ScheduleMemo] {
        memos.filter(\.isTrashed).sorted { ($0.trashedAt ?? .distantPast) > ($1.trashedAt ?? .distantPast) }
    }

    var body: some View {
        List {
            if trashed.isEmpty {
                ContentUnavailableView("回收站为空", systemImage: "trash", description: Text("移入回收站的随记不会自动到期。"))
            } else {
                ForEach(trashed) { memo in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(memo.body.isEmpty ? (memo.kind == .audio ? "录音随记" : "图片随记") : memo.body).lineLimit(4)
                        HStack {
                            Button("恢复") { restore(memo) }.buttonStyle(.bordered)
                            Button("永久删除", role: .destructive) { permanentlyDelete(memo) }.buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
        }
        .navigationTitle("回收站")
        .toolbar {
            if !trashed.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清空", role: .destructive) { confirmsEmpty = true }
                }
            }
        }
        .confirmationDialog("永久删除回收站中的全部随记？", isPresented: $confirmsEmpty, titleVisibility: .visible) {
            Button("永久删除全部", role: .destructive) {
                for memo in trashed { permanentlyDelete(memo, saves: false) }
                try? modelContext.save()
            }
        } message: { Text("图片和附件也会从本机删除，此操作无法撤销。") }
        .alert("删除失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func restore(_ memo: ScheduleMemo) {
        do { try ScheduleMemoDeletionService.restore(memo, in: modelContext) }
        catch { errorMessage = error.localizedDescription }
    }

    private func permanentlyDelete(_ memo: ScheduleMemo, saves: Bool = true) {
        do {
            try ScheduleMemoDeletionService.permanentlyDelete(
                memo,
                images: images,
                audioRecords: audioRecords,
                in: modelContext,
                saves: saves
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private func memoTitle(_ body: String) -> String {
    let line = body.split(whereSeparator: \.isNewline).first.map(String.init) ?? "新日程"
    return String(line.prefix(40))
}

private func defaultTimetableContext(for date: Date = Date()) -> TimetableCellReminderContext {
    let calendar = Calendar.current
    let start = calendar.startOfDay(for: SemesterConfig.startOfSemesterDate)
    let current = calendar.startOfDay(for: date)
    let days = calendar.dateComponents([.day], from: start, to: current).day ?? 0
    let weekday = calendar.component(.weekday, from: date)
    let day = weekday == 1 ? 7 : weekday - 1
    let week = (days >= 0 && days < SemesterConfig.supportedWeeks * 7)
        ? (days / 7) + 1
        : SemesterConfig.currentWeek()
    let period = min(max(TimetablePeriodSchedule.defaultStudyPeriod(for: date), 1), TimetablePeriodSchedule.slots.count)
    return TimetableCellReminderContext(
        week: week,
        day: day,
        period: period,
        date: date,
        occupiedPeriods: [],
        totalPeriods: TimetablePeriodSchedule.slots.count,
        reminder: nil,
        allowsDateSelection: true
    )
}
