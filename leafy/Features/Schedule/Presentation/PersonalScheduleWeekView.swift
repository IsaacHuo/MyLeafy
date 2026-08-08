import SwiftData
import SwiftUI

struct PersonalScheduleBlockValue: Identifiable {
    enum Source {
        case reminder(UUID)
        case event(String)
    }

    let id: String
    let source: Source
    let title: String
    let locationText: String
    let startsAt: Date
    let endsAt: Date
    let startPeriod: Int
    let endPeriod: Int

    init(reminder: TimetableCellReminder) {
        let start = reminder.resolvedStartDate ?? Date()
        let end = reminder.resolvedEndDate.flatMap { $0 > start ? $0 : nil }
            ?? start.addingTimeInterval(45 * 60)
        let range = TimetablePeriodSchedule.periodRange(overlapping: start, endDate: end)
        let fallback = TimetablePeriodSchedule.periodForFocus(containing: start)?.period ?? 1
        id = "reminder-\(reminder.id.uuidString)"
        source = .reminder(reminder.id)
        title = reminder.title
        locationText = reminder.locationText
        startsAt = start
        endsAt = end
        startPeriod = range?.lowerBound ?? fallback
        endPeriod = range?.upperBound ?? fallback
    }

    init(event: CustomScheduleEvent) {
        let end = event.endsAt.flatMap { $0 > event.startsAt ? $0 : nil }
            ?? event.startsAt.addingTimeInterval(45 * 60)
        let range = TimetablePeriodSchedule.periodRange(overlapping: event.startsAt, endDate: end)
        let fallback = TimetablePeriodSchedule.periodForFocus(containing: event.startsAt)?.period ?? 1
        id = "event-\(event.id)"
        source = .event(event.id)
        title = event.title
        locationText = event.locationText
        startsAt = event.startsAt
        endsAt = end
        startPeriod = range?.lowerBound ?? fallback
        endPeriod = range?.upperBound ?? fallback
    }

    init(reminder: TimetableCellReminderRenderValue) {
        let start = reminder.resolvedStartDate ?? Date()
        let end = reminder.resolvedEndDate.flatMap { $0 > start ? $0 : nil }
            ?? start.addingTimeInterval(45 * 60)
        id = "reminder-\(reminder.id.uuidString)"
        source = .reminder(reminder.id)
        title = reminder.title
        locationText = reminder.locationText
        startsAt = start
        endsAt = end
        startPeriod = reminder.displayStartPeriod
        endPeriod = reminder.displayEndPeriod
    }

    init(countdown: TimetableCountdownProjection) {
        id = "event-\(countdown.eventID)"
        source = .event(countdown.eventID)
        title = countdown.title
        locationText = ""
        startsAt = countdown.startsAt
        endsAt = countdown.endsAt
        startPeriod = countdown.startPeriod
        endPeriod = countdown.endPeriod
    }
}

struct PersonalScheduleBlockView: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference
    @AppStorage("appThemeColorPreference") private var appThemeColorPreferenceRaw = AppThemeColorPreference.green.rawValue

    let value: PersonalScheduleBlockValue
    let height: CGFloat
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 2.5 * leafyControlScale) {
            HStack(alignment: .firstTextBaseline, spacing: 4 * leafyControlScale) {
                Image(systemName: "calendar.day.timeline.left")
                    .font(.system(size: iconFontSize, weight: .semibold))
                    .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))

                Text(value.title)
                    .font(.system(size: titleFontSize, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(height < 40 * leafyControlScale ? 1 : 2)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
            }

            if height > 34 * leafyControlScale {
                Text(subtitle)
                    .font(.system(size: captionFontSize, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(.horizontal, 4.5 * leafyControlScale)
        .padding(.vertical, 4 * leafyControlScale)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(blockBackground)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.small * 0.72, style: .continuous)
                .stroke(AppTheme.accent.opacity(colorScheme == .dark ? 0.28 : 0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small * 0.72, style: .continuous))
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0 : 0.025), radius: 1)
        .accessibilityLabel(accessibilityText)
    }

    private var titleFontSize: CGFloat { (height < 36 * leafyControlScale ? 9.2 : 10.4) * leafyControlScale }
    private var iconFontSize: CGFloat { (height < 36 * leafyControlScale ? 8.2 : 9.2) * leafyControlScale }
    private var captionFontSize: CGFloat { (height < 42 * leafyControlScale ? 7.4 : 8.2) * leafyControlScale }

    private var subtitle: String {
        let time = "\(DateFormatters.timeOnly.string(from: value.startsAt))–\(DateFormatters.timeOnly.string(from: value.endsAt))"
        return value.locationText.isEmpty ? time : "\(time) · \(value.locationText)"
    }

    private var blockBackground: Color {
        if colorScheme == .dark {
            return AppTheme.accent(for: themeColorPreference).opacity(0.3)
        }
        return AppTheme.courseCardColor(
            for: value.id + value.title,
            themeColorPreferenceRaw: appThemeColorPreferenceRaw
        )
        .opacity(0.9)
    }

    private var accessibilityText: String {
        value.locationText.isEmpty
            ? "\(value.title)，\(subtitle)"
            : "\(value.title)，\(value.locationText)，\(subtitle)"
    }
}

