import Charts
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

extension ScheduleDestination {
    var title: String {
        switch self {
        case .memos: return "全部随记"
        case .customSchedules: return "我的日程"
        case .dailyReview: return "每日回顾"
        case .tags: return "标签"
        case .statistics: return "记录统计"
        case .scheduleReports: return "日程推送"
        case .yearOverview: return "年度视图"
        case .trash: return "回收站"
        case .timetableProcessing: return "课表处理"
        }
    }

    var systemImage: String {
        switch self {
        case .memos: return "square.grid.2x2"
        case .customSchedules: return "calendar.badge.plus"
        case .dailyReview: return "sparkles"
        case .tags: return "number"
        case .statistics: return "chart.bar.xaxis"
        case .scheduleReports: return "bell.badge"
        case .yearOverview: return "calendar"
        case .trash: return "trash"
        case .timetableProcessing: return "slider.horizontal.3"
        }
    }
}

struct ScheduleRootView: View {
    @EnvironmentObject private var appNavigation: AppNavigationCoordinator
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var compactPath: [ScheduleDestination] = []
    @State private var regularSelection: ScheduleDestination? = .memos
    @State private var showsMenu = false

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                NavigationSplitView {
                    ScheduleSidebar(selection: $regularSelection)
                        .navigationTitle("日程")
                } detail: {
                    NavigationStack {
                        destinationView(regularSelection ?? .memos)
                    }
                }
            } else {
                NavigationStack(path: $compactPath) {
                    ScheduleMemoFeedView()
                        .navigationTitle("日程")
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button {
                                    showsMenu = true
                                } label: {
                                    Image(systemName: "line.3.horizontal")
                                        .frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("打开日程菜单")
                            }
                        }
                        .navigationDestination(for: ScheduleDestination.self) { destination in
                            destinationView(destination)
                        }
                }
                .leafySheet(isPresented: $showsMenu) {
                    NavigationStack {
                        ScheduleSidebar(selection: Binding(
                            get: { nil },
                            set: { destination in
                                guard let destination else { return }
                                showsMenu = false
                                if destination != .memos { compactPath.append(destination) }
                            }
                        ), presentation: .modal)
                    }
                    .presentationDetents([.medium, .large])
                }
            }
        }
        .onAppear { consumeRequestedDestination() }
        .onChange(of: appNavigation.requestedScheduleDestination) { _, _ in
            consumeRequestedDestination()
        }
    }

    @ViewBuilder
    private func destinationView(_ destination: ScheduleDestination) -> some View {
        switch destination {
        case .memos:
            ScheduleMemoFeedView()
                .navigationTitle("日程")
        case .customSchedules:
            CustomScheduleListView()
        case .dailyReview:
            ScheduleMemoReviewView()
        case .tags:
            ScheduleMemoTagsView()
        case .statistics:
            ScheduleMemoStatisticsView()
        case .scheduleReports:
            ScheduleReportsView()
        case .yearOverview:
            ScheduleYearOverviewView()
        case .trash:
            ScheduleMemoTrashView()
        case .timetableProcessing:
            TimetableProcessingView()
        }
    }

    private func consumeRequestedDestination() {
        guard let destination = appNavigation.requestedScheduleDestination else { return }
        if horizontalSizeClass == .regular {
            regularSelection = destination
        } else if destination == .memos {
            compactPath.removeAll()
        } else {
            compactPath = [destination]
        }
        appNavigation.requestedScheduleDestination = nil
    }
}

private struct ScheduleSidebar: View {
    enum Presentation: Equatable {
        case sidebar
        case modal
    }

    @Binding var selection: ScheduleDestination?
    var presentation: Presentation = .sidebar

