import SwiftData
import SwiftUI

struct ClockScheduleView: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyControlScale) private var controlScale
    @Environment(\.modelContext) private var modelContext
    @Query private var courses: [Course]
    @Query private var reminders: [TimetableCellReminder]

    @State private var customEvents: [CustomScheduleEvent]
    @State private var selectedDate: Date
    @State private var selectedDayPart: ClockScheduleDayPart
    @State private var selectedEventID: String?
    @State private var focusedStartDate: Date?
    @State private var isDatePickerPresented = false
    @State private var editorPresentation: CustomScheduleEditorPresentation?

    init(initialDate: Date = Date()) {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: initialDate)
        _customEvents = State(initialValue: CustomScheduleStore.load())
        _selectedDate = State(initialValue: day)
        _selectedDayPart = State(initialValue: Self.defaultDayPart(for: initialDate))
    }

    private var projection: ClockScheduleDayProjection {
        ClockScheduleProjection.make(
            date: selectedDate,
            courses: courses,
            reminders: reminders,
            customEvents: customEvents
        )
    }

    private var visibleEvents: [ClockScheduleEvent] {
        projection.events(for: selectedDayPart)
    }

    private var selectedEvent: ClockScheduleEvent? {
        guard let selectedEventID else { return nil }
        return projection.events.first { $0.id == selectedEventID }
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    dateHeader
                    dateRail
                    dayPartPicker
                    dialSection

                    if let selectedEvent {
                        detailCard(for: selectedEvent)
                    } else if visibleEvents.isEmpty {
                        emptyState
                    }
                }
                .padding(.horizontal, AppSpacing.page)
                .padding(.vertical, AppSpacing.compact)
            }
            .background(LeafyPageBackground())
            .navigationTitle("日程")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        presentNewSchedule()
                    } label: {
                        Image(systemName: "plus")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("添加日程")
                    .accessibilityHint("以当前日期创建一条日程")
                }
            }
            .sheet(isPresented: $isDatePickerPresented) {
                datePickerSheet
            }
            .sheet(item: $editorPresentation, onDismiss: reloadCustomEvents) { presentation in
                CustomScheduleEditorSheet(presentation: presentation)
                    .presentationDetents([.medium, .large])
            }
            .onAppear {
                updateDefaultDayPartIfNeeded()
                reloadCustomEvents()
            }
            .onChange(of: selectedDate) { _, newDate in
                normalizeSelectedDate(newDate)
                selectedEventID = nil
                focusedStartDate = nil
                updateDefaultDayPartIfNeeded()
            }
            .onChange(of: selectedDayPart) { _, _ in
                selectedEventID = nil
                focusedStartDate = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .customScheduleEventsDidChange)) { _ in
                reloadCustomEvents()
            }
        }
    }

    private var dateHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isDatePickerPresented = true
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(DateFormatters.fullDateWithWeekday.string(from: selectedDate))
                            .title2()
                            .foregroundStyle(AppTheme.primaryText)
                        Text(isToday ? "今天" : selectedDayPart.title)
                            .leafySubheadline()
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "calendar")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.accentEmphasis)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .leafyGlassSurface(
                    in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous),
                    fallbackFill: AppTheme.cardBackground,
                    isInteractive: true
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("选择日期")
            .accessibilityValue(DateFormatters.fullDateWithWeekday.string(from: selectedDate))
            .accessibilityHint("打开图形日期选择器")
        }
    }

    private var dateRail: some View {
        let dates = relativeDates(around: selectedDate)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(dates, id: \.self) { date in
                    let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                    Button {
                        selectedDate = date
                    } label: {
                        VStack(spacing: 5) {
                            Text(shortWeekday(for: date))
                                .font(.system(size: 12 * controlScale, weight: .medium))
                            Text(calendarDayText(for: date))
                                .font(.system(size: 17 * controlScale, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(isSelected ? AppTheme.textOnAccent : AppTheme.primaryText)
                        .frame(width: 52, height: 52)
                        .background(
                            isSelected ? AppTheme.accent : AppTheme.cardBackground,
                            in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                                .stroke(isSelected ? AppTheme.accent : AppTheme.separator, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(DateFormatters.fullDateWithWeekday.string(from: date))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityHint("切换到这一天")
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private var dayPartPicker: some View {
        Picker("时段", selection: $selectedDayPart) {
            ForEach(ClockScheduleDayPart.allCases, id: \.self) { part in
                Text(part.title).tag(part)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("上午或下午")
    }

    private var dialSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isToday {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    dial(pointerDate: pointerDate(now: context.date))
                }
            } else {
                dial(pointerDate: focusedStartDate)
            }

            HStack(spacing: 8) {
                Image(systemName: isToday ? "location.north.line" : "hand.point.up.left")
                    .foregroundStyle(AppTheme.accentEmphasis)
                Text(pointerCaption)
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
                Spacer()
                Text("共 \(visibleEvents.count) 项")
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .padding(.horizontal, 4)
        }
    }

    private func dial(pointerDate: Date?) -> some View {
        ClockScheduleDial(
            date: selectedDate,
            dayPart: selectedDayPart,
            events: visibleEvents,
            selectedEventID: selectedEventID,
            pointerDate: pointerDate,
            onSelect: selectEvent
        )
        .frame(maxWidth: .infinity)
        .frame(height: 340)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("这段时间没有日程", systemImage: "clock")
        } description: {
            Text("点击右上角加号，添加一条本机日程。")
        } actions: {
            Button("添加日程") {
                presentNewSchedule()
            }
            .buttonStyle(.borderedProminent)
            .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .leafyCardStyle()
    }

    private func detailCard(for event: ClockScheduleEvent) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(eventColor(for: event))
                    .frame(width: 12, height: 12)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .leafyHeadline()
                    Text(event.source.title)
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                if event.source != .course {
                    Button("编辑") {
                        presentEditor(for: event)
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .accessibilityHint("打开日程编辑器")
                }
            }

            detailRow("时间", value: event.timeText, systemImage: "clock")
            if let location = event.location {
                detailRow("地点", value: location, systemImage: "mappin.and.ellipse")
            }
            if let note = event.note {
                detailRow("备注", value: note, systemImage: "note.text")
            }
            if let period = event.period {
                detailRow("课表节次", value: "第 \(period) 节", systemImage: "calendar.badge.clock")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .leafyCardStyle()
        .accessibilityElement(children: .contain)
    }

    private func detailRow(_ title: String, value: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
                Text(value)
                    .leafyBody()
                    .foregroundStyle(AppTheme.primaryText)
            }
            Spacer()
        }
    }

    private var datePickerSheet: some View {
        NavigationStack {
            DatePicker("选择日期", selection: $selectedDate, displayedComponents: [.date])
                .datePickerStyle(.graphical)
                .padding(AppSpacing.page)
                .navigationTitle("选择日期")
                .leafyInlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            isDatePickerPresented = false
                        }
                    }
                }
                .background(LeafyPageBackground())
        }
        .presentationDetents([.medium, .large])
    }

    private func selectEvent(_ event: ClockScheduleEvent) {
        selectedEventID = event.id
        focusedStartDate = event.startsAt
    }

    private func presentNewSchedule() {
        let context = defaultTimetableContext(for: selectedDate)
        editorPresentation = .importantDate(
            nil,
            defaultContext: context,
            allowsModeSelection: true,
            suggestedDate: suggestedStartDate(for: selectedDate)
        )
    }

    private func suggestedStartDate(for date: Date) -> Date {
        let calendar = Calendar.current
        let period = TimetablePeriodSchedule.defaultStudyPeriod(for: date)
        guard let slot = TimetablePeriodSchedule.slot(for: period) else { return date }
        return calendar.date(
            bySettingHour: slot.startHour,
            minute: slot.startMinute,
            second: 0,
            of: date
        ) ?? date
    }

    private func presentEditor(for event: ClockScheduleEvent) {
        switch event.source {
        case .course:
            return
        case .reminder:
            guard let id = UUID(uuidString: event.sourceID),
                  let reminder = reminders.first(where: { $0.id == id })
            else { return }
            editorPresentation = .timetable(
                context(for: reminder),
                allowsModeSelection: false,
                suggestedDate: selectedDate
            )
        case .customSchedule:
            guard let source = customEvents.first(where: { $0.id == event.sourceID }) else { return }
            editorPresentation = .importantDate(
                source,
                defaultContext: defaultTimetableContext(for: source.startsAt),
                allowsModeSelection: false,
                suggestedDate: source.startsAt
            )
        }
    }

    private func context(for reminder: TimetableCellReminder) -> TimetableCellReminderContext {
        TimetableCellReminderContext(
            week: reminder.week,
            day: reminder.dayOfWeek,
            period: reminder.displayStartPeriod,
            date: reminder.resolvedStartDate ?? selectedDate,
            occupiedPeriods: [],
            totalPeriods: TimetablePeriodSchedule.slots.count,
            reminder: reminder,
            allowsDateSelection: true
        )
    }

    private func defaultTimetableContext(for date: Date) -> TimetableCellReminderContext {
        let weekAndDay = semesterWeekAndDayIfSupported(for: date)
            ?? (week: SemesterConfig.currentWeek(date: date), day: weekdayNumber(for: date))
        let period = min(
            max(TimetablePeriodSchedule.defaultStudyPeriod(for: date), 1),
            TimetablePeriodSchedule.slots.count
        )
        return TimetableCellReminderContext(
            week: weekAndDay.week,
            day: weekAndDay.day,
            period: period,
            date: TimetablePeriodSchedule.startDate(
                week: weekAndDay.week,
                dayOfWeek: weekAndDay.day,
                period: period
            ) ?? date,
            occupiedPeriods: [],
            totalPeriods: TimetablePeriodSchedule.slots.count,
            reminder: nil,
            allowsDateSelection: true
        )
    }

    private func reloadCustomEvents() {
        customEvents = CustomScheduleStore.load()
        if let selectedEventID,
           !projection.events.contains(where: { $0.id == selectedEventID }) {
            self.selectedEventID = nil
        }
    }

    private func normalizeSelectedDate(_ date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        if day != date {
            selectedDate = day
        }
    }

    private func updateDefaultDayPartIfNeeded() {
        guard selectedEventID == nil else { return }
        if isToday {
            selectedDayPart = Self.defaultDayPart(for: Date())
        } else {
            selectedDayPart = projection.earliestEvent?.dayPart ?? .am
        }
    }

    private func pointerDate(now: Date) -> Date? {
        if isToday {
            let currentPart = Self.defaultDayPart(for: now)
            return currentPart == selectedDayPart ? now : nil
        }
        return focusedStartDate
    }

    private var pointerCaption: String {
        if isToday {
            return "指针显示当前时间"
        }
        if let focusedStartDate {
            return "指针聚焦 \(DateFormatters.timeOnly.string(from: focusedStartDate))"
        }
        return "点按事件后聚焦开始时间"
    }

    private func eventColor(for event: ClockScheduleEvent) -> Color {
        switch event.source {
        case .course:
            return AppTheme.courseCardColor(for: event.title)
        case .reminder:
            return AppTheme.accent
        case .customSchedule:
            return AppTheme.warning
        }
    }

    private func relativeDates(around date: Date) -> [Date] {
        let calendar = Calendar.current
        return (-3...3).compactMap { calendar.date(byAdding: .day, value: $0, to: date).map(calendar.startOfDay(for:)) }
    }

    private func calendarDayText(for date: Date) -> String {
        String(Calendar.current.component(.day, from: date))
    }

    private func shortWeekday(for date: Date) -> String {
        let weekday = Calendar.current.component(.weekday, from: date)
        let day = weekday == 1 ? 7 : weekday - 1
        return leafyLanguage.weekdayTitle(for: day)
    }

    private func weekdayNumber(for date: Date) -> Int {
        let weekday = Calendar.current.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }

    private func semesterWeekAndDayIfSupported(for date: Date) -> (week: Int, day: Int)? {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: SemesterConfig.startOfSemesterDate)
        let current = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: start, to: current).day ?? 0
        guard days >= 0, days < SemesterConfig.supportedWeeks * 7 else { return nil }
        return (days / 7 + 1, days % 7 + 1)
    }

    private static func defaultDayPart(for date: Date) -> ClockScheduleDayPart {
        Calendar.current.component(.hour, from: date) < 12 ? .am : .pm
    }
}