struct PersonalScheduleWeekView: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference
    @Query private var reminders: [TimetableCellReminder]

    @State private var events: [CustomScheduleEvent]
    @State private var displayedYear: Int
    @State private var currentWeek: Int
    @State private var scrollToWeek: Int?
    @State private var isAwayFromCurrentWeek = false
    @State private var editorPresentation: CustomScheduleEditorPresentation?
    @State private var showsTimeView = false
    @State private var layoutMetricsCache = TimetableLayoutMetricsCache()

    private let totalClasses = TimetablePeriodSchedule.slots.count
    private let visibleDays = Array(1...7)

    init(referenceDate: Date = Date(), calendar: Calendar = .current) {
        let year = calendar.component(.year, from: referenceDate)
        let timeline = PersonalScheduleYearTimeline(year: year, calendar: calendar)
        let page = timeline.pageIndex(containing: referenceDate, calendar: calendar) ?? 1
        _events = State(initialValue: CustomScheduleStore.load())
        _displayedYear = State(initialValue: year)
        _currentWeek = State(initialValue: page)
        _scrollToWeek = State(initialValue: page)
    }

    private var timeline: PersonalScheduleYearTimeline {
        PersonalScheduleYearTimeline(year: displayedYear)
    }

    private var items: [PersonalScheduleBlockValue] {
        let reminderItems = reminders.compactMap { reminder -> PersonalScheduleBlockValue? in
            guard reminder.resolvedStartDate != nil else { return nil }
            return PersonalScheduleBlockValue(reminder: reminder)
        }
        return (reminderItems + events.map { PersonalScheduleBlockValue(event: $0) })
            .sorted { lhs, rhs in
                if lhs.startsAt != rhs.startsAt { return lhs.startsAt < rhs.startsAt }
                return lhs.title.localizedCompare(rhs.title) == .orderedAscending
            }
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = layoutMetrics(for: geometry.size)
            TimetableScrollContainer(
                axisWidth: axisWidth,
                headerHeight: headerHeight,
                totalWeeks: timeline.weeks.count,
                weekStride: metrics.weekStride,
                dayColumnWidth: metrics.dayColumnWidth,
                rowHeight: metrics.rowHeight,
                rowSpacing: metrics.rowSpacing,
                allowsVerticalScroll: metrics.allowsVerticalScroll,
                currentWeek: $currentWeek,
                scrollToWeek: $scrollToWeek,
                isAwayFromCurrentWeek: $isAwayFromCurrentWeek,
                containerID: "personal-schedule-\(displayedYear)",
                currentWeekProvider: { currentPageForDisplayedYear ?? 0 },
                corner: {
                    cornerHeader
                        .frame(width: axisWidth, height: headerHeight)
                },
                header: {
                    headerContent(metrics: metrics)
                },
                axis: {
                    timeAxis(metrics: metrics)
                },
                body: {
                    gridContent(metrics: metrics)
                }
            )
            .frame(width: metrics.containerWidth, height: metrics.containerHeight, alignment: .topLeading)
            .padding(.horizontal, metrics.horizontalPadding)
            .transaction { $0.animation = nil }
        }
        .background(LeafyPageBackground())
        .navigationTitle("我的日程")
        .leafyInlineNavigationTitle()
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isAwayFromCurrentWeek {
                    Button("回到") { returnToCurrentWeek() }
                        .frame(minHeight: 44)
                        .accessibilityLabel("回到本周")
                }

                Button(weekTitle) { showsTimeView = true }
                    .frame(minHeight: 44)
                    .accessibilityLabel("时间视图，\(weekTitle)")

                Button {
                    presentNewSchedule()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("添加个人日程")
            }
        }
        .leafySheet(item: $editorPresentation, onDismiss: reloadEvents) { presentation in
            CustomScheduleEditorSheet(presentation: presentation)
                .presentationDetents([.medium, .large])
        }
        .leafySheet(isPresented: $showsTimeView) {
            PersonalScheduleTimeView(
                selectedYear: displayedYear,
                selectedPage: currentWeek,
                onSelect: select(year:page:)
            )
            .frame(idealWidth: 420, idealHeight: 520)
            .presentationDetents([.medium, .large])
        }
        .onChange(of: currentWeek) { _, page in
            updateAwayState(page: page)
        }
        .onReceive(NotificationCenter.default.publisher(for: .customScheduleEventsDidChange)) { _ in
            reloadEvents()
        }
    }

    private var axisWidth: CGFloat { 34 * leafyControlScale }
    private var headerHeight: CGFloat { 52 * leafyControlScale }

    private func layoutMetrics(for size: CGSize) -> TimetableLayoutMetrics {
        layoutMetricsCache.metrics(
            size: size,
            dayCount: visibleDays.count,
            totalClasses: totalClasses,
            axisWidth: axisWidth,
            headerHeight: headerHeight,
            horizontalPadding: 4 * leafyControlScale,
            daySpacing: 5 * leafyControlScale,
            weekSpacing: 6 * leafyControlScale,
            rowSpacing: 1.5 * leafyControlScale,
            minimumRowHeight: 26 * leafyControlScale,
            cardInset: 1.5 * leafyControlScale,
            laneSpacing: 2 * leafyControlScale,
            bottomClearance: 16 * leafyControlScale,
            controlScale: leafyControlScale,
            interPaneSpacing: AppSpacing.micro,
            allowsAgendaList: false
        )
    }

    private var renderedWeeks: [Int] {
        TimetableRenderedWeekWindow.pages(
            currentWeek: currentWeek,
            pendingWeek: scrollToWeek,
            totalWeeks: timeline.weeks.count
        )
    }

    private func headerContent(metrics: TimetableLayoutMetrics) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(renderedWeeks, id: \.self) { week in
                HStack(alignment: .top, spacing: metrics.daySpacing) {
                    ForEach(visibleDays, id: \.self) { day in
                        if let date = timeline.date(page: week, dayOfWeek: day), timeline.contains(date) {
                            dayHeader(date: date, day: day)
                                .frame(width: metrics.dayColumnWidth, height: headerHeight)
                        } else {
                            Color.clear
                                .frame(width: metrics.dayColumnWidth, height: headerHeight)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .offset(x: CGFloat(week - 1) * metrics.weekStride)
                .accessibilityHidden(week != currentWeek)
            }
        }
        .frame(width: contentWidth(metrics: metrics), height: headerHeight, alignment: .topLeading)
    }

    private func gridContent(metrics: TimetableLayoutMetrics) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(renderedWeeks, id: \.self) { week in
                HStack(alignment: .top, spacing: metrics.daySpacing) {
                    ForEach(visibleDays, id: \.self) { day in
                        if let date = timeline.date(page: week, dayOfWeek: day), timeline.contains(date) {
                            dayColumn(date: date, week: week, day: day, metrics: metrics)
                                .frame(width: metrics.dayColumnWidth, height: metrics.gridHeight)
                        } else {
                            Color.clear
                                .frame(width: metrics.dayColumnWidth, height: metrics.gridHeight)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .offset(x: CGFloat(week - 1) * metrics.weekStride)
                .accessibilityHidden(week != currentWeek)
            }

            currentTimeIndicator(metrics: metrics)
        }
        .frame(width: contentWidth(metrics: metrics), height: metrics.gridHeight, alignment: .topLeading)
    }

    private func dayColumn(
        date: Date,
        week: Int,
        day: Int,
        metrics: TimetableLayoutMetrics
    ) -> some View {
        let dayItems = items.filter { Calendar.current.isDate($0.startsAt, inSameDayAs: date) }
        let occupiedPeriods = Set(dayItems.flatMap { Array($0.startPeriod...$0.endPeriod) })

        return ZStack(alignment: .topLeading) {
            gridBackground(width: metrics.dayColumnWidth, metrics: metrics)

            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture().onEnded { value in
                        guard let period = period(at: value.location.y, metrics: metrics),
                              !occupiedPeriods.contains(period) else { return }
                        presentNewSchedule(date: date, week: week, day: day, period: period)
                    }
                )
                .accessibilityHidden(true)

            if let freePeriod = (1...totalClasses).first(where: { !occupiedPeriods.contains($0) }) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityLabel("\(DateFormatters.header.string(from: date))添加日程")
                    .accessibilityHint("添加第 \(freePeriod) 节个人日程")
                    .accessibilityAction {
                        presentNewSchedule(date: date, week: week, day: day, period: freePeriod)
                    }
            }

            ForEach(dayItems) { item in
                let geometry = TimetableScheduleBlockGeometry.make(
                    startDate: item.startsAt,
                    endDate: item.endsAt,
                    fallbackStartPeriod: item.startPeriod,
                    fallbackEndPeriod: item.endPeriod,
                    metrics: metrics,
                    minimumHeight: 18 * leafyControlScale
                )
                PersonalScheduleBlockView(
                    value: item,
                    height: geometry.height,
                    width: max(metrics.dayColumnWidth - metrics.cardInset * 2, 1)
                )
                .position(x: metrics.dayColumnWidth * 0.5, y: geometry.centerY)
                .zIndex(2)
                .onTapGesture { edit(item, week: week, day: day) }
            }
        }
    }

    private var cornerHeader: some View {
        let date = timeline.weekStart(at: currentWeek) ?? timeline.startDate
        let month = Calendar.current.component(.month, from: date)
        return Text("\(month)月")
            .font(.system(size: 11.5 * leafyControlScale, weight: .semibold))
            .foregroundStyle(AppTheme.secondaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                    .fill(AppTheme.cardBackground.opacity(0.62))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                    .stroke(AppTheme.separator, lineWidth: 1)
            )
    }

    private func dayHeader(date: Date, day: Int) -> some View {
        let isToday = Calendar.current.isDateInToday(date)
        return VStack(spacing: 2) {
            Text(["周一", "周二", "周三", "周四", "周五", "周六", "周日"][day - 1])
                .font(.system(size: 14 * leafyControlScale, weight: .semibold))
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 11.5 * leafyControlScale, weight: .semibold))
        }
        .foregroundStyle(isToday ? AppTheme.textOnAccent : AppTheme.primaryText)
        .frame(maxWidth: .infinity, minHeight: headerHeight)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                .fill(isToday ? AppTheme.accent : AppTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                .stroke(isToday ? Color.clear : AppTheme.separator, lineWidth: 1)
        )
    }

    private func timeAxis(metrics: TimetableLayoutMetrics) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(TimetablePeriodSchedule.slots, id: \.period) { slot in
                VStack(spacing: 0) {
                    Text(slot.startText).font(.system(size: 6.4 * leafyControlScale, weight: .medium))
                    Text("\(slot.period)").font(.system(size: 15 * leafyControlScale, weight: .semibold))
                    Text(slot.endText).font(.system(size: 6.4 * leafyControlScale, weight: .medium))
                }
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: axisWidth, height: metrics.rowHeight)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                        .fill(AppTheme.cardBackground.opacity(0.52))
                )
                .position(
                    x: axisWidth * 0.5,
                    y: yPosition(period: slot.period, metrics: metrics) + metrics.rowHeight * 0.5
                )
            }
        }
        .frame(width: axisWidth, height: metrics.gridHeight, alignment: .topLeading)
    }

    @ViewBuilder
    private func currentTimeIndicator(metrics: TimetableLayoutMetrics) -> some View {
        if displayedYear == Calendar.current.component(.year, from: Date()),
           currentWeek == currentPageForDisplayedYear,
           let y = TimetableCurrentTimePosition.yPosition(for: Date(), metrics: metrics) {
            Rectangle()
                .fill(AppTheme.accentEmphasis(for: themeColorPreference))
                .frame(width: TimetableCurrentTimeIndicatorGeometry.width(visibleDayCount: 7, metrics: metrics), height: 2)
                .position(
                    x: TimetableCurrentTimeIndicatorGeometry.centerX(page: currentWeek, visibleDayCount: 7, metrics: metrics),
                    y: y
                )
                .zIndex(10)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func gridBackground(width: CGFloat, metrics: TimetableLayoutMetrics) -> some View {
        Canvas { context, _ in
            for period in 1...totalClasses {
                let rect = CGRect(
                    x: 0,
                    y: yPosition(period: period, metrics: metrics),
                    width: width,
                    height: metrics.rowHeight
                )
                context.opacity = period == 5 || period == 9 ? 1 : 0.72
                context.fill(
                    Path(roundedRect: rect, cornerRadius: AppRadius.small),
                    with: .color(period.isMultiple(of: 2) ? AppTheme.fill.opacity(0.72) : AppTheme.cardBackground.opacity(0.72))
                )
            }
        }
        .frame(width: width, height: metrics.gridHeight)
        .accessibilityHidden(true)
    }

    private func contentWidth(metrics: TimetableLayoutMetrics) -> CGFloat {
        max(CGFloat(timeline.weeks.count) * metrics.weekStride - metrics.weekSpacing, 1)
    }

    private func yPosition(period: Int, metrics: TimetableLayoutMetrics) -> CGFloat {
        CGFloat(max(period - 1, 0)) * (metrics.rowHeight + metrics.rowSpacing)
    }

    private func period(at y: CGFloat, metrics: TimetableLayoutMetrics) -> Int? {
        (1...totalClasses).first { period in
            let start = yPosition(period: period, metrics: metrics)
            return y >= start && y <= start + metrics.rowHeight
        }
    }

    private var currentPageForDisplayedYear: Int? {
        timeline.pageIndex(containing: Date())
    }

    private var weekTitle: String {
        guard let start = timeline.weekStart(at: currentWeek) else { return "\(displayedYear)年" }
        let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
        return "\(displayedYear) · \(DateFormatters.chineseDay.string(from: max(start, timeline.startDate)))–\(DateFormatters.chineseDay.string(from: min(end, timeline.endDate.addingTimeInterval(-1))))"
    }

    private func select(year: Int, page: Int) {
        displayedYear = year
        let selectedTimeline = PersonalScheduleYearTimeline(year: year)
        currentWeek = min(max(page, 1), selectedTimeline.weeks.count)
        scrollToWeek = currentWeek
        showsTimeView = false
        updateAwayState(page: currentWeek)
    }

    private func returnToCurrentWeek() {
        let now = Date()
        let year = Calendar.current.component(.year, from: now)
        let currentTimeline = PersonalScheduleYearTimeline(year: year)
        let page = currentTimeline.pageIndex(containing: now) ?? 1
        displayedYear = year
        currentWeek = page
        scrollToWeek = page
        isAwayFromCurrentWeek = false
    }

    private func updateAwayState(page: Int) {
        let currentYear = Calendar.current.component(.year, from: Date())
        isAwayFromCurrentWeek = displayedYear != currentYear || page != currentPageForDisplayedYear
    }

    private func presentNewSchedule() {
        let preferredDay: Int
        if displayedYear == Calendar.current.component(.year, from: Date()), currentWeek == currentPageForDisplayedYear {
            let weekday = Calendar.current.component(.weekday, from: Date())
            preferredDay = weekday == 1 ? 7 : weekday - 1
        } else {
            preferredDay = 1
        }
        let period = TimetablePeriodSchedule.defaultStudyPeriod()
        guard let date = timeline.date(page: currentWeek, dayOfWeek: preferredDay), timeline.contains(date) else { return }
        presentNewSchedule(date: date, week: currentWeek, day: preferredDay, period: period)
    }

    private func presentNewSchedule(date: Date, week: Int, day: Int, period: Int) {
        let context = editorContext(
            date: date,
            week: week,
            day: day,
            period: period,
            reminder: nil
        )
        editorPresentation = .timetable(context)
    }

    private func edit(_ item: PersonalScheduleBlockValue, week: Int, day: Int) {
        switch item.source {
        case .reminder(let id):
            guard let reminder = reminders.first(where: { $0.id == id }) else { return }
            editorPresentation = .timetable(
                editorContext(
                    date: item.startsAt,
                    week: week,
                    day: day,
                    period: item.startPeriod,
                    reminder: reminder
                ),
                allowsModeSelection: false
            )
        case .event(let id):
            guard let event = events.first(where: { $0.id == id }) else { return }
            editorPresentation = .importantDate(
                event,
                defaultContext: editorContext(
                    date: item.startsAt,
                    week: week,
                    day: day,
                    period: item.startPeriod,
                    reminder: nil
                ),
                allowsModeSelection: false
            )
        }
    }

    private func editorContext(
        date: Date,
        week: Int,
        day: Int,
        period: Int,
        reminder: TimetableCellReminder?
    ) -> TimetableCellReminderContext {
        let slot = TimetablePeriodSchedule.slot(for: period)
        let resolvedDate = slot.flatMap {
            Calendar.current.date(bySettingHour: $0.startHour, minute: $0.startMinute, second: 0, of: date)
        } ?? date
        return TimetableCellReminderContext(
            week: week,
            day: day,
            period: period,
            date: resolvedDate,
            occupiedPeriods: [],
            totalPeriods: totalClasses,
            reminder: reminder,
            allowsDateSelection: true
        )
    }

    private func reloadEvents() {
        events = CustomScheduleStore.load()
    }
}

private struct PersonalScheduleTimeView: View {
    let selectedYear: Int
    let selectedPage: Int
    let onSelect: (Int, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var browsingYear: Int

    private let columns = Array(repeating: GridItem(.flexible(minimum: 68), spacing: AppSpacing.compact), count: 4)

    init(selectedYear: Int, selectedPage: Int, onSelect: @escaping (Int, Int) -> Void) {
        self.selectedYear = selectedYear
        self.selectedPage = selectedPage
        self.onSelect = onSelect
        _browsingYear = State(initialValue: selectedYear)
    }

    private var timeline: PersonalScheduleYearTimeline {
        PersonalScheduleYearTimeline(year: browsingYear)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    HStack {
                        Button { browsingYear -= 1 } label: {
                            Image(systemName: "chevron.left").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("上一年")

                        Spacer()
                        Text("\(browsingYear)年")
                            .font(.title3.weight(.semibold))
                        Spacer()

                        Button { browsingYear += 1 } label: {
                            Image(systemName: "chevron.right").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("下一年")
                    }

                    LazyVGrid(columns: columns, spacing: AppSpacing.compact) {
                        ForEach(Array(timeline.weeks.enumerated()), id: \.offset) { index, start in
                            let page = index + 1
                            Button {
                                onSelect(browsingYear, page)
                            } label: {
                                VStack(spacing: 3) {
                                    Text("第 \(page) 周")
                                        .font(.subheadline.weight(.semibold))
                                    Text(DateFormatters.chineseDay.string(from: max(start, timeline.startDate)))
                                        .microCaption()
                                }
                                .frame(maxWidth: .infinity, minHeight: 48)
                            }
                            .buttonStyle(.bordered)
                            .tint(browsingYear == selectedYear && page == selectedPage ? AppTheme.accent : AppTheme.secondaryText)
                        }
                    }
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle("时间视图")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
        }
    }
}
