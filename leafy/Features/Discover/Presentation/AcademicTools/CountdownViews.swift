import SwiftData
import SwiftUI

enum CustomScheduleDefaultContext {
    static func make(for date: Date = Date()) -> TimetableCellReminderContext {
        let timetable = AcademicYearTimetable(
            configurations: SemesterConfig.timelineConfigurations,
            semanticEvents: SemesterConfig.timelineConfigurations.flatMap(\.calendarEvents)
        )
        let calendar = Calendar.current
        let current = calendar.startOfDay(for: date)
        let weekAndDay: (week: Int, day: Int)
        if let week = timetable.pageIndex(containing: current) {
            let weekday = calendar.component(.weekday, from: current)
            weekAndDay = (week, ((weekday + 5) % 7) + 1)
        } else {
            let today = calendar.startOfDay(for: Date())
            let weekday = calendar.component(.weekday, from: today)
            weekAndDay = (
                timetable.pageIndex(containing: today) ?? 1,
                weekday == 1 ? 7 : weekday - 1
            )
        }
        let period = min(
            max(TimetablePeriodSchedule.defaultStudyPeriod(for: date), 1),
            TimetablePeriodSchedule.slots.count
        )
        let resolvedDate = defaultDate(
            week: weekAndDay.week,
            day: weekAndDay.day,
            period: period,
            timetable: timetable,
            calendar: calendar
        )
        return TimetableCellReminderContext(
            week: weekAndDay.week,
            day: weekAndDay.day,
            period: period,
            date: resolvedDate,
            occupiedPeriods: [],
            totalPeriods: TimetablePeriodSchedule.slots.count,
            reminder: nil,
            allowsDateSelection: true
        )
    }

    private static func defaultDate(
        week: Int,
        day: Int,
        period: Int,
        timetable: AcademicYearTimetable,
        calendar: Calendar
    ) -> Date {
        guard let timelineWeek = timetable.week(atPageIndex: week),
              let slot = TimetablePeriodSchedule.slot(for: period),
              let date = calendar.date(
                  byAdding: .day,
                  value: day - 1,
                  to: timelineWeek.weekStartDate
              ) else { return Date() }
        return calendar.date(
            bySettingHour: slot.startHour,
            minute: slot.startMinute,
            second: 0,
            of: date
        ) ?? date
    }
}