private struct ClockScheduleDial: View {
    let date: Date
    let dayPart: ClockScheduleDayPart
    let events: [ClockScheduleEvent]
    let selectedEventID: String?
    let pointerDate: Date?
    let onSelect: (ClockScheduleEvent) -> Void

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = side / 2 - 24

            ZStack {
                Circle()
                    .fill(AppTheme.cardBackground)
                    .overlay(Circle().stroke(AppTheme.separator, lineWidth: 1))

                ClockScheduleTicks()
                    .stroke(AppTheme.secondaryText.opacity(0.34), lineWidth: 1)
                    .padding(22)

                ForEach(1...12, id: \.self) { hour in
                    let angle = 2 * Double.pi * Double(hour) / 12 - Double.pi / 2
                    Text("\(hour)")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryText)
                        .position(
                            x: center.x + (radius - 58) * CGFloat(cos(angle)),
                            y: center.y + (radius - 58) * CGFloat(sin(angle))
                        )
                        .accessibilityHidden(true)
                }

                ForEach(events) { event in
                    ClockScheduleArc(
                        start: event.startsAt,
                        end: event.endsAt,
                        dayPart: dayPart,
                        radius: max(radius - CGFloat(event.lane) * 14, 46),
                        calendar: .current
                    )
                    .stroke(
                        eventColor(for: event).opacity(selectedEventID == event.id ? 0.96 : 0.62),
                        style: StrokeStyle(
                            lineWidth: selectedEventID == event.id ? 14 : 10,
                            lineCap: .round
                        )
                    )
                }

