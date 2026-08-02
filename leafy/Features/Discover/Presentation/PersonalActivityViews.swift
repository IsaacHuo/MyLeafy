import Charts
import SwiftData
import SwiftUI

private enum ActivityScopeID {
    static let all = "activity-scope-all"
}

struct ActivityScopeOption: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let focusDestination: LearningWorkspaceDestination?
    let exerciseDestination: ExerciseSpaceDestination?

    static let allFocus = ActivityScopeOption(
        id: ActivityScopeID.all,
        title: "全部学习空间",
        icon: "square.grid.2x2",
        focusDestination: nil,
        exerciseDestination: nil
    )

    static let allExercise = ActivityScopeOption(
        id: ActivityScopeID.all,
        title: "全部运动空间",
        icon: "square.grid.2x2",
        focusDestination: nil,
        exerciseDestination: nil
    )
}

struct PersonalActivityOverviewCard: View {
    let channel: PersonalActivityChannel
    let projection: ActivityProjection
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AcademicDetailCard {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    HStack(spacing: AppSpacing.compact) {
                        LeafyIconBadge(
                            systemName: channel.icon,
                            tint: channel == .focus ? AppTheme.accent : AppTheme.exercise
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(channel == .focus ? "专注活动" : "运动活动")
                                .leafyHeadline()
                                .foregroundStyle(AppTheme.primaryText)
                            Text(overviewSubtitle)
                                .leafySubheadline()
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        Spacer()
                        LeafyDisclosureIndicator()
                    }

                    PersonalActivityHeatmap(
                        projection: projection,
                        channel: channel,
                        compact: true,
                        selectedDay: .constant(nil)
                    )
                    .allowsHitTesting(false)

                    HStack(spacing: AppSpacing.card) {
                        Label("本周 \(durationText(weekDuration))", systemImage: "calendar")
                        Label("连续 \(projection.currentStreak) 天", systemImage: "flame.fill")
                    }
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(channel.rawValue)活动，\(overviewSubtitle)，连续 \(projection.currentStreak) 天")
        .accessibilityHint("轻点查看完整活动")
    }

    private var weekDuration: TimeInterval {
        let week = Calendar.current.dateInterval(of: .weekOfYear, for: Date())
        return projection.days
            .filter { week?.contains($0.date) == true }
            .reduce(0) { $0 + $1.duration }
    }

    private var overviewSubtitle: String {
        projection.activeDayCount == 0
            ? "最近 4 周暂无记录"
            : "最近 4 周活跃 \(projection.activeDayCount) 天"
    }
}

struct PersonalActivityHeatmap: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let projection: ActivityProjection
    let channel: PersonalActivityChannel
    let compact: Bool
    @Binding var selectedDay: ActivityDay?

    var body: some View {
        if compact {
            chart
                .frame(height: 112)
        } else {
            GeometryReader { geometry in
                ScrollViewReader { reader in
                    ScrollView(.horizontal, showsIndicators: projection.weekCount > 22) {
                        HStack(spacing: 0) {
                            chart
                                .frame(
                                    width: max(geometry.size.width, CGFloat(projection.weekCount) * 17 + 46),
                                    height: 154
                                )
                            Color.clear
                                .frame(width: 1, height: 1)
                                .id("personal-activity-latest")
                        }
                    }
                    .onAppear {
                        guard projection.weekCount > 22 else { return }
                        reader.scrollTo("personal-activity-latest", anchor: .trailing)
                    }
                    .onChange(of: projection.weekCount) { _, weekCount in
                        guard weekCount > 22 else { return }
                        reader.scrollTo("personal-activity-latest", anchor: .trailing)
                    }
                }
                .leafyTransparentHorizontalScrollRail()
            }
            .frame(height: 154)
        }
    }

