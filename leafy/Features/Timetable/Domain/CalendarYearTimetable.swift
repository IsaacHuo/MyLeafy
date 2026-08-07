import Foundation

nonisolated struct CalendarYearTimetable: Sendable {
    let year: Int
    let weeks: [CalendarYearWeek]

    private let calendar: Calendar
    private let configurations: [SemesterRuntimeConfig]
    private let vacations: [SchoolCalendarEvent]

    init(
        year: Int,
        configurations: [SemesterRuntimeConfig],
        semanticEvents: [SchoolCalendarEvent] = [],
        referenceDate: Date? = nil,
        calendar: Calendar = .current
    ) {
        self.year = year
        self.calendar = calendar
        self.configurations = configurations.sorted { $0.semesterStartDate < $1.semesterStartDate }
        self.vacations = semanticEvents.filter { event in
            event.academicCategory == .winterBreak || event.academicCategory == .summerBreak
        }

        let yearStart = Self.startOfYear(year, calendar: calendar)
        let nextYearStart = calendar.date(byAdding: .year, value: 1, to: yearStart)!
        let firstWeekStart = Self.monday(containing: yearStart, calendar: calendar)
        let lastWeekStart = Self.monday(
            containing: calendar.date(byAdding: .day, value: -1, to: nextYearStart)!,
            calendar: calendar
        )
        let weekReferenceDate = referenceDate.map { calendar.startOfDay(for: $0) }

        var generated: [CalendarYearWeek] = []
        var weekStart = firstWeekStart
        while weekStart <= lastWeekStart {
            let weekEndExclusive = calendar.date(byAdding: .day, value: 7, to: weekStart)!
            let effectiveReferenceDate = Self.referenceDate(
                for: weekStart,
                yearStart: yearStart,
                nextYearStart: nextYearStart,
                requestedDate: weekReferenceDate,
                calendar: calendar
            )
            generated.append(
                CalendarYearWeek(
                    id: weekStart,
                    phase: Self.resolvePhase(
                        on: effectiveReferenceDate,
                        configurations: self.configurations,
                        vacations: self.vacations,
                        calendar: calendar
                    ),
                    referenceDate: effectiveReferenceDate
                )
            )
            weekStart = weekEndExclusive
        }
        self.weeks = generated
    }

    func phase(for date: Date) -> CalendarYearWeekPhase {
        phase(on: calendar.startOfDay(for: date))
    }

    func week(containing date: Date) -> CalendarYearWeek? {
        guard let pageIndex = pageIndex(containing: date) else { return nil }
        return weeks[pageIndex - 1]
    }

    func pageIndex(containing date: Date) -> Int? {
        let normalized = calendar.startOfDay(for: date)
        guard let index = weeks.firstIndex(where: { week in
            let end = calendar.date(byAdding: .day, value: 7, to: week.id)!
            return normalized >= week.id && normalized < end
        }) else { return nil }
        return index + 1
    }

    func week(atPageIndex pageIndex: Int) -> CalendarYearWeek? {
        guard weeks.indices.contains(pageIndex - 1) else { return nil }
        return weeks[pageIndex - 1]
    }

    func configuration(semesterID: String) -> SemesterRuntimeConfig? {
        configurations.first { $0.semesterID == semesterID }
    }

    private func phase(on date: Date) -> CalendarYearWeekPhase {
        Self.resolvePhase(
            on: date,
            configurations: configurations,
            vacations: vacations,
            calendar: calendar
        )
    }

    private static func resolvePhase(
        on date: Date,
        configurations: [SemesterRuntimeConfig],
        vacations: [SchoolCalendarEvent],
        calendar: Calendar
    ) -> CalendarYearWeekPhase {
        if let configuration = configurations.reversed().first(where: { configuration in
            let start = calendar.startOfDay(for: configuration.semesterStartDate)
            let end = calendar.date(byAdding: .day, value: 7 * 20, to: start)!
            return date >= start && date < end
        }) {
            let start = calendar.startOfDay(for: configuration.semesterStartDate)
            let days = calendar.dateComponents([.day], from: start, to: date).day ?? 0
            return .teaching(
                semesterID: configuration.semesterID,
                weekNumber: min(20, max(1, days / 7 + 1))
            )
        }

        if let vacation = vacations.first(where: { $0.contains(date, calendar: calendar) }),
           let category = vacation.academicCategory {
            return .vacation(title: vacation.title, category: category)
        }
        return .unconfigured
    }

    private static func referenceDate(
        for weekStart: Date,
        yearStart: Date,
        nextYearStart: Date,
        requestedDate: Date?,
        calendar: Calendar
    ) -> Date {
        if let requestedDate,
           requestedDate >= weekStart,
           requestedDate < calendar.date(byAdding: .day, value: 7, to: weekStart)!,
           requestedDate >= yearStart,
           requestedDate < nextYearStart {
            return requestedDate
        }
        return max(weekStart, yearStart)
    }

    private static func startOfYear(_ year: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(calendar: calendar, year: year, month: 1, day: 1))!
    }

    private static func monday(containing date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let mondayBasedOffset = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -mondayBasedOffset, to: day)!
    }
}

nonisolated struct CalendarYearWeek: Identifiable, Sendable {
    let id: Date
    let phase: CalendarYearWeekPhase
    let referenceDate: Date

    var weekStartDate: Date { id }

    func weekEndDate(calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 6, to: weekStartDate) ?? weekStartDate
    }
}

nonisolated enum CalendarYearWeekPhase: Equatable, Sendable {
    case teaching(semesterID: String, weekNumber: Int)
    case vacation(title: String, category: SchoolCalendarEvent.AcademicCategory)
    case unconfigured
}
