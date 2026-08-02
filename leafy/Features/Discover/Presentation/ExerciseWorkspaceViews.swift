import SwiftData
import SwiftUI

struct ExerciseTopicOption: Identifiable, Hashable {
    let id: String
    let title: String
    let spaceID: String
    let categoryRawValue: String
    let icon: String

    static let other = fixed(.other)

    var destination: ExerciseSpaceDestination {
        if let id = UUID(uuidString: spaceID) { return .custom(id) }
        return .fixed(ExerciseSpaceCategory.normalized(categoryRawValue))
    }

    static func fixed(_ category: ExerciseSpaceCategory) -> ExerciseTopicOption {
        ExerciseTopicOption(
            id: ExerciseSpaceDestination.fixed(category).id,
            title: category.rawValue,
            spaceID: "",
            categoryRawValue: category.rawValue,
            icon: category.icon
        )
    }

    static func custom(_ space: ExerciseSpace) -> ExerciseTopicOption {
        let category = ExerciseSpaceCategory.normalized(space.kindRawValue)
        return ExerciseTopicOption(
            id: ExerciseSpaceDestination.custom(space.id).id,
            title: space.title,
            spaceID: space.id.uuidString,
            categoryRawValue: category.rawValue,
            icon: category.icon
        )
    }

    @MainActor
    static func options(spaces: [ExerciseSpace]) -> [ExerciseTopicOption] {
        ExerciseSpaceCategory.allCases.map { fixed($0) }
            + spaces.filter { !$0.isArchived }.map { custom($0) }
    }

    static func option(for record: ExerciseRecord, spaces: [ExerciseSpace]) -> ExerciseTopicOption {
        if let id = UUID(uuidString: record.spaceID) {
            if let space = spaces.first(where: { $0.id == id }) { return .custom(space) }
            return ExerciseTopicOption(
                id: ExerciseSpaceDestination.custom(id).id,
                title: "运动空间",
                spaceID: record.spaceID,
                categoryRawValue: record.categoryRawValue,
                icon: ExerciseSpaceCategory.normalized(record.categoryRawValue).icon
            )
        }
        return .fixed(record.category)
    }

    static func option(for destination: ExerciseSpaceDestination, spaces: [ExerciseSpace]) -> ExerciseTopicOption {
        switch destination {
        case .fixed(let category): return .fixed(category)
        case .custom(let id):
            if let space = spaces.first(where: { $0.id == id }) { return .custom(space) }
            return ExerciseTopicOption(
                id: destination.id,
                title: "运动空间",
                spaceID: id.uuidString,
                categoryRawValue: ExerciseSpaceCategory.other.rawValue,
                icon: ExerciseSpaceCategory.other.icon
            )
        }
    }
}

struct ExerciseSession: Identifiable {
    let id = UUID()
    let startedAt: Date
    let topic: ExerciseTopicOption
}

struct ExerciseTimerPanel: View {
    let topicOptions: [ExerciseTopicOption]
    let lockedTopic: ExerciseTopicOption?
    @Binding var selectedTopic: ExerciseTopicOption
    @Binding var activeSession: ExerciseSession?
    let stopAction: (ExerciseSession, Date) -> Void

    private var effectiveTopic: ExerciseTopicOption {
        lockedTopic ?? selectedTopic
    }