                if let pointerDate {
                    ClockSchedulePointer(date: pointerDate, dayPart: dayPart, calendar: .current)
                        .stroke(AppTheme.accentEmphasis, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .padding(32)
                    Circle()
                        .fill(AppTheme.accentEmphasis)
                        .frame(width: 8, height: 8)
                }

                ForEach(events) { event in
                    let eventPoint = point(
                        for: event,
                        center: center,
                        radius: max(radius - CGFloat(event.lane) * 14, 46)
                    )
                    Button {
                        onSelect(event)
                    } label: {
                        Text(event.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .padding(.horizontal, 9)
                            .frame(width: 72, height: 44)
                            .background(eventColor(for: event), in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(
                                        selectedEventID == event.id ? AppTheme.primaryText : .clear,
                                        lineWidth: 2
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .position(eventPoint)
                    .accessibilityLabel(event.title)
                    .accessibilityValue("\(event.source.title)，\(event.timeText)")
                    .accessibilityHint("查看日程详情")
                }

                VStack(spacing: 2) {
                    Text(pointerDate.map(DateFormatters.timeOnly.string) ?? dayPart.title)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text("\(events.count) 项")
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .accessibilityHidden(true)
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func point(for event: ClockScheduleEvent, center: CGPoint, radius: CGFloat) -> CGPoint {
        let start = ClockScheduleDialGeometry.minutes(on: event.startsAt, in: dayPart)
        let end = event.endsAt.map { ClockScheduleDialGeometry.minutes(on: $0, in: dayPart) }
            ?? min(start + 10, ClockScheduleDialGeometry.minutesPerDial)
        let midpoint = (start + end) / 2
        let angle = ClockScheduleDialGeometry.angle(for: midpoint)
        return CGPoint(
            x: center.x + radius * 0.74 * CGFloat(cos(angle)),
            y: center.y + radius * 0.74 * CGFloat(sin(angle))
        )
    }

    private func eventColor(for event: ClockScheduleEvent) -> Color {
        switch event.source {
        case .course:
            return AppTheme.courseCardColor(for: event.title)
        case .reminder:
            return AppTheme.accent
        case .customSchedule:
            return AppTheme.warning
        }
    }
}

private struct ClockScheduleArc: Shape {
    let start: Date
    let end: Date?
    let dayPart: ClockScheduleDayPart
    let radius: CGFloat
    let calendar: Calendar

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let startMinutes = ClockScheduleDialGeometry.minutes(on: start, in: dayPart, calendar: calendar)
        let endMinutes = end.map { ClockScheduleDialGeometry.minutes(on: $0, in: dayPart, calendar: calendar) }
            ?? min(startMinutes + 10, ClockScheduleDialGeometry.minutesPerDial)
        let startAngle = Angle.radians(ClockScheduleDialGeometry.angle(for: startMinutes))
        let endAngle = Angle.radians(ClockScheduleDialGeometry.angle(for: max(endMinutes, startMinutes + 1)))
        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        return path
    }
}

private struct ClockScheduleTicks: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for index in 0..<60 {
            let angle = 2 * Double.pi * Double(index) / 60 - Double.pi / 2
            let inner = radius - (index.isMultiple(of: 5) ? 12 : 5)
            path.move(to: CGPoint(x: center.x + inner * CGFloat(cos(angle)), y: center.y + inner * CGFloat(sin(angle))))
            path.addLine(to: CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle))))
        }
        return path
    }
}

