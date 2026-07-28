import SwiftData
import SwiftUI

struct ScheduleReportsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.leafyDependencies) private var dependencies

    @State private var settings = ScheduleReportSettingsStore.load()
    @State private var lastAppliedSettings = ScheduleReportSettingsStore.load()
    @State private var operationAlert: LeafyOperationAlert?
    @State private var applyTask: Task<Void, Never>?
    @State private var isEditorPresented = false

    private var input: ScheduleReportInput {
        ScheduleReportDataSource.input(modelContext: modelContext)
    }

    var body: some View {
        List {
            Section {
                AcademicDetailCard {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Label("日程推送", systemImage: "bell.badge")
                            .leafyHeadline()
                        Text("报告和提醒仅在本机规划，不上传课表、考试、校历或自定日程。")
                            .leafyBody()
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .scheduleReportListRow()
            }

            Section {
                ForEach(ScheduleReportMode.builtInCases) { mode in
                    ScheduleReportModeCard(
                        mode: mode,
                        setting: binding(for: mode),
                        time: dateBinding(for: mode)
                    )
                    .scheduleReportListRow()
                }
            } header: {
                AcademicDetailSectionHeader(title: "报告")
            }

            Section {
                if settings.reminders.isEmpty {
                    AcademicDetailCard {
                        Text("暂无自定义提醒")
                            .leafyBody()
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .scheduleReportListRow()
                } else {
                    ForEach(settings.reminders) { reminder in
                        ScheduleReminderCard(
                            reminder: reminder,
                            input: input,
                            onToggle: { toggleReminder(reminder.id, isEnabled: $0) }
                        )
                        .scheduleReportListRow()
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteReminder(reminder.id)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                    }
                }
            } header: {
                AcademicDetailSectionHeader(title: "自定义提醒")
            }

            Section {
                AcademicDetailFooterText(
                    text: "获取到天气时，今日早报会附上当天预报与出门建议，明日晚报会附上明天预报与建议。系统后台刷新为尽力而为。"
                )
                .scheduleReportListRow(verticalPadding: 4)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(LeafyPageBackground())
        .environment(\.defaultMinListRowHeight, 1)
        .navigationTitle("推送")
        .leafyInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .leafyTrailing) {
                Button {
                    isEditorPresented = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加提醒")
            }
        }
        .onAppear {
            let loaded = ScheduleReportSettingsStore.load()
            settings = ScheduleReportPlanner.resolvingReminderSources(in: loaded, input: input)
            settings.deriveEnabledState()
            lastAppliedSettings = settings
            ScheduleReportSettingsStore.save(settings)
        }
        .onDisappear { applyTask?.cancel() }
        .sheet(isPresented: $isEditorPresented) {
            ScheduleReminderEditor(input: input) { savedReminder in
                var updated = settings
                updated.reminders.append(savedReminder)
                updated.deriveEnabledState()
                apply(updated, debounce: false)
            }
        }
        .leafyOperationAlert($operationAlert)
    }

    private func toggleReminder(_ id: UUID, isEnabled: Bool) {
        guard let index = settings.reminders.firstIndex(where: { $0.id == id }),
              settings.reminders[index].availability == .available else { return }
        var updated = settings
        updated.reminders[index].isEnabled = isEnabled
        updated.deriveEnabledState()
        apply(updated, debounce: false)
    }

    private func deleteReminder(_ id: UUID) {
        var updated = settings
        updated.reminders.removeAll { $0.id == id }
        updated.deriveEnabledState()
        apply(updated, debounce: false)
    }

    private func binding(for mode: ScheduleReportMode) -> Binding<ScheduleReportModeSetting> {
        Binding {
            settings.setting(for: mode)
        } set: { newValue in
            var updated = settings
            updated.set(newValue, for: mode)
            updated.deriveEnabledState()
            apply(updated, debounce: false)
        }
    }

    private func dateBinding(for mode: ScheduleReportMode) -> Binding<Date> {
        Binding {
            let setting = settings.setting(for: mode)
            return Calendar.current.date(
                from: DateComponents(hour: setting.hour, minute: setting.minute)
            ) ?? Date()
        } set: { newValue in
            var updated = settings
            var setting = updated.setting(for: mode)
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            setting.hour = components.hour ?? mode.defaultHour
            setting.minute = components.minute ?? mode.defaultMinute
            updated.set(setting, for: mode)
            updated.deriveEnabledState()
            apply(updated, debounce: true)
        }
    }

    @MainActor
    private func apply(_ updatedSettings: ScheduleReportSettings, debounce: Bool) {
        settings = updatedSettings
        applyTask?.cancel()
        applyTask = Task { @MainActor in
            if debounce {
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            do {
                let weather = await availableWeather()
                let applied = try await ScheduleReportNotificationManager.updateNotifications(
                    settings: updatedSettings,
                    input: input,
                    weather: weather
                )
                guard !Task.isCancelled else { return }
                settings = applied
                lastAppliedSettings = applied
                ScheduleReportSettingsStore.save(applied)
                ScheduleReportBackgroundRefreshCoordinator.shared.schedule()
            } catch is CancellationError {
                return
            } catch {
                settings = lastAppliedSettings
                ScheduleReportSettingsStore.save(lastAppliedSettings)
                operationAlert = .failure(error.localizedDescription)
            }
        }
    }

    @MainActor
    private func availableWeather() async -> TimetableWeatherSnapshot? {
        if let cached = dependencies.timetableWeatherService.cachedWeather(maxAge: 30 * 60) {
            return cached
        }
        guard dependencies.timetableWeatherService.authorizationState() == .authorized else {
            return nil
        }
        return try? await dependencies.timetableWeatherService.fetchCurrentWeather(
            requestsPermissionIfNeeded: false
        )
    }
}

private extension View {
    func scheduleReportListRow(verticalPadding: CGFloat = 6) -> some View {
        listRowInsets(
            EdgeInsets(
                top: verticalPadding,
                leading: AppSpacing.page,
                bottom: verticalPadding,
                trailing: AppSpacing.page
            )
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

private struct ScheduleReminderCard: View {
    let reminder: ScheduleReminder
    let input: ScheduleReportInput
    let onToggle: (Bool) -> Void

    var body: some View {
        AcademicDetailCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Toggle(
                    isOn: Binding(get: { reminder.isEnabled }, set: onToggle)
                ) {
                    HStack(spacing: 8) {
                        Image(systemName: systemImage)
                            .frame(width: 28, alignment: .leading)
                        Text(ScheduleReminderPresentation.title(for: reminder, input: input))
                    }
                    .font(.headline)
                }
                .disabled(reminder.availability == .sourceUnavailable)

                if reminder.availability == .sourceUnavailable {
                    Text("原日程已不可用")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.warning)
                } else {
                    Text(ScheduleReminderPresentation.detail(for: reminder, input: input))
                        .leafySubheadline()
                        .foregroundStyle(AppTheme.secondaryText)
                    Text(
                        reminder.leadMinutes
                            .map { ScheduleReminderPresentation.leadText($0) }
                            .joined(separator: " · ")
                    )
                        .font(.caption)
                        .foregroundStyle(AppTheme.tertiaryText)
                }

            }
        }
    }

    private var systemImage: String {
        switch reminder.source {
        case .freeform: return "square.and.pencil"
        case .customSchedule: return "calendar.badge.clock"
        case .exam: return "pencil.and.list.clipboard"
        case .calendar: return "calendar"
        case .course: return "book.closed"
        }
    }
}

private enum ScheduleReminderEditorSourceKind: String, CaseIterable, Identifiable {
    case freeform
    case customSchedule
    case exam
    case calendar
    case course

    var id: String { rawValue }
    var title: String {
        switch self {
        case .freeform: return "自由输入"
        case .customSchedule: return "自定日程"
        case .exam: return "教务考试"
        case .calendar: return "校历节点"
        case .course: return "课程"
        }
    }
}

private struct ScheduleReminderEditor: View {
    @Environment(\.dismiss) private var dismiss

    let input: ScheduleReportInput
    let onSave: (ScheduleReminder) -> Void

    @State private var sourceKind: ScheduleReminderEditorSourceKind
    @State private var title: String
    @State private var bodyText: String
    @State private var fireDate: Date
    @State private var selectedCustomScheduleID: String
    @State private var selectedExamID: Int?
    @State private var selectedCalendarID: String
    @State private var selectedCourseID: UUID?
    @State private var courseScope: ScheduleReminderCourseScope
    @State private var selectedOccurrenceDate: Date?
    @State private var selectedLeadMinutes: Set<Int>
    @State private var customLeadMinutes: Int

    init(
        input: ScheduleReportInput,
        onSave: @escaping (ScheduleReminder) -> Void
    ) {
        self.input = input
        self.onSave = onSave

        _sourceKind = State(initialValue: .freeform)
        _title = State(initialValue: "")
        _bodyText = State(initialValue: "")
        _fireDate = State(initialValue: Date().addingTimeInterval(60 * 60))
        _selectedCustomScheduleID = State(initialValue: input.countdowns.first?.id ?? "")
        _selectedExamID = State(initialValue: input.exams.first?.id)
        _selectedCalendarID = State(initialValue: AcademicCalendarEvents.displayEvents().first?.id ?? "")
        _selectedCourseID = State(initialValue: input.courses.first?.id)
        _courseScope = State(initialValue: .singleOccurrence)
        _selectedOccurrenceDate = State(initialValue: nil)
        _selectedLeadMinutes = State(initialValue: [0])
        _customLeadMinutes = State(initialValue: 120)
    }

    private var canSave: Bool {
        guard !selectedLeadMinutes.isEmpty else { return false }
        switch sourceKind {
        case .freeform:
            return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && fireDate > Date()
        case .customSchedule:
            return input.countdowns.contains { $0.id == selectedCustomScheduleID }
        case .exam:
            return selectedExamID.map { id in input.exams.contains { $0.id == id } } == true
        case .calendar:
            return AcademicCalendarEvents.displayEvents().contains { $0.id == selectedCalendarID }
        case .course:
            guard let selectedCourseID,
                  input.courses.contains(where: { $0.id == selectedCourseID }) else { return false }
            return courseScope == .remainingSemester || resolvedOccurrenceDate != nil
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("提醒来源", selection: $sourceKind) {
                        ForEach(ScheduleReminderEditorSourceKind.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    sourceFields
                } header: {
                    Text("来源")
                }

                Section {
                    ForEach(ScheduleReminder.presetLeadMinutes, id: \.self) { minutes in
                        Toggle(
                            ScheduleReminderPresentation.leadText(minutes),
                            isOn: Binding(
                                get: { selectedLeadMinutes.contains(minutes) },
                                set: { selected in
                                    if selected {
                                        selectedLeadMinutes.insert(minutes)
                                    } else {
                                        selectedLeadMinutes.remove(minutes)
                                    }
                                }
                            )
                        )
                    }

                    Stepper(
                        "自定义：\(ScheduleReminderPresentation.leadText(customLeadMinutes))",
                        value: $customLeadMinutes,
                        in: ScheduleReminder.customLeadMinuteRange
                    )
                    Button("添加自定义提前量") {
                        selectedLeadMinutes.insert(customLeadMinutes)
                    }

                    ForEach(customSelectedLeadMinutes, id: \.self) { minutes in
                        HStack {
                            Text(ScheduleReminderPresentation.leadText(minutes))
                            Spacer()
                            Button(role: .destructive) {
                                selectedLeadMinutes.remove(minutes)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("删除\(ScheduleReminderPresentation.leadText(minutes))")
                        }
                    }
                } header: {
                    Text("提醒时间")
                } footer: {
                    Text("可同时选择多个提前量；自定义范围为 1 分钟至 7 天。")
                }
            }
            .navigationTitle("添加提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(makeReminder())
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onChange(of: selectedCourseID) { _, _ in
                selectedOccurrenceDate = courseOccurrences.first
            }
            .onChange(of: courseScope) { _, newValue in
                if newValue == .singleOccurrence, selectedOccurrenceDate == nil {
                    selectedOccurrenceDate = courseOccurrences.first
                }
            }
        }
    }

    @ViewBuilder
    private var sourceFields: some View {
        switch sourceKind {
        case .freeform:
            TextField("标题", text: $title)
            TextField("正文（可选）", text: $bodyText, axis: .vertical)
                .lineLimit(2...5)
            DatePicker(
                "发生时间",
                selection: $fireDate,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )

        case .customSchedule:
            if input.countdowns.isEmpty {
                Text("暂无可用的自定日程")
                    .foregroundStyle(AppTheme.secondaryText)
            } else {
                Picker("选择日程", selection: $selectedCustomScheduleID) {
                    ForEach(input.countdowns) { event in
                        Text(event.title).tag(event.id)
                    }
                }
            }

        case .exam:
            if input.exams.isEmpty {
                Text("暂无教务考试")
                    .foregroundStyle(AppTheme.secondaryText)
            } else {
                Picker("选择考试", selection: $selectedExamID) {
                    ForEach(input.exams) { exam in
                        Text("\(exam.name) · \(exam.date)").tag(Optional(exam.id))
                    }
                }
            }

        case .calendar:
            let events = AcademicCalendarEvents.displayEvents()
            if events.isEmpty {
                Text("暂无校历节点")
                    .foregroundStyle(AppTheme.secondaryText)
            } else {
                Picker("选择节点", selection: $selectedCalendarID) {
                    ForEach(events) { event in
                        Text(event.title).tag(event.id)
                    }
                }
            }

        case .course:
            if input.courses.isEmpty {
                Text("暂无课程")
                    .foregroundStyle(AppTheme.secondaryText)
            } else {
                Picker("选择课程", selection: $selectedCourseID) {
                    ForEach(input.courses) { course in
                        Text(course.courseName).tag(Optional(course.id))
                    }
                }
                Picker("范围", selection: $courseScope) {
                    ForEach(ScheduleReminderCourseScope.allCases, id: \.self) {
                        Text($0.title).tag($0)
                    }
                }
                if courseScope == .singleOccurrence {
                    Picker("选择上课日期", selection: Binding(
                        get: { resolvedOccurrenceDate },
                        set: { selectedOccurrenceDate = $0 }
                    )) {
                        ForEach(courseOccurrences, id: \.self) { date in
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .tag(Optional(date))
                        }
                    }
                }
            }
        }
    }

    private var courseOccurrences: [Date] {
        guard let selectedCourseID,
              let course = input.courses.first(where: { $0.id == selectedCourseID }) else {
            return []
        }
        return course.weeks
            .compactMap { TimetablePeriodSchedule.startDate(for: course, week: $0) }
            .filter { $0 > Date() }
            .sorted()
    }

    private var customSelectedLeadMinutes: [Int] {
        selectedLeadMinutes
            .filter { !ScheduleReminder.presetLeadMinutes.contains($0) }
            .sorted()
    }

    private var resolvedOccurrenceDate: Date? {
        if let selectedOccurrenceDate,
           courseOccurrences.contains(where: { abs($0.timeIntervalSince(selectedOccurrenceDate)) < 60 }) {
            return selectedOccurrenceDate
        }
        return courseOccurrences.first
    }

    private func makeReminder() -> ScheduleReminder {
        let source: ScheduleReminderSource
        switch sourceKind {
        case .freeform:
            source = .freeform(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                body: bodyText.trimmingCharacters(in: .whitespacesAndNewlines),
                fireDate: fireDate
            )
        case .customSchedule:
            source = .customSchedule(eventID: selectedCustomScheduleID)
        case .exam:
            source = .exam(examID: selectedExamID ?? -1)
        case .calendar:
            source = .calendar(eventID: selectedCalendarID)
        case .course:
            source = .course(
                courseID: selectedCourseID ?? UUID(),
                scope: courseScope,
                occurrenceDate: courseScope == .singleOccurrence ? resolvedOccurrenceDate : nil
            )
        }
        return ScheduleReminder(
            id: UUID(),
            isEnabled: true,
            source: source,
            leadMinutes: Array(selectedLeadMinutes),
            availability: .available
        )
    }
}

private enum ScheduleReminderPresentation {
    static func title(for reminder: ScheduleReminder, input: ScheduleReportInput) -> String {
        switch reminder.source {
        case .freeform(let title, _, _):
            return title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "自由输入提醒" : title
        case .customSchedule(let eventID):
            return input.countdowns.first(where: { $0.id == eventID })?.title ?? "自定日程"
        case .exam(let examID):
            return input.exams.first(where: { $0.id == examID })?.name ?? "教务考试"
        case .calendar(let eventID):
            return AcademicCalendarEvents.displayEvents().first(where: { $0.id == eventID })?.title ?? "校历节点"
        case .course(let courseID, _, _):
            return input.courses.first(where: { $0.id == courseID })?.courseName ?? "课程"
        }
    }

    static func detail(for reminder: ScheduleReminder, input: ScheduleReportInput) -> String {
        switch reminder.source {
        case .freeform(_, let body, let fireDate):
            let time = fireDate?.formatted(date: .abbreviated, time: .shortened) ?? "未设置时间"
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? time : "\(time) · \(trimmed)"
        case .customSchedule(let eventID):
            guard let event = input.countdowns.first(where: { $0.id == eventID }) else { return "原日程已不可用" }
            return event.startsAt.formatted(date: .abbreviated, time: .shortened)
        case .exam(let examID):
            guard let exam = input.exams.first(where: { $0.id == examID }) else { return "原日程已不可用" }
            return "\(exam.date) \(exam.start) · \(exam.location)"
        case .calendar(let eventID):
            guard let event = AcademicCalendarEvents.displayEvents().first(where: { $0.id == eventID }) else { return "原日程已不可用" }
            return event.startDate?.formatted(date: .abbreviated, time: .omitted) ?? event.startDateString
        case .course(_, let scope, let occurrenceDate):
            if scope == .remainingSemester {
                return scope.title
            }
            return occurrenceDate?.formatted(date: .abbreviated, time: .shortened) ?? scope.title
        }
    }

    static func leadText(_ minutes: Int) -> String {
        switch minutes {
        case 0: return "准时"
        case 1..<60: return "提前 \(minutes) 分钟"
        case 60 where minutes % 60 == 0: return "提前 1 小时"
        case 60..<1_440 where minutes % 60 == 0: return "提前 \(minutes / 60) 小时"
        case 1_440: return "提前 1 天"
        case 1_440... where minutes % 1_440 == 0: return "提前 \(minutes / 1_440) 天"
        default: return "提前 \(minutes) 分钟"
        }
    }
}

private struct ScheduleReportModeCard: View {
    let mode: ScheduleReportMode
    @Binding var setting: ScheduleReportModeSetting
    @Binding var time: Date

    var body: some View {
        AcademicDetailCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Toggle(isOn: $setting.isEnabled) {
                    HStack(spacing: 8) {
                        Image(systemName: mode.systemImage)
                            .frame(width: 28, alignment: .leading)
                        Text(mode.title)
                    }
                    .font(.headline)
                }
                Text(mode.subtitle)
                    .leafySubheadline()
                    .foregroundStyle(AppTheme.secondaryText)

                if setting.isEnabled {
                    DatePicker("推送时间", selection: $time, displayedComponents: .hourAndMinute)
                }
            }
        }
    }
}