    private var destinations: [ScheduleDestination] {
        ScheduleDestination.allCases.filter {
            $0 != .timetableProcessing || ActiveCampusContext.identity?.isCustom == true
        }
    }

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
    }

    private var sidebarList: some View {
        List(selection: $selection) {
            row(.statistics)

            Section("记录") {
                row(.memos)
                row(.dailyReview)
                row(.tags)
                row(.trash)
            }
            Section("日程") {
                row(.customSchedules)
                row(.scheduleReports)
                row(.yearOverview)
                if destinations.contains(.timetableProcessing) { row(.timetableProcessing) }
            }
        }
    }

    private func row(_ destination: ScheduleDestination) -> some View {
        Label(destination.title, systemImage: destination.systemImage)
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

struct ScheduleMemoFeedView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var memos: [ScheduleMemo]
    @Query private var images: [ScheduleMemoImage]
    @Query private var reminders: [TimetableCellReminder]
    @State private var searchText = ""
    @State private var selectedTag: String?
    @State private var filter: ScheduleMemoFilter = .all
    @State private var sort: ScheduleMemoSort = .newest
    @State private var editingMemo: ScheduleMemo?
    @State private var convertingMemo: ScheduleMemo?
    @State private var shareCardSource: CommunityPostCardPreviewSource?
    @State private var importantDates = CustomScheduleStore.load()
    @State private var operationAlert: LeafyOperationAlert?

    init(initialTag: String? = nil) {
        _selectedTag = State(initialValue: initialTag)
    }

    private var visibleMemos: [ScheduleMemo] {
        let byID = Dictionary(uniqueKeysWithValues: memos.map { ($0.id, $0) })
        let records = memos.map { memo in
            ScheduleMemoSearchRecord(
                id: memo.id,
                body: memo.body,
                tags: memo.tags,
                createdAt: memo.createdAt,
                updatedAt: memo.updatedAt,
                pinnedAt: memo.pinnedAt,
                isTrashed: memo.isTrashed,
                imageCount: images.lazy.filter { $0.memoID == memo.id }.count,
                isLinked: memo.linkedScheduleKind != nil && memo.linkedScheduleID != nil
            )
        }
        return ScheduleMemoSearchEngine.results(
            in: records,
            query: searchText,
            tag: selectedTag,
            requiresImages: filter == .withImages,
            requiresLink: filter == .linked,
            sort: sort
        ).compactMap { byID[$0.id] }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.card) {
                filterSummary
                if visibleMemos.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "还没有随记" : "没有找到随记",
                        systemImage: searchText.isEmpty ? "square.and.pencil" : "magnifyingglass",
                        description: Text(searchText.isEmpty ? "在下方快速记下一句话、一个想法或一张图片。" : "试试清除筛选或换一个关键词。")
                    )
                    .padding(.top, 72)
                } else {
                    ForEach(visibleMemos) { memo in
                        ScheduleMemoCard(
                            memo: memo,
                            images: memoImages(for: memo),
                            linkedTitle: linkedTitle(for: memo),
                            onTag: { selectedTag = $0 },
                            onEdit: { editingMemo = memo },
                            onConvert: { convertingMemo = memo },
                            onShareCard: { makeShareCard(for: memo) },
                            onPin: { togglePin(memo) },
                            onTrash: { moveToTrash(memo) }
                        )
                    }
                }
            }
            .leafyAdaptiveContentWidth(maxWidth: 760)
            .padding(.vertical, AppSpacing.card)
        }
        .background(LeafyPageBackground())
        .searchable(text: $searchText, prompt: "搜索正文或标签")
        .safeAreaInset(edge: .bottom) {
            ScheduleMemoComposer()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("筛选", selection: $filter) {
                        ForEach(ScheduleMemoFilter.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("排序", selection: $sort) {
                        ForEach(ScheduleMemoSort.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    Image(systemName: filter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("筛选与排序")
            }
        }
        .leafySheet(item: $editingMemo) { memo in
            ScheduleMemoEditorView(memo: memo)
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
        .leafySheet(item: $shareCardSource) { source in
            CommunityPostCardPreviewSheet(source: source)
        }
        .onReceive(NotificationCenter.default.publisher(for: .customScheduleEventsDidChange)) { _ in
            importantDates = CustomScheduleStore.load()
        }
        .leafyOperationAlert($operationAlert)
    }

    @ViewBuilder
    private var filterSummary: some View {
        if selectedTag != nil || filter != .all {
            HStack(spacing: 8) {
                if let selectedTag {
                    Button("#\(selectedTag)  ×") { self.selectedTag = nil }
                        .leafyCapsuleChipSurface(isSelected: true)
                }
                if filter != .all {
                    Button("\(filter.title)  ×") { filter = .all }
                        .leafyCapsuleChipSurface(isSelected: true)
                }
                Spacer()
            }
        }
    }

    private func linkedTitle(for memo: ScheduleMemo) -> String? {
        ScheduleMemoLinkResolver.title(
            kind: memo.linkedScheduleKind,
            stableID: memo.linkedScheduleID,
            timetableTitles: Dictionary(uniqueKeysWithValues: reminders.map { ($0.id.uuidString, $0.title) }),
            importantDateTitles: Dictionary(uniqueKeysWithValues: importantDates.map { ($0.id, $0.title) })
        )
    }

    private func memoImages(for memo: ScheduleMemo) -> [ScheduleMemoImage] {
        images.filter { $0.memoID == memo.id }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func makeShareCard(for memo: ScheduleMemo) {
        do {
            shareCardSource = try scheduleMemoShareCardSource(memo: memo, images: memoImages(for: memo))
        } catch {
            operationAlert = .failure(error.localizedDescription)
        }
    }

    private func togglePin(_ memo: ScheduleMemo) {
        memo.pinnedAt = memo.pinnedAt == nil ? Date() : nil
        memo.updatedAt = Date()
        try? modelContext.save()
    }

    private func moveToTrash(_ memo: ScheduleMemo) {
        do { try ScheduleMemoDeletionService.moveToTrash(memo, in: modelContext) }
        catch { operationAlert = .failure(error.localizedDescription) }
    }
}

private struct ScheduleMemoCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let memo: ScheduleMemo
    let images: [ScheduleMemoImage]
    let linkedTitle: String?
    let onTag: (String) -> Void
    let onEdit: () -> Void
    let onConvert: () -> Void
    let onShareCard: () -> Void
    let onPin: () -> Void
    let onTrash: () -> Void

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if memo.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityLabel("已置顶")
                }
                Spacer()
            }
            .frame(minHeight: 24)

            if !memo.body.isEmpty {
                Text(memo.body)
                    .leafyBody()
                    .foregroundStyle(AppTheme.primaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        AppTheme.accent(for: themeColorPreference)
                            .opacity(colorScheme == .dark ? 0.16 : 0.10),
                        in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                    )
            }

            if !images.isEmpty {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(images) { imageRecord in
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
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .background(AppTheme.softFill)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                        .clipped()
                        .accessibilityLabel("随记图片")
                    }
                }
            }

            if !memo.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(memo.tags, id: \.self) { tag in
                            Button("#\(tag)") { onTag(tag) }
                                .leafyCapsuleChipSurface(isSelected: false)
                        }
                    }
                }
            }

            if let linkedTitle {
                Label(linkedTitle, systemImage: linkedTitle == "原日程已删除" ? "link.badge.plus" : "link")
                    .microCaption()
                    .foregroundStyle(linkedTitle == "原日程已删除" ? AppTheme.warning : AppTheme.secondaryText)
            }

            HStack {
                Spacer()
                Text(memo.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .microCaption()
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
        .padding(18)
        .leafyCardStyle()
        .overlay(alignment: .topTrailing) {
            Menu {
                Button(memo.isPinned ? "取消置顶" : "置顶", systemImage: "pin") { onPin() }
                Button("编辑", systemImage: "pencil") { onEdit() }
                Button(linkedTitle == nil ? "转为日程" : "重新创建日程", systemImage: "calendar.badge.plus") { onConvert() }
                Button("转为图文卡片", systemImage: "rectangle.on.rectangle.angled") { onShareCard() }
                Button("移到回收站", systemImage: "trash", role: .destructive) { onTrash() }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .padding(4)
            .accessibilityLabel("随记操作")
        }
    }
}

private struct ScheduleMemoDraftImage: Identifiable {
    let id = UUID()
    let data: Data
    let image: UIImage
}

private struct ScheduleMemoComposer: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var speech = ScheduleMemoSpeechRecognizer()
    @State private var text = ""
    @State private var speechBase = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var draftImages: [ScheduleMemoDraftImage] = []
    @State private var errorMessage: String?
    @State private var errorTitle = "无法保存随记"

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draftImages.isEmpty
    }

    var body: some View {
        VStack(spacing: 8) {
            if !draftImages.isEmpty {
                HStack(spacing: 8) {
                    ForEach(draftImages) { draft in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: draft.image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .clipped()
                            Button {
                                draftImages.removeAll { $0.id == draft.id }
                                photoItems = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.7))
                            }
                            .frame(width: 44, height: 44, alignment: .topTrailing)
                            .accessibilityLabel("移除图片")
                        }
                    }
                    Spacer()
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(
                    selection: $photoItems,
                    maxSelectionCount: ScheduleMemoImageStore.maximumImageCount,
                    matching: .images
                ) {
                    Image(systemName: "plus")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("添加图片，最多三张")

                TextField("写点什么… 用 #标签 整理", text: $text, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(.vertical, 6)

                Button {
                    Task {
                        if !speech.isListening { speechBase = text.isEmpty ? "" : text + " " }
                        await speech.toggle()
                    }
                } label: {
                    Image(systemName: speech.isListening ? "stop.circle.fill" : "mic")
                        .foregroundStyle(speech.isListening ? AppTheme.danger : AppTheme.primaryText)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(speech.isListening ? "停止语音转写" : "开始语音转写")

                Button {
                    save()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canSave ? AppTheme.accent : AppTheme.tertiaryText)
                        .frame(width: 44, height: 44)
                }
                .disabled(!canSave)
                .accessibilityLabel("保存随记")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .leafyGlassSurface(in: Capsule(), fallbackFill: AppTheme.cardBackground, isInteractive: true)
        }
        .padding(.horizontal, AppSpacing.page)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .onChange(of: photoItems) { _, items in
            Task { await load(items) }
        }
        .onChange(of: speech.transcript) { _, transcript in
            text = speechBase + transcript
        }
        .onChange(of: speech.state) { _, state in
            if case .unavailable(let message) = state {
                errorTitle = "无法使用语音转写"
                errorMessage = message
            }
        }
        .alert(errorTitle, isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil; speech.clearMessage() } }
        )) {
            Button("好") { errorMessage = nil; speech.clearMessage() }
        } message: {
            Text(errorMessage ?? "")
        }
        .onDisappear { speech.stop() }
    }

    private func load(_ items: [PhotosPickerItem]) async {
        var loaded: [ScheduleMemoDraftImage] = []
        for item in items.prefix(ScheduleMemoImageStore.maximumImageCount) {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = ImageDataDecoder.decodedImage(from: data) else { continue }
            loaded.append(.init(data: data, image: image))
        }
        draftImages = loaded
    }

    @MainActor
    private func save() {
        guard canSave else { return }
        var filenames: [String] = []
        do {
            for draft in draftImages {
                filenames.append(try ScheduleMemoImageStore.importImage(data: draft.data))
            }
            let memo = ScheduleMemo(body: text)
            modelContext.insert(memo)
            for (index, filename) in filenames.enumerated() {
                modelContext.insert(ScheduleMemoImage(memoID: memo.id, sortOrder: index, localFilename: filename))
            }
            try modelContext.save()
            text = ""
            speechBase = ""
            photoItems = []
            draftImages = []
        } catch {
            try? ScheduleMemoImageStore.deleteFiles(named: filenames)
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

    init(memo: ScheduleMemo) {
        self.memo = memo
        _bodyText = State(initialValue: memo.body)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("随记内容") {
                    TextField("写点什么…", text: $bodyText, axis: .vertical)
                        .lineLimit(5...14)
                }
                Section {
                    Text("正文里的 #标签 和 #学习/Swift 会自动成为标签。")
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .navigationTitle("编辑随记")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        memo.updateBody(bodyText)
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ScheduleMemoReviewView: View {
    @Query private var memos: [ScheduleMemo]
    @Query private var images: [ScheduleMemoImage]
    @State private var page = 0
    @State private var shareCardSource: CommunityPostCardPreviewSource?
    @State private var operationAlert: LeafyOperationAlert?

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
                            linkedTitle: nil,
                            onTag: { _ in },
                            onEdit: {},
                            onConvert: {},
                            onShareCard: {
                                do {
                                    let memoImages = images
                                        .filter { $0.memoID == memo.id }
                                        .sorted { $0.sortOrder < $1.sortOrder }
                                    shareCardSource = try scheduleMemoShareCardSource(memo: memo, images: memoImages)
                                } catch {
                                    operationAlert = .failure(error.localizedDescription)
                                }
                            },
                            onPin: {},
                            onTrash: {}
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
            CommunityPostCardPreviewSheet(source: source)
        }
        .leafyOperationAlert($operationAlert)
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

private struct ScheduleMemoStatisticsView: View {
    @Query private var memos: [ScheduleMemo]
    @State private var selectedDate: Date?

    private var statistics: ScheduleMemoStatistics { .make(memos: memos) }
    private let rows = Array(repeating: GridItem(.fixed(18), spacing: 5), count: 7)

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.card) {
                HStack(spacing: 10) {
                    metric("随记", statistics.memoCount)
                    metric("标签", statistics.tagCount)
                    metric("记录天数", statistics.recordingDayCount)
                }
                AcademicDetailCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("最近 12 周").leafyHeadline()
                        LazyHGrid(rows: rows, spacing: 5) {
                            ForEach(statistics.activityDays) { day in
                                Button { selectedDate = day.date } label: {
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(activityColor(day.count))
                                        .frame(width: 18, height: 18)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(day.date.formatted(date: .long, time: .omitted))，\(day.count) 条随记")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text("颜色越深，表示当天记录越多。点按日期查看当天随记。")
                            .microCaption().foregroundStyle(AppTheme.secondaryText)
                    }
                }
            }
            .leafyAdaptiveContentWidth(maxWidth: 760)
            .padding(.vertical, AppSpacing.card)
        }
        .background(LeafyPageBackground())
        .navigationTitle("记录统计")
        .leafySheet(isPresented: Binding(get: { selectedDate != nil }, set: { if !$0 { selectedDate = nil } })) {
            NavigationStack {
                ScheduleMemoDayView(date: selectedDate ?? Date())
            }
        }
    }

    private func metric(_ title: String, _ value: Int) -> some View {
        VStack(spacing: 5) {
            Text("\(value)").font(.title2.bold()).foregroundStyle(AppTheme.primaryText)
            Text(title).microCaption().foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
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

private struct ScheduleMemoDayView: View {
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
                Text(memo.body.isEmpty ? "图片随记" : memo.body)
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
                        Text(memo.body.isEmpty ? "图片随记" : memo.body).lineLimit(4)
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
        } message: { Text("图片也会从本机删除，此操作无法撤销。") }
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
                in: modelContext,
                saves: saves
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ScheduleYearOverviewView: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    var body: some View {
        TimetableTimeScopeView(
            snapshot: TimetableTimeScopeSnapshot.make(
                currentWeek: SemesterConfig.currentWeek(),
                referenceDate: Date(),
                language: leafyLanguage
            )
        )
    }
}

private func scheduleMemoShareCardSource(
    memo: ScheduleMemo,
    images: [ScheduleMemoImage]
) throws -> CommunityPostCardPreviewSource {
    var photoData: [Data] = []
    for (index, imageRecord) in images.enumerated() {
        guard let data = ScheduleMemoImageStore.data(named: imageRecord.localFilename) else {
            throw CommunityPostCardGenerationError.invalidImage(index + 1)
        }
        photoData.append(data)
    }

    let lines = memo.body
        .split(whereSeparator: \.isNewline)
        .map(String.init)
    let snapshot = CommunityPostCardSnapshot(
        authorName: AppBrand.displayName,
        avatarData: nil,
        dateText: DateFormatters.headerWithTime.string(from: memo.createdAt),
        category: "日程随记",
        title: lines.first.map { String($0.prefix(80)) } ?? "图片随记",
        body: lines.dropFirst().joined(separator: "\n"),
        attachmentNames: [],
        photoData: photoData,
        isAnonymous: false
    )
    return CommunityPostCardPreviewSource(content: .snapshot(snapshot))
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