private struct ClockSchedulePointer: Shape {
    let date: Date
    let dayPart: ClockScheduleDayPart
    let calendar: Calendar

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let minutes = ClockScheduleDialGeometry.minutes(on: date, in: dayPart, calendar: calendar)
        let angle = ClockScheduleDialGeometry.angle(for: minutes)
        let point = CGPoint(
            x: center.x + radius * 0.86 * CGFloat(cos(angle)),
            y: center.y + radius * 0.86 * CGFloat(sin(angle))
        )
        var path = Path()
        path.move(to: center)
        path.addLine(to: point)
        return path
    }
}

enum ClockScheduleDialGeometry {
    static let minutesPerDial = 12.0 * 60.0

    static func minutes(
        on date: Date,
        in dayPart: ClockScheduleDayPart,
        calendar: Calendar = .current
    ) -> Double {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let second = calendar.component(.second, from: date)
        let minutesOfDay = Double(hour * 60 + minute) + Double(second) / 60

        switch dayPart {
        case .am:
            return min(max(minutesOfDay, 0), minutesPerDial)
        case .pm:
            let adjusted = hour < 12 ? minutesOfDay + 24 * 60 : minutesOfDay
            return min(max(adjusted - minutesPerDial, 0), minutesPerDial)
        }
    }