struct CustomScheduleListView: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.modelContext) private var modelContext
    @Query private var timetableEvents: [TimetableCellReminder]

    @State private var importantDateEvents: [CustomScheduleEvent] = []
    @State private var editorPresentation: CustomScheduleEditorPresentation?
    @State private var operationAlert: LeafyOperationAlert?
    @State private var pendingDeleteItem: CustomScheduleListItem?

    private let presentation: SchedulePrimaryContentPresentation

    init(presentation: SchedulePrimaryContentPresentation = .standalone) {
        self.presentation = presentation
    }

    private var academicYearTimetable: AcademicYearTimetable {
        let configurations = SemesterConfig.timelineConfigurations
        return AcademicYearTimetable(
            configurations: configurations,
            semanticEvents: configurations.flatMap(\.calendarEvents)
        )
    }

    private var sortedItems: [CustomScheduleListItem] {
        let timetable = academicYearTimetable
        let importantDates = importantDateEvents.map { event in
            CustomScheduleListItem.importantDate(
                event,
                projectsIntoTimetable: timetable.contains(event.startsAt)
            )
        }
        return (timetableEvents.map(CustomScheduleListItem.timetable) + importantDates)
            .sorted { lhs, rhs in
                if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
                return lhs.title.localizedCompare(rhs.title) == .orderedAscending
            }
    }

    var body: some View {
        configuredContent
        .leafySheet(item: $editorPresentation, onDismiss: reloadImportantDates) { presentation in
            CustomScheduleEditorSheet(presentation: presentation)
                .presentationDetents([.medium, .large])
        }
        .onAppear(perform: reloadImportantDates)
        .onReceive(NotificationCenter.default.publisher(for: .customScheduleEventsDidChange)) { _ in
            reloadImportantDates()
        }
        .leafyOperationAlert($operationAlert)
        .confirmationDialog("删除这条日程？", isPresented: Binding(
            get: { pendingDeleteItem != nil },
            set: { if !$0 { pendingDeleteItem = nil } }
        ), titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let item = pendingDeleteItem {
                    delete(item)
                }
                pendingDeleteItem = nil
            }
            Button("取消", role: .cancel) {
                pendingDeleteItem = nil
            }
        } message: {
            Text("删除后无法恢复。")
        }
    }

    @ViewBuilder
    private var configuredContent: some View {
        if presentation == .daytraceRoot {
            scheduleList
        } else {
            scheduleList
                .navigationTitle("自定日程")
                .leafyInlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .leafyTrailing) {
                        Button {
                            editorPresentation = .importantDate(
                                nil,
                                defaultContext: defaultTimetableContext(),
                                allowsModeSelection: true
                            )
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("添加自定日程")
                    }
                }
        }
    }

    private var scheduleList: some View {
        List {
            if sortedItems.isEmpty {
                AcademicDetailCard {
                    ContentUnavailableView("暂无自定日程", systemImage: "calendar.badge.plus")
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(listRowInsets)
            } else {
                ForEach(sortedItems) { item in
                    Button {
                        edit(item)
                    } label: {
                        AcademicDetailCard {
                            CustomScheduleListRow(item: item)
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            pendingDeleteItem = item
                        } label: {
                            Label("删除", systemImage: "trash")
                                .foregroundStyle(.red)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(listRowInsets)
                }
            }

            Text("日程仅保存在当前设备。每条日程都会显示倒计时；日期在当前学年内时，还会同时显示在课表。")
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(
                    top: AppSpacing.compact,
                    leading: AppSpacing.page,
                    bottom: AppSpacing.compact,
                    trailing: AppSpacing.page
                ))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(LeafyPageBackground())
        .frame(maxWidth: 840, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var listRowInsets: EdgeInsets {
        EdgeInsets(
            top: AppSpacing.micro,
            leading: AppSpacing.page,
            bottom: AppSpacing.micro,
            trailing: AppSpacing.page
        )
    }

    private func reloadImportantDates() {
        importantDateEvents = CustomScheduleStore.load()
    }

    private func edit(_ item: CustomScheduleListItem) {
        switch item {
        case .timetable(let reminder):
            editorPresentation = .timetable(context(for: reminder), allowsModeSelection: false)
        case .importantDate(let event, _):
            editorPresentation = .importantDate(event, defaultContext: defaultTimetableContext(for: event.startsAt), allowsModeSelection: false)
        }
    }

    @MainActor
    private func delete(_ item: CustomScheduleListItem) {
        switch item {
        case .timetable(let reminder):
            TimetableNotificationManager.cancelReminder(for: reminder)
            modelContext.delete(reminder)
            do {
                try modelContext.save()
                operationAlert = .success(L10n.text("日程已删除。", language: leafyLanguage))
            } catch {
                operationAlert = .failure(error.localizedDescription)
            }
        case .importantDate(let event, _):
            var events = CustomScheduleStore.load()
            events.removeAll { $0.id == event.id }
            TimetableNotificationManager.cancelReminder(for: event)
            CustomScheduleStore.save(events)
            importantDateEvents = events
            operationAlert = .success(L10n.text("日程已删除。", language: leafyLanguage))
        }
    }

    private func context(for reminder: TimetableCellReminder) -> TimetableCellReminderContext {
        TimetableCellReminderContext(
            week: reminder.week,
            day: reminder.dayOfWeek,
            period: reminder.displayStartPeriod,
            date: reminder.resolvedStartDate ?? defaultDate(week: reminder.week, day: reminder.dayOfWeek, period: reminder.displayStartPeriod),
            occupiedPeriods: [],
            totalPeriods: TimetablePeriodSchedule.slots.count,
            reminder: reminder,
            allowsDateSelection: true
        )
    }

    private func defaultTimetableContext(for date: Date = Date()) -> TimetableCellReminderContext {
        CustomScheduleDefaultContext.make(for: date)
    }

    private func defaultDate(week: Int, day: Int, period: Int) -> Date {
        let calendar = Calendar.current
        guard let timelineWeek = academicYearTimetable.week(atPageIndex: week),
              let slot = TimetablePeriodSchedule.slot(for: period),
              let date = calendar.date(
                  byAdding: .day,
                  value: day - 1,
                  to: timelineWeek.weekStartDate
              ) else { return Date() }
        return calendar.date(
            bySettingHour: slot.startHour,
            minute: slot.startMinute,
            second: 0,
            of: date
        ) ?? date
    }

}

struct CustomCountdownListView: View {
    var body: some View {
        CustomScheduleListView()
    }
}

struct CustomScheduleRootView: View {
    var body: some View {
        NavigationStack {
            CustomScheduleListView()
        }
    }
}

private enum CustomScheduleListItem: Identifiable {
    case timetable(TimetableCellReminder)
    case importantDate(CustomScheduleEvent, projectsIntoTimetable: Bool)

    var id: String {
        switch self {
        case .timetable(let reminder):
            return "timetable-\(reminder.id.uuidString)"
        case .importantDate(let event, _):
            return "important-\(event.id)"
        }
    }

    var title: String {
        switch self {
        case .timetable(let reminder):
            return reminder.title
        case .importantDate(let event, _):
            return event.title
        }
    }

    var badge: String {
        switch self {
        case .timetable:
            return "课表 · 倒计时"
        case .importantDate(_, let projectsIntoTimetable):
            return projectsIntoTimetable ? "课表 · 倒计时" : "倒计时"
        }
    }

    var startDate: Date {
        switch self {
        case .timetable(let reminder):
            return reminder.resolvedStartDate ?? .distantFuture
        case .importantDate(let event, _):
            return event.startsAt
        }
    }

    var endDate: Date? {
        switch self {
        case .timetable(let reminder):
            return reminder.resolvedEndDate
        case .importantDate(let event, _):
            return event.endsAt
        }
    }

    var location: String {
        switch self {
        case .timetable(let reminder):
            return reminder.locationText
        case .importantDate(let event, _):
            return event.locationText
        }
    }

    var note: String {
        switch self {
        case .timetable(let reminder):
            return reminder.noteText
        case .importantDate(let event, _):
            return event.noteText
        }
    }

    var minutesBefore: Int {
        switch self {
        case .timetable(let reminder):
            return reminder.minutesBefore
        case .importantDate(let event, _):
            return event.minutesBefore
        }
    }

    var systemImage: String {
        switch self {
        case .timetable:
            return "calendar.badge.clock"
        case .importantDate(_, let projectsIntoTimetable):
            return projectsIntoTimetable ? "calendar.badge.clock" : "timer"
        }
    }

    var tint: Color {
        switch self {
        case .timetable:
            return AppTheme.accent
        case .importantDate(_, let projectsIntoTimetable):
            return projectsIntoTimetable ? AppTheme.accent : AppTheme.warning
        }
    }
}

private struct CustomScheduleListRow: View {
    let item: CustomScheduleListItem

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.compact) {
            LeafyIconBadge(systemName: item.systemImage, tint: item.tint)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: AppSpacing.micro)

                    Text(item.badge)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.softFill, in: Capsule())
                }

                HStack(alignment: .center, spacing: AppSpacing.micro) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dateText)
                        Text(timeText)
                    }
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)

                    Spacer(minLength: AppSpacing.micro)

                    Text(CountdownEventRow.countdownDescription(for: item.startDate))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)
                }

                if !detailText.isEmpty {
                    Text(detailText)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private var dateText: String {
        DateFormatters.header.string(from: item.startDate)
    }

    private var timeText: String {
        if let endDate = item.endDate, endDate > item.startDate {
            return "\(DateFormatters.timeOnly.string(from: item.startDate))–\(DateFormatters.timeOnly.string(from: endDate))"
        }
        return DateFormatters.timeOnly.string(from: item.startDate)
    }

    private var detailText: String {
        var parts: [String] = []
        if !item.location.isEmpty {
            parts.append(item.location)
        }
        if item.minutesBefore > 0 {
            parts.append("提前 \(item.minutesBefore) 分钟提醒")
        }
        if !item.note.isEmpty {
            parts.append(item.note)
        }
        return parts.joined(separator: " · ")
    }
}

struct CountdownEventRow: View {
    let title: String
    let badge: String
    let targetDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(badge)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.softFill, in: Capsule())
            }
            Text(DateFormatters.headerWithTime.string(from: targetDate))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(Self.countdownDescription(for: targetDate))
                .font(.title3.weight(.bold))
        }
        .padding(.vertical, 6)
    }

    static func countdownDescription(for targetDate: Date) -> String {
        let seconds = Int(targetDate.timeIntervalSinceNow)
        if seconds <= 0 { return "已开始" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        if days > 0 {
            return "还有 \(days) 天 \(hours) 小时"
        }
        let minutes = (seconds % 3_600) / 60
        return "还有 \(hours) 小时 \(minutes) 分钟"
    }
}