    private var chart: some View {
        Chart(projection.days) { day in
            RectangleMark(
                x: .value("周", day.weekIndex),
                y: .value("星期", day.weekdayIndex),
                width: .ratio(0.72),
                height: .ratio(0.72)
            )
            .cornerRadius(3)
            .foregroundStyle(color(for: day))
            .accessibilityLabel(dayAccessibilityLabel(day))
            .accessibilityValue(durationText(day.duration))
        }
        .chartXScale(domain: 0...max(projection.weekCount - 1, 1))
        .chartYScale(domain: -0.5...6.5)
        .chartXAxis {
            if !compact {
                AxisMarks(values: monthLabelWeeks) { value in
                    AxisValueLabel {
                        if let week = value.as(Int.self), let label = monthLabels[week] {
                            Text(label)
                                .font(.caption2)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                    AxisTick().foregroundStyle(.clear)
                    AxisGridLine().foregroundStyle(.clear)
                }
            }
        }
        .chartYAxis {
            if !compact {
                AxisMarks(values: [0, 2, 4]) { value in
                    AxisValueLabel {
                        if let weekday = value.as(Int.self) {
                            Text(weekdayLabel(weekday))
                                .font(.caption2)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                    AxisTick().foregroundStyle(.clear)
                    AxisGridLine().foregroundStyle(.clear)
                }
            }
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            if !compact {
                GeometryReader { geometry in
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture()
                                .onEnded { value in
                                    selectDay(at: value.location, proxy: proxy, geometry: geometry)
                                }
                        )
                }
            }
        }
    }

    private var monthLabels: [Int: String] {
        var labels: [Int: String] = [:]
        var seenMonths = Set<String>()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月"
        let keyFormatter = DateFormatter()
        keyFormatter.calendar = formatter.calendar
        keyFormatter.locale = Locale(identifier: "en_US_POSIX")
        keyFormatter.dateFormat = "yyyy-MM"

        for day in projection.days where day.isInRange {
            let key = keyFormatter.string(from: day.date)
            if seenMonths.insert(key).inserted {
                labels[day.weekIndex] = formatter.string(from: day.date)
            }
        }
        return labels
    }

    private var monthLabelWeeks: [Int] {
        monthLabels.keys.sorted()
    }

    private func color(for day: ActivityDay) -> Color {
        guard day.isInRange else { return .clear }
        if day.isFuture {
            return AppTheme.softFill.opacity(colorScheme == .dark ? 0.28 : 0.45)
        }
        guard day.intensity > 0 else {
            return AppTheme.softFill.opacity(colorScheme == .dark ? 0.62 : 0.9)
        }

        let base = channel == .focus ? AppTheme.accent : AppTheme.exercise
        if colorSchemeContrast == .increased {
            switch day.intensity {
            case 1: return base.opacity(0.46)
            case 2: return base.opacity(0.64)
            case 3: return base.opacity(0.82)
            default: return base
            }
        }
        switch day.intensity {
        case 1: return base.opacity(colorScheme == .dark ? 0.34 : 0.28)
        case 2: return base.opacity(colorScheme == .dark ? 0.52 : 0.48)
        case 3: return base.opacity(colorScheme == .dark ? 0.72 : 0.7)
        default: return base.opacity(0.96)
        }
    }

    private func dayAccessibilityLabel(_ day: ActivityDay) -> String {
        let date = DateFormatters.header.string(from: day.date)
        if !day.isInRange { return "\(date)，不在当前范围" }
        if day.isFuture { return "\(date)，尚未到达" }
        return "\(date)，\(channel.rawValue) \(durationText(day.duration))，\(day.recordCount) 条记录"
    }

    private func weekdayLabel(_ value: Int) -> String {
        switch value {
        case 0: return "一"
        case 2: return "三"
        case 4: return "五"
        default: return ""
        }
    }

    private func selectDay(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let anchor = proxy.plotFrame else { return }
        let frame = geometry[anchor]
        let plotLocation = CGPoint(x: location.x - frame.origin.x, y: location.y - frame.origin.y)
        guard plotLocation.x >= 0, plotLocation.y >= 0,
              plotLocation.x <= frame.width, plotLocation.y <= frame.height,
              let week: Int = proxy.value(atX: plotLocation.x),
              let weekday: Int = proxy.value(atY: plotLocation.y),
              let day = projection.days.first(where: { $0.weekIndex == week && $0.weekdayIndex == weekday }),
              day.isInRange,
              !day.isFuture
        else { return }
        selectedDay = day
    }
}

struct PersonalActivityView: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \LearningProject.updatedAt, order: .reverse) private var learningProjects: [LearningProject]
    @Query(sort: \StudyTimeRecord.startedAt, order: .reverse) private var focusRecords: [StudyTimeRecord]
    @Query(sort: \ExerciseSpace.updatedAt, order: .reverse) private var exerciseSpaces: [ExerciseSpace]
    @Query(sort: \ExerciseRecord.startedAt, order: .reverse) private var exerciseRecords: [ExerciseRecord]

    @State private var channel: PersonalActivityChannel
    @State private var focusRange: ActivityRange = .semester
    @State private var exerciseRange: ActivityRange = .semester
    @State private var focusScopeID = ActivityScopeID.all
    @State private var exerciseScopeID = ActivityScopeID.all
    @State private var selectedDay: ActivityDay?

    @State private var selectedFocusTopic = StudyFocusTopicOption.none
    @State private var activeFocusSession: StudyFocusSession?
    @State private var showingFocusEditor = false
    @State private var focusEditorDate: Date?
    @State private var editingFocusRecord: StudyTimeRecord?

    @State private var selectedExerciseTopic = ExerciseTopicOption.other
    @State private var activeExerciseSession: ExerciseSession?
    @State private var showingExerciseEditor = false
    @State private var exerciseEditorDate: Date?
    @State private var editingExerciseRecord: ExerciseRecord?
    @State private var operationAlert: LeafyOperationAlert?

    init(initialChannel: PersonalActivityChannel = .focus) {
        _channel = State(initialValue: initialChannel)
    }

    private var currentRange: ActivityRange {
        channel == .focus ? focusRange : exerciseRange
    }

    private var currentProjection: ActivityProjection {
        ActivityProjection.make(
            intervals: channel == .focus
                ? FocusActivityRecordAdapter.intervals(from: visibleFocusRecords)
                : ExerciseActivityRecordAdapter.intervals(from: visibleExerciseRecords),
            channel: channel,
            interval: ActivityDateRangeResolver.interval(for: currentRange)
        )
    }

    private var focusScopeOptions: [ActivityScopeOption] {
        let fixed = LearningMaterialCategory.fixedSpaceOrder.map { category in
            ActivityScopeOption(
                id: LearningWorkspaceDestination.fixed(category).id,
                title: category.rawValue,
                icon: StudyFocusTopicOption.fixed(category).icon,
                focusDestination: .fixed(category),
                exerciseDestination: nil
            )
        }
        let custom = learningProjects.map { project in
            ActivityScopeOption(
                id: LearningWorkspaceDestination.project(project.id).id,
                title: project.title,
                icon: project.kind.icon,
                focusDestination: .project(project.id),
                exerciseDestination: nil
            )
        }
        return [.allFocus] + fixed + custom
    }

    private var exerciseScopeOptions: [ActivityScopeOption] {
        let fixed = ExerciseSpaceCategory.allCases.map { category in
            ActivityScopeOption(
                id: ExerciseSpaceDestination.fixed(category).id,
                title: category.rawValue,
                icon: category.icon,
                focusDestination: nil,
                exerciseDestination: .fixed(category)
            )
        }
        let custom = exerciseSpaces.map { space in
            ActivityScopeOption(
                id: ExerciseSpaceDestination.custom(space.id).id,
                title: space.title,
                icon: ExerciseSpaceCategory.normalized(space.kindRawValue).icon,
                focusDestination: nil,
                exerciseDestination: .custom(space.id)
            )
        }
        return [.allExercise] + fixed + custom
    }

    private var visibleFocusRecords: [StudyTimeRecord] {
        guard let destination = focusScopeOptions.first(where: { $0.id == focusScopeID })?.focusDestination else {
            return focusRecords
        }
        return focusRecords.filter { $0.belongs(to: destination) }
    }

    private var visibleExerciseRecords: [ExerciseRecord] {
        guard let destination = exerciseScopeOptions.first(where: { $0.id == exerciseScopeID })?.exerciseDestination else {
            return exerciseRecords
        }
        return exerciseRecords.filter { $0.belongs(to: destination) }
    }

    private var focusTopicOptions: [StudyFocusTopicOption] {
        StudyFocusTopicOption.options(projects: learningProjects)
    }

    private var exerciseTopicOptions: [ExerciseTopicOption] {
        ExerciseTopicOption.options(spaces: exerciseSpaces)
    }

    var body: some View {
        AcademicDetailScrollContainer {
            channelPicker
            controlsCard
            activityCard
            timerContent
            recordsContent
            AcademicDetailFooterText(text: "个人活动记录仅保存在当前设备；专注、运动和校园热力图使用互相独立的数据。")
        }
        .navigationTitle("活动")
        .leafyInlineNavigationTitle()
        .sheet(item: $selectedDay) { day in
            dayDetail(day)
        }
        .sheet(isPresented: $showingFocusEditor, onDismiss: { focusEditorDate = nil }) {
            StudyTimeRecordEditorView(
                record: nil,
                topicOptions: focusTopicOptions,
                initialTopic: selectedFocusTopic,
                initialDate: focusEditorDate
            ) { draft in
                insertFocusRecord(draft)
            }
        }
        .sheet(item: $editingFocusRecord) { record in
            StudyTimeRecordEditorView(
                record: record,
                topicOptions: focusTopicOptions,
                initialTopic: StudyFocusTopicOption.option(for: record, projects: learningProjects)
            ) { draft in
                updateFocusRecord(record, with: draft)
            }
        }
        .sheet(isPresented: $showingExerciseEditor, onDismiss: { exerciseEditorDate = nil }) {
            ExerciseRecordEditorView(
                record: nil,
                topicOptions: exerciseTopicOptions,
                initialTopic: selectedExerciseTopic,
                initialDate: exerciseEditorDate
            ) { draft in
                insertExerciseRecord(draft)
            }
        }
        .sheet(item: $editingExerciseRecord) { record in
            ExerciseRecordEditorView(
                record: record,
                topicOptions: exerciseTopicOptions,
                initialTopic: ExerciseTopicOption.option(for: record, spaces: exerciseSpaces)
            ) { draft in
                updateExerciseRecord(record, with: draft)
            }
        }
        .leafyOperationAlert($operationAlert)
    }

    private var channelPicker: some View {
        Picker("活动类型", selection: $channel) {
            ForEach(PersonalActivityChannel.allCases) { item in
                Label(item.rawValue, systemImage: item.icon).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: channel) { _, _ in selectedDay = nil }
    }

    private var controlsCard: some View {
        AcademicDetailCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Picker("时间范围", selection: rangeBinding) {
                    ForEach(ActivityRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                Picker(channel == .focus ? "学习空间" : "运动空间", selection: scopeBinding) {
                    ForEach(channel == .focus ? focusScopeOptions : exerciseScopeOptions) { option in
                        Label(option.title, systemImage: option.icon).tag(option.id)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var activityCard: some View {
        AcademicDetailCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(currentRange.rawValue)\(channel.rawValue) \(durationText(currentProjection.totalDuration))")
                            .leafyHeadline()
                            .foregroundStyle(AppTheme.primaryText)
                        Text(currentScopeTitle)
                            .leafySubheadline()
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                    Label("少 → 多", systemImage: "square.grid.3x3.fill")
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                }

                PersonalActivityHeatmap(
                    projection: currentProjection,
                    channel: channel,
                    compact: false,
                    selectedDay: $selectedDay
                )

                HStack(spacing: 0) {
                    ActivityMetric(title: "活跃", value: "\(currentProjection.activeDayCount) 天")
                    ActivityMetric(title: "最长连续", value: "\(currentProjection.longestStreak) 天")
                    ActivityMetric(title: "当前连续", value: "\(currentProjection.currentStreak) 天")
                }
            }
        }
    }

    @ViewBuilder
    private var timerContent: some View {
        if channel == .focus {
            StudyFocusTimerPanel(
                topicOptions: focusTopicOptions,
                lockedTopic: nil,
                selectedTopic: $selectedFocusTopic,
                activeSession: $activeFocusSession,
                stopAction: stopFocusSession
            )
        } else {
            ExerciseTimerPanel(
                topicOptions: exerciseTopicOptions,
                lockedTopic: nil,
                selectedTopic: $selectedExerciseTopic,
                activeSession: $activeExerciseSession,
                stopAction: stopExerciseSession
            )
        }
    }

    private var recordsContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            HStack {
                AcademicDetailSectionHeader(title: channel == .focus ? "专注记录" : "运动记录")
                Spacer()
                CareerSectionAddButton(title: "添加记录", systemName: "plus") {
                    if channel == .focus {
                        focusEditorDate = nil
                        showingFocusEditor = true
                    } else {
                        exerciseEditorDate = nil
                        showingExerciseEditor = true
                    }
                }
            }

            if channel == .focus {
                focusRecordList
            } else {
                exerciseRecordList
            }
        }
    }

    @ViewBuilder
    private var focusRecordList: some View {
        if visibleFocusRecords.isEmpty {
            emptyCard(channel: .focus)
        } else {
            AcademicDetailCard {
                VStack(spacing: 0) {
                    ForEach(Array(visibleFocusRecords.prefix(30).enumerated()), id: \.element.id) { index, record in
                        if index > 0 { AcademicDetailDivider() }
                        StudyTimeRecordRow(
                            record: record,
                            editAction: { editingFocusRecord = record },
                            deleteAction: { deleteFocusRecord(record) }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var exerciseRecordList: some View {
        if visibleExerciseRecords.isEmpty {
            emptyCard(channel: .exercise)
        } else {
            AcademicDetailCard {
                VStack(spacing: 0) {
                    ForEach(Array(visibleExerciseRecords.prefix(30).enumerated()), id: \.element.id) { index, record in
                        if index > 0 { AcademicDetailDivider() }
                        ExerciseRecordRow(
                            record: record,
                            editAction: { editingExerciseRecord = record },
                            deleteAction: { deleteExerciseRecord(record) }
                        )
                    }
                }
            }
        }
    }

    private func emptyCard(channel: PersonalActivityChannel) -> some View {
        AcademicDetailCard {
            ContentUnavailableView(
                channel.emptyTitle,
                systemImage: channel.icon,
                description: Text(channel == .focus ? "开始一次专注，或补记过去的学习时间。" : "开始一次运动，或补记过去的运动时间。")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.compact)
        }
    }

    private var rangeBinding: Binding<ActivityRange> {
        Binding(
            get: { currentRange },
            set: { newValue in
                if channel == .focus { focusRange = newValue } else { exerciseRange = newValue }
            }
        )
    }

    private var scopeBinding: Binding<String> {
        Binding(
            get: { channel == .focus ? focusScopeID : exerciseScopeID },
            set: { newValue in
                if channel == .focus { focusScopeID = newValue } else { exerciseScopeID = newValue }
            }
        )
    }

    private var currentScopeTitle: String {
        let options = channel == .focus ? focusScopeOptions : exerciseScopeOptions
        let id = channel == .focus ? focusScopeID : exerciseScopeID
        return options.first(where: { $0.id == id })?.title ?? (channel == .focus ? "全部学习空间" : "全部运动空间")
    }

    @ViewBuilder
    private func dayDetail(_ day: ActivityDay) -> some View {
        ActivityDayDetailView(
            day: day,
            channel: channel,
            focusRecords: focusRecords(on: day.date),
            exerciseRecords: exerciseRecords(on: day.date),
            startAction: startFromDayDetail,
            addAction: addFromDayDetail,
            editFocusAction: { record in
                selectedDay = nil
                DispatchQueue.main.async { editingFocusRecord = record }
            },
            deleteFocusAction: deleteFocusRecord,
            editExerciseAction: { record in
                selectedDay = nil
                DispatchQueue.main.async { editingExerciseRecord = record }
            },
            deleteExerciseAction: deleteExerciseRecord
        )
    }

    private func focusRecords(on date: Date) -> [StudyTimeRecord] {
        visibleFocusRecords.filter { overlapsDay(start: $0.startedAt, end: $0.endedAt, date: date) }
    }

    private func exerciseRecords(on date: Date) -> [ExerciseRecord] {
        visibleExerciseRecords.filter { overlapsDay(start: $0.startedAt, end: $0.endedAt, date: date) }
    }

    private func overlapsDay(start: Date, end: Date, date: Date) -> Bool {
        let dayStart = Calendar.current.startOfDay(for: date)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return start < dayEnd && end > dayStart
    }

    private func startFromDayDetail() {
        selectedDay = nil
        if channel == .focus {
            activeFocusSession = StudyFocusSession(startedAt: Date(), topic: selectedFocusTopic)
        } else {
            activeExerciseSession = ExerciseSession(startedAt: Date(), topic: selectedExerciseTopic)
        }
    }

    private func addFromDayDetail() {
        let date = selectedDay?.date
        selectedDay = nil
        DispatchQueue.main.async {
            if channel == .focus {
                focusEditorDate = date
                showingFocusEditor = true
            } else {
                exerciseEditorDate = date
                showingExerciseEditor = true
            }
        }
    }

    private func insertFocusRecord(_ draft: StudyTimeRecordDraft) {
        let now = Date()
        modelContext.insert(StudyTimeRecord(
            projectID: draft.projectID,
            categoryRawValue: draft.categoryRawValue,
            startedAt: draft.startedAt,
            endedAt: draft.endedAt,
            content: draft.content,
            location: draft.location,
            note: draft.note,
            createdAt: now,
            updatedAt: now
        ))
        save("专注记录已添加。")
    }

    private func updateFocusRecord(_ record: StudyTimeRecord, with draft: StudyTimeRecordDraft) {
        record.projectID = draft.projectID
        record.categoryRawValue = draft.categoryRawValue
        record.startedAt = draft.startedAt
        record.endedAt = draft.endedAt
        record.content = draft.content
        record.location = draft.location
        record.note = draft.note
        record.updatedAt = Date()
        save("专注记录已保存。")
    }

    private func deleteFocusRecord(_ record: StudyTimeRecord) {
        modelContext.delete(record)
        save("专注记录已删除。")
    }

    private func stopFocusSession(_ session: StudyFocusSession, endedAt: Date) {
        let endedAt = max(endedAt, session.startedAt.addingTimeInterval(60))
        let now = Date()
        modelContext.insert(StudyTimeRecord(
            projectID: session.topic.projectID,
            categoryRawValue: session.topic.categoryRawValue,
            startedAt: session.startedAt,
            endedAt: endedAt,
            content: session.topic == .none ? "专注学习" : session.topic.title,
            location: "图书馆",
            createdAt: now,
            updatedAt: now
        ))
        save("专注记录已保存。")
    }

    private func insertExerciseRecord(_ draft: ExerciseRecordDraft) {
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

    private func updateExerciseRecord(_ record: ExerciseRecord, with draft: ExerciseRecordDraft) {
        record.spaceID = draft.spaceID
        record.categoryRawValue = draft.categoryRawValue
        record.startedAt = draft.startedAt
        record.endedAt = draft.endedAt
        record.content = draft.content
        record.location = draft.location
        record.note = draft.note
        record.updatedAt = Date()
        save("运动记录已保存。")
    }

    private func deleteExerciseRecord(_ record: ExerciseRecord) {
        modelContext.delete(record)
        save("运动记录已删除。")
    }

    private func stopExerciseSession(_ session: ExerciseSession, endedAt: Date) {
        let endedAt = max(endedAt, session.startedAt.addingTimeInterval(60))
        let now = Date()
        modelContext.insert(ExerciseRecord(
            spaceID: session.topic.spaceID,
            categoryRawValue: session.topic.categoryRawValue,
            startedAt: session.startedAt,
            endedAt: endedAt,
            content: session.topic.title,
            location: "校园",
            createdAt: now,
            updatedAt: now
        ))
        save("运动记录已保存。")
    }

    private func save(_ message: String) {
        do {
            try modelContext.save()
            operationAlert = .success(L10n.text(message, language: leafyLanguage))
        } catch {
            operationAlert = .failure(error.localizedDescription)
        }
    }
}

private struct ActivityMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .microCaption()
                .foregroundStyle(AppTheme.secondaryText)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ActivityDayDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let day: ActivityDay
    let channel: PersonalActivityChannel
    let focusRecords: [StudyTimeRecord]
    let exerciseRecords: [ExerciseRecord]
    let startAction: () -> Void
    let addAction: () -> Void
    let editFocusAction: (StudyTimeRecord) -> Void
    let deleteFocusAction: (StudyTimeRecord) -> Void
    let editExerciseAction: (ExerciseRecord) -> Void
    let deleteExerciseAction: (ExerciseRecord) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    AcademicDetailCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(DateFormatters.fullDateWithWeekday.string(from: day.date))
                                .leafyHeadline()
                                .foregroundStyle(AppTheme.primaryText)
                            Text("\(channel.rawValue) \(durationText(day.duration)) · \(day.recordCount) 条记录")
                                .leafySubheadline()
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }

                    if channel == .focus {
                        focusList
                    } else {
                        exerciseList
                    }
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle("当日活动")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: AppSpacing.compact) {
                    Button {
                        dismiss()
                        addAction()
                    } label: {
                        Label("补记", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        dismiss()
                        startAction()
                    } label: {
                        Label(channel == .focus ? "开始专注" : "开始运动", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(channel == .focus ? AppTheme.accent : AppTheme.exercise)
                }
                .padding(.horizontal, AppSpacing.page)
                .padding(.vertical, AppSpacing.compact)
                .background(.bar)
            }
        }
    }

    @ViewBuilder
    private var focusList: some View {
        if focusRecords.isEmpty {
            ContentUnavailableView("当天暂无专注记录", systemImage: "timer")
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.section)
        } else {
            AcademicDetailCard {
                VStack(spacing: 0) {
                    ForEach(Array(focusRecords.enumerated()), id: \.element.id) { index, record in
                        if index > 0 { AcademicDetailDivider() }
                        StudyTimeRecordRow(
                            record: record,
                            editAction: { editFocusAction(record) },
                            deleteAction: { deleteFocusAction(record) }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var exerciseList: some View {
        if exerciseRecords.isEmpty {
            ContentUnavailableView("当天暂无运动记录", systemImage: "figure.run")
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.section)
        } else {
            AcademicDetailCard {
                VStack(spacing: 0) {
                    ForEach(Array(exerciseRecords.enumerated()), id: \.element.id) { index, record in
                        if index > 0 { AcademicDetailDivider() }
                        ExerciseRecordRow(
                            record: record,
                            editAction: { editExerciseAction(record) },
                            deleteAction: { deleteExerciseAction(record) }
                        )
                    }
                }
            }
        }
    }
}

func durationText(_ duration: TimeInterval) -> String {
    let minutes = max(Int(duration / 60), 0)
    let hours = minutes / 60
    let remainder = minutes % 60
    if hours == 0 { return "\(remainder) 分钟" }
    if remainder == 0 { return "\(hours) 小时" }
    return "\(hours) 小时 \(remainder) 分钟"
}