    var body: some View {
        AcademicDetailCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                HStack(alignment: .top, spacing: AppSpacing.compact) {
                    LeafyIconBadge(
                        systemName: activeSession == nil ? "figure.run" : "figure.run.circle.fill",
                        tint: AppTheme.exercise
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(activeSession == nil ? "开始运动" : "运动进行中")
                            .leafyHeadline()
                            .foregroundStyle(AppTheme.primaryText)
                        Text(activeSession == nil ? "点击后立即开始计时，停止时保存为运动记录。" : "停止后会写入当前运动空间。")
                            .leafySubheadline()
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                }

                if let lockedTopic {
                    Label(lockedTopic.title, systemImage: lockedTopic.icon)
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                } else {
                    Picker("运动空间", selection: $selectedTopic) {
                        ForEach(topicOptions) { option in
                            Label(option.title, systemImage: option.icon).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if let activeSession {
                    TimelineView(.periodic(from: activeSession.startedAt, by: 1)) { context in
                        Text(StudyTimeDurationFormatter.timerText(for: context.date.timeIntervalSince(activeSession.startedAt)))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(AppTheme.primaryText)
                            .monospacedDigit()
                    }

                    Button(role: .destructive) {
                        let session = activeSession
                        self.activeSession = nil
                        stopAction(session, Date())
                    } label: {
                        Label("停止并保存", systemImage: "stop.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .foregroundStyle(.white)
                            .background(Capsule().fill(AppTheme.danger))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        activeSession = ExerciseSession(startedAt: Date(), topic: effectiveTopic)
                    } label: {
                        Label("开始运动", systemImage: "play.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .foregroundStyle(.white)
                            .background(Capsule().fill(AppTheme.exercise))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct ExerciseRecordDraft {
    var spaceID: String
    var categoryRawValue: String
    var startedAt: Date
    var endedAt: Date
    var content: String
    var location: String
    var note: String
}

struct ExerciseRecordEditorView: View {
    let record: ExerciseRecord?
    let topicOptions: [ExerciseTopicOption]
    let lockedTopic: ExerciseTopicOption?
    let onSave: (ExerciseRecordDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTopic: ExerciseTopicOption
    @State private var startedAt: Date
    @State private var endedAt: Date
    @State private var content: String
    @State private var location: String
    @State private var note: String

    init(
        record: ExerciseRecord?,
        topicOptions: [ExerciseTopicOption],
        initialTopic: ExerciseTopicOption,
        lockedTopic: ExerciseTopicOption? = nil,
        initialDate: Date? = nil,
        onSave: @escaping (ExerciseRecordDraft) -> Void
    ) {
        let now = Date()
        let calendar = Calendar.current
        let defaultEnd: Date
        if let initialDate, record == nil {
            let components = calendar.dateComponents([.hour, .minute], from: now)
            defaultEnd = calendar.date(
                bySettingHour: components.hour ?? 18,
                minute: components.minute ?? 0,
                second: 0,
                of: initialDate
            ) ?? initialDate
        } else {
            defaultEnd = now
        }
        let start = calendar.date(byAdding: .hour, value: -1, to: defaultEnd) ?? defaultEnd
        let options = topicOptions.isEmpty ? [.other] : topicOptions
        let resolved = lockedTopic
            ?? record.map { ExerciseTopicOption.option(for: $0, spaces: []) }
            ?? options.first(where: { $0.id == initialTopic.id })
            ?? initialTopic
        self.record = record
        self.topicOptions = options
        self.lockedTopic = lockedTopic
        self.onSave = onSave
        _selectedTopic = State(initialValue: options.first(where: { $0.id == resolved.id }) ?? resolved)
        _startedAt = State(initialValue: record?.startedAt ?? start)
        _endedAt = State(initialValue: record?.endedAt ?? defaultEnd)
        _content = State(initialValue: record?.content ?? resolved.title)
        _location = State(initialValue: record?.location ?? "校园")
        _note = State(initialValue: record?.note ?? "")
    }

    private var effectiveTopic: ExerciseTopicOption { lockedTopic ?? selectedTopic }
    private var trimmedContent: String { content.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedLocation: String { location.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedNote: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("开始时间", selection: $startedAt, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("结束时间", selection: $endedAt, displayedComponents: [.date, .hourAndMinute])
                    if endedAt <= startedAt {
                        Text("结束时间必须晚于开始时间。")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.danger)
                    }
                }

                Section {
                    if let lockedTopic {
                        Label(lockedTopic.title, systemImage: lockedTopic.icon)
                    } else {
                        Picker("运动空间", selection: $selectedTopic) {
                            ForEach(topicOptions) { option in
                                Label(option.title, systemImage: option.icon).tag(option)
                            }
                        }
                    }
                    TextField("运动内容", text: $content)
                    TextField("地点", text: $location)
                    TextField("备注", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(record == nil ? "添加运动记录" : "编辑运动记录")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(ExerciseRecordDraft(
                            spaceID: effectiveTopic.spaceID,
                            categoryRawValue: effectiveTopic.categoryRawValue,
                            startedAt: startedAt,
                            endedAt: endedAt,
                            content: trimmedContent,
                            location: trimmedLocation,
                            note: trimmedNote
                        ))
                        dismiss()
                    }
                    .disabled(trimmedContent.isEmpty || trimmedLocation.isEmpty || endedAt <= startedAt)
                }
            }
        }
    }
}

struct ExerciseRecordRow: View {
    let record: ExerciseRecord
    let editAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.compact) {
            VStack(alignment: .leading, spacing: 7) {
                Text(record.content)
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)
                Text(timeRangeText)
                    .leafySubheadline()
                    .foregroundStyle(AppTheme.secondaryText)
                HStack(spacing: 8) {
                    Label(record.location, systemImage: "mappin.and.ellipse")
                    Text(durationText(record.endedAt.timeIntervalSince(record.startedAt)))
                }
                .microCaption()
                .foregroundStyle(AppTheme.secondaryText)
                if !record.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(record.note)
                        .leafySubheadline()
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            Spacer(minLength: AppSpacing.micro)
            VStack(spacing: AppSpacing.micro) {
                Button(action: editAction) {
                    Image(systemName: "pencil")
                        .frame(width: 44, height: 44)
                        .background(AppTheme.softFill, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("编辑运动记录")
                Button(role: .destructive, action: deleteAction) {
                    Image(systemName: "trash")
                        .foregroundStyle(AppTheme.danger)
                        .frame(width: 44, height: 44)
                        .background(AppTheme.danger.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除运动记录")
            }
        }
        .padding(.vertical, 4)
    }

    private var timeRangeText: String {
        let start = DateFormatters.headerWithTime.string(from: record.startedAt)
        let end = Calendar.current.isDate(record.startedAt, inSameDayAs: record.endedAt)
            ? DateFormatters.timeOnly.string(from: record.endedAt)
            : DateFormatters.headerWithTime.string(from: record.endedAt)
        return "\(start) - \(end)"
    }
}

private enum ExerciseWorkspaceListItem: Identifiable {
    case fixed(ExerciseSpaceCategory)
    case custom(ExerciseSpace)

    var id: String { destination.id }
    var destination: ExerciseSpaceDestination {
        switch self {
        case .fixed(let category): return .fixed(category)
        case .custom(let space): return .custom(space.id)
        }
    }
    var title: String {
        switch self {
        case .fixed(let category): return category.rawValue
        case .custom(let space): return space.title
        }
    }
    var icon: String {
        switch self {
        case .fixed(let category): return category.icon
        case .custom(let space): return ExerciseSpaceCategory.normalized(space.kindRawValue).icon
        }
    }
    var space: ExerciseSpace? {
        if case .custom(let space) = self { return space }
        return nil
    }
}

struct ExerciseWorkspaceSectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExerciseSpace.updatedAt, order: .reverse) private var spaces: [ExerciseSpace]
    @Query(sort: \ExerciseRecord.startedAt, order: .reverse) private var records: [ExerciseRecord]

    let openRoute: (AcademicDetailRoute) -> Void

    @State private var showingEditor = false
    @State private var editingSpace: ExerciseSpace?
    @State private var pendingDeletion: ExerciseSpace?
    @State private var pendingFullDeletion: ExerciseSpace?
    @State private var operationAlert: LeafyOperationAlert?

    private var activeItems: [ExerciseWorkspaceListItem] {
        ExerciseSpaceCategory.allCases.map(ExerciseWorkspaceListItem.fixed)
            + spaces.filter { !$0.isArchived }.map(ExerciseWorkspaceListItem.custom)
    }

    private var archivedItems: [ExerciseWorkspaceListItem] {
        spaces.filter(\.isArchived).map(ExerciseWorkspaceListItem.custom)
    }

    private var overviewProjection: ActivityProjection {
        ActivityProjection.make(
            intervals: ExerciseActivityRecordAdapter.intervals(from: records),
            channel: .exercise,
            interval: ActivityDateRangeResolver.recentWeeks()
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.card) {
            PersonalActivityOverviewCard(channel: .exercise, projection: overviewProjection) {
                openRoute(.exerciseActivity)
            }

            HStack {
                AcademicDetailSectionHeader(title: "运动空间")
                Spacer()
                CareerSectionAddButton(title: "新建运动空间", systemName: "plus") {
                    showingEditor = true
                }
            }

            AcademicDetailCard {
                VStack(spacing: 0) {
                    ForEach(Array(activeItems.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { AcademicDetailDivider() }
                        ExerciseWorkspaceRow(
                            item: item,
                            records: records.filter { $0.belongs(to: item.destination) },
                            openAction: { openRoute(.exerciseWorkspace(item.destination)) },
                            editAction: item.space.map { space in { editingSpace = space } },
                            deleteAction: item.space.map { space in { pendingDeletion = space } }
                        )
                    }
                }
            }

            if !archivedItems.isEmpty {
                AcademicDetailSectionHeader(title: "已归档运动空间")
                AcademicDetailCard {
                    VStack(spacing: 0) {
                        ForEach(Array(archivedItems.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { AcademicDetailDivider() }
                            ExerciseWorkspaceRow(
                                item: item,
                                records: records.filter { $0.belongs(to: item.destination) },
                                openAction: { openRoute(.exerciseWorkspace(item.destination)) },
                                editAction: item.space.map { space in { editingSpace = space } },
                                deleteAction: item.space.map { space in { pendingDeletion = space } }
                            )
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            ExerciseSpaceEditorSheet(space: nil) { title, category, archived in
                let now = Date()
                modelContext.insert(ExerciseSpace(
                    title: title,
                    kindRawValue: category.rawValue,
                    createdAt: now,
                    updatedAt: now,
                    isArchived: archived
                ))
                save("运动空间已创建。")
            }
        }
        .sheet(item: $editingSpace) { space in
            ExerciseSpaceEditorSheet(space: space) { title, category, archived in
                space.title = title
                space.kindRawValue = category.rawValue
                space.isArchived = archived
                space.updatedAt = Date()
                save("运动空间已保存。")
            }
        }
        .confirmationDialog(
            "删除运动空间？",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除空间，记录移到其他") {
                if let space = pendingDeletion { deleteKeepingRecords(space) }
                pendingDeletion = nil
            }
            Button("连同记录一起删除", role: .destructive) {
                pendingFullDeletion = pendingDeletion
                pendingDeletion = nil
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("可以只删除运动空间并把记录移到“其他”，也可以同时删除空间和全部记录。")
        }
        .confirmationDialog(
            "同时删除运动空间和记录？",
            isPresented: Binding(
                get: { pendingFullDeletion != nil },
                set: { if !$0 { pendingFullDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除空间和记录", role: .destructive) {
                if let space = pendingFullDeletion { deleteWithRecords(space) }
                pendingFullDeletion = nil
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作无法恢复。")
        }
        .leafyOperationAlert($operationAlert)
    }

    private func deleteKeepingRecords(_ space: ExerciseSpace) {
        ExerciseSpaceRecordMutation.delete(
            space,
            records: records,
            includingRecords: false,
            in: modelContext
        )
        save("运动空间已删除，记录已移到其他。")
    }

    private func deleteWithRecords(_ space: ExerciseSpace) {
        ExerciseSpaceRecordMutation.delete(
            space,
            records: records,
            includingRecords: true,
            in: modelContext
        )
        save("运动空间和记录已删除。")
    }

    private func save(_ message: String) {
        do {
            try modelContext.save()
            operationAlert = .success(message)
        } catch {
            operationAlert = .failure(error.localizedDescription)
        }
    }
}

private struct ExerciseWorkspaceRow: View {
    let item: ExerciseWorkspaceListItem
    let records: [ExerciseRecord]
    let openAction: () -> Void
    let editAction: (() -> Void)?
    let deleteAction: (() -> Void)?

    var body: some View {
        HStack(spacing: AppSpacing.compact) {
            Button(action: openAction) {
                HStack(spacing: AppSpacing.compact) {
                    LeafyIconBadge(systemName: item.icon, tint: AppTheme.exercise)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .leafyHeadline()
                            .foregroundStyle(AppTheme.primaryText)
                        Text("\(records.count) 条记录 · \(durationText(records.reduce(0) { $0 + max($1.endedAt.timeIntervalSince($1.startedAt), 0) }))")
                            .leafySubheadline()
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                    LeafyDisclosureIndicator()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if editAction != nil || deleteAction != nil {
                Menu {
                    if let editAction {
                        Button(action: editAction) { Label("编辑运动空间", systemImage: "pencil") }
                    }
                    if let deleteAction {
                        Button(role: .destructive, action: deleteAction) { Label("删除运动空间", systemImage: "trash") }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("更多运动空间操作")
            }
        }
        .padding(.vertical, 7)
    }
}

private struct ExerciseSpaceEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let space: ExerciseSpace?
    let onSave: (String, ExerciseSpaceCategory, Bool) -> Void

    @State private var title: String
    @State private var category: ExerciseSpaceCategory
    @State private var isArchived: Bool

    init(space: ExerciseSpace?, onSave: @escaping (String, ExerciseSpaceCategory, Bool) -> Void) {
        self.space = space
        self.onSave = onSave
        _title = State(initialValue: space?.title ?? "")
        _category = State(initialValue: space.map { ExerciseSpaceCategory.normalized($0.kindRawValue) } ?? .other)
        _isArchived = State(initialValue: space?.isArchived ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("空间名称", text: $title)
                    Picker("运动类型", selection: $category) {
                        ForEach(ExerciseSpaceCategory.allCases) { item in
                            Label(item.rawValue, systemImage: item.icon).tag(item)
                        }
                    }
                    if space != nil { Toggle("归档运动空间", isOn: $isArchived) }
                }
            }
            .navigationTitle(space == nil ? "新建运动空间" : "编辑运动空间")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(title.trimmingCharacters(in: .whitespacesAndNewlines), category, isArchived)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct ExerciseWorkspaceDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExerciseSpace.updatedAt, order: .reverse) private var spaces: [ExerciseSpace]
    @Query(sort: \ExerciseRecord.startedAt, order: .reverse) private var records: [ExerciseRecord]

    let destination: ExerciseSpaceDestination
    let openRoute: (AcademicDetailRoute) -> Void

    @State private var activeSession: ExerciseSession?
    @State private var selectedTopic = ExerciseTopicOption.other
    @State private var showingEditor = false
    @State private var editingRecord: ExerciseRecord?
    @State private var showingClearConfirmation = false
    @State private var operationAlert: LeafyOperationAlert?

    private var topic: ExerciseTopicOption {
        ExerciseTopicOption.option(for: destination, spaces: spaces)
    }

    private var visibleRecords: [ExerciseRecord] {
        records.filter { $0.belongs(to: destination) }
    }

    private var projection: ActivityProjection {
        ActivityProjection.make(
            intervals: ExerciseActivityRecordAdapter.intervals(from: visibleRecords),
            channel: .exercise,
            interval: ActivityDateRangeResolver.recentWeeks()
        )
    }

    var body: some View {
        AcademicDetailScrollContainer {
            PersonalActivityOverviewCard(channel: .exercise, projection: projection) {
                openRoute(.exerciseActivity)
            }
            ExerciseTimerPanel(
                topicOptions: ExerciseTopicOption.options(spaces: spaces),
                lockedTopic: topic,
                selectedTopic: $selectedTopic,
                activeSession: $activeSession,
                stopAction: stopSession
            )
            HStack {
                AcademicDetailSectionHeader(title: "运动记录")
                Spacer()
                CareerSectionAddButton(title: "添加记录", systemName: "plus") { showingEditor = true }
            }
            if visibleRecords.isEmpty {
                AcademicDetailCard {
                    ContentUnavailableView("暂无运动记录", systemImage: topic.icon, description: Text("开始一次运动，或补记过去的运动时间。"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.compact)
                }
            } else {
                AcademicDetailCard {
                    VStack(spacing: 0) {
                        ForEach(Array(visibleRecords.enumerated()), id: \.element.id) { index, record in
                            if index > 0 { AcademicDetailDivider() }
                            ExerciseRecordRow(
                                record: record,
                                editAction: { editingRecord = record },
                                deleteAction: { delete(record) }
                            )
                        }
                    }
                }
            }
            AcademicDetailFooterText(text: "运动记录仅保存在当前设备，不会自动计入阳光长跑。")
        }
        .navigationTitle(topic.title)
        .leafyInlineNavigationTitle()
        .toolbar {
            if destination.fixedCategory != nil {
                ToolbarItem(placement: .leafyTrailing) {
                    Menu {
                        Button(role: .destructive) { showingClearConfirmation = true } label: {
                            Label("清空运动记录", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("更多运动空间操作")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            ExerciseRecordEditorView(
                record: nil,
                topicOptions: ExerciseTopicOption.options(spaces: spaces),
                initialTopic: topic,
                lockedTopic: topic
            ) { insert($0) }
        }
        .sheet(item: $editingRecord) { record in
            ExerciseRecordEditorView(
                record: record,
                topicOptions: ExerciseTopicOption.options(spaces: spaces),
                initialTopic: topic,
                lockedTopic: topic
            ) { update(record, with: $0) }
        }
        .confirmationDialog("清空运动空间？", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
            Button("删除全部运动记录", role: .destructive) { clearRecords() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除这个固定运动空间中的全部记录，空间本身会保留。此操作无法恢复。")
        }
        .leafyOperationAlert($operationAlert)
    }

    private func insert(_ draft: ExerciseRecordDraft) {
        let now = Date()
        modelContext.insert(ExerciseRecord(
            spaceID: draft.spaceID,
            categoryRawValue: draft.categoryRawValue,
            startedAt: draft.startedAt,
            endedAt: draft.endedAt,
            content: draft.content,
            location: draft.location,
            note: draft.note,
            createdAt: now,
            updatedAt: now
        ))
        save("运动记录已添加。")
    }

    private func update(_ record: ExerciseRecord, with draft: ExerciseRecordDraft) {
        record.startedAt = draft.startedAt
        record.endedAt = draft.endedAt
        record.content = draft.content
        record.location = draft.location
        record.note = draft.note
        record.updatedAt = Date()
        save("运动记录已保存。")
    }

    private func stopSession(_ session: ExerciseSession, endedAt: Date) {
        let endedAt = max(endedAt, session.startedAt.addingTimeInterval(60))
        let now = Date()
        modelContext.insert(ExerciseRecord(
            spaceID: topic.spaceID,
            categoryRawValue: topic.categoryRawValue,
            startedAt: session.startedAt,
            endedAt: endedAt,
            content: topic.title,
            location: "校园",
            createdAt: now,
            updatedAt: now
        ))
        save("运动记录已保存。")
    }

    private func delete(_ record: ExerciseRecord) {
        modelContext.delete(record)
        save("运动记录已删除。")
    }

    private func clearRecords() {
        ExerciseSpaceRecordMutation.clear(destination, records: records, in: modelContext)
        save("运动空间记录已清空。")
    }

    private func save(_ message: String) {
        do {
            try modelContext.save()
            operationAlert = .success(message)
        } catch {
            operationAlert = .failure(error.localizedDescription)
        }
    }
}