    static func angle(for minutes: Double) -> Double {
        2 * Double.pi * minutes / minutesPerDial - Double.pi / 2
    }
}

private struct ClockSchedulePreview: View {
    let projection: ClockScheduleDayProjection
    @State private var selectedID: String?

    var body: some View {
        ScrollView {
            ClockScheduleDial(
                date: projection.date,
                dayPart: projection.events.first?.dayPart ?? .am,
                events: projection.events,
                selectedEventID: selectedID,
                pointerDate: projection.events.first?.startsAt,
                onSelect: { selectedID = $0.id }
            )
            .frame(height: 340)
            .padding()
        }
        .background(LeafyPageBackground())
    }
}

#Preview("日程·主要状态") {
    ClockSchedulePreview(projection: ClockSchedulePreviewData.main)
}

#Preview("日程·空状态") {
    ClockSchedulePreview(projection: ClockSchedulePreviewData.empty)
}

#Preview("日程·重叠状态") {
    ClockSchedulePreview(projection: ClockSchedulePreviewData.overlap)
}

private enum ClockSchedulePreviewData {
    static let date = Calendar.current.startOfDay(for: Date())

    static let main = ClockScheduleDayProjection(
        date: date,
        events: [
            sample(id: "course-a", source: .course, title: "数据结构", hour: 8, minute: 0, endHour: 8, endMinute: 45, lane: 0),
            sample(id: "custom-a", source: .customSchedule, title: "社团会议", hour: 10, minute: 20, endHour: 11, endMinute: 0, lane: 0)
        ]
    )

    static let empty = ClockScheduleDayProjection(date: date, events: [])

    static let overlap = ClockScheduleDayProjection(
        date: date,
        events: [
            sample(id: "course-overlap", source: .course, title: "高等数学", hour: 9, minute: 0, endHour: 10, endMinute: 30, lane: 0, laneCount: 2),
            sample(id: "reminder-overlap", source: .reminder, title: "交作业", hour: 9, minute: 30, endHour: 10, endMinute: 0, lane: 1, laneCount: 2)
        ]
    )

    private static func sample(
        id: String,
        source: ClockScheduleSource,
        title: String,
        hour: Int,
        minute: Int,
        endHour: Int,
        endMinute: Int,
        lane: Int,
        laneCount: Int = 1
    ) -> ClockScheduleEvent {
        let calendar = Calendar.current
        let start = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)!
        let end = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: date)!
        return ClockScheduleEvent(
            id: id,
            source: source,
            sourceID: id,
            title: title,
            sourceStartsAt: start,
            sourceEndsAt: end,
            startsAt: start,
            endsAt: end,
            location: nil,
            note: nil,
            period: nil,
            dayPart: hour < 12 ? .am : .pm,
            lane: lane,
            laneCount: laneCount
        )
    }
}
