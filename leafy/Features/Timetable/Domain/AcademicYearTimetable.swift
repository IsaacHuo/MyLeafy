import Foundation

nonisolated struct AcademicYearTimetable: Sendable {
    let academicYearID: String
    let startDate: Date
    let endDate: Date
    let weeks: [AcademicYearWeek]

    private let calendar: Calendar
    private let configurations: [SemesterRuntimeConfig]
    private let vacations: [SchoolCalendarEvent]

    init(
        configurations: [SemesterRuntimeConfig],
        semanticEvents: [SchoolCalendarEvent] = [],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) {
        let sortedConfigurations = configurations.sorted {
            Self.semesterStartDate(for: $0, calendar: calendar)
                < Self.semesterStartDate(for: $1, calendar: calendar)
        }
        let academicYear = Self.resolveAcademicYear(
            for: referenceDate,
            configurations: sortedConfigurations,
            calendar: calendar
        )
        let bounds = Self.resolveBounds(
            for: academicYear,
            configurations: sortedConfigurations,
            calendar: calendar
        )

        academicYearID = academicYear.id
        startDate = bounds.start
        endDate = bounds.end
        self.calendar = calendar
        self.configurations = sortedConfigurations
        vacations = semanticEvents.filter { event in
            event.academicCategory == .winterBreak || event.academicCategory == .summerBreak
        }

        let firstWeekStart = Self.monday(containing: bounds.start, calendar: calendar)
        let lastDay = calendar.date(byAdding: .day, value: -1, to: bounds.end)!
        let lastWeekStart = Self.monday(containing: lastDay, calendar: calendar)
        let requestedDate = calendar.startOfDay(for: referenceDate)

        var generated: [AcademicYearWeek] = []
        var weekStart = firstWeekStart
        while weekStart <= lastWeekStart {
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!
            let effectiveReferenceDate = Self.referenceDate(
                for: weekStart,
                rangeStart: bounds.start,
                rangeEnd: bounds.end,
                requestedDate: requestedDate,
                calendar: calendar
            )
            generated.append(
                AcademicYearWeek(
                    id: weekStart,
                    phase: Self.resolvePhase(
                        on: effectiveReferenceDate,
                        configurations: sortedConfigurations,
                        vacations: vacations,
                        calendar: calendar
                    ),
                    referenceDate: effectiveReferenceDate
                )
            )
            weekStart = weekEnd
        }
        weeks = generated
    }

    var academicYearTitle: String {
        academicYearID.replacingOccurrences(of: "-", with: "–")
    }

    func contains(_ date: Date) -> Bool {
        let normalized = calendar.startOfDay(for: date)
        return normalized >= startDate && normalized < endDate
    }

    func phase(for date: Date) -> AcademicYearWeekPhase {
        Self.resolvePhase(
            on: calendar.startOfDay(for: date),
            configurations: configurations,
            vacations: vacations,
            calendar: calendar
        )
    }

    func week(containing date: Date) -> AcademicYearWeek? {
        guard let pageIndex = pageIndex(containing: date) else { return nil }
        return weeks[pageIndex - 1]
    }

    func pageIndex(containing date: Date) -> Int? {
        let normalized = calendar.startOfDay(for: date)
        guard contains(normalized),
              let index = weeks.firstIndex(where: { week in
                  let end = calendar.date(byAdding: .day, value: 7, to: week.id)!
                  return normalized >= week.id && normalized < end
              }) else { return nil }
        return index + 1
    }

    func week(atPageIndex pageIndex: Int) -> AcademicYearWeek? {
        guard weeks.indices.contains(pageIndex - 1) else { return nil }
        return weeks[pageIndex - 1]
    }

    func configuration(semesterID: String) -> SemesterRuntimeConfig? {
        configurations.first { $0.semesterID == semesterID }
    }

    func adjacentAcademicYear(
        toward direction: AcademicYearBoundaryDirection
    ) -> (timetable: AcademicYearTimetable, referenceDate: Date)? {
        let referenceDate: Date
        switch direction {
        case .previous:
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: startDate) else {
                return nil
            }
            referenceDate = previousDay
        case .next:
            referenceDate = endDate
        }

        let timetable = AcademicYearTimetable(
            configurations: configurations,
            semanticEvents: vacations,
            referenceDate: referenceDate,
            calendar: calendar
        )
        guard timetable.academicYearID != academicYearID,
              configurations.contains(where: {
                  Self.academicYearID(semesterID: $0.semesterID) == timetable.academicYearID
              }) else {
            return nil
        }
        return (timetable, referenceDate)
    }

    func courseIntersectsTimeline(_ course: Course) -> Bool {
        guard let configuration = configuration(semesterID: course.sourceSemesterID) else {
            return false
        }
        return course.weeks.contains { semesterWeek in
            guard let occurrenceDate = calendar.date(
                byAdding: .day,
                value: (semesterWeek - 1) * 7 + (course.dayOfWeek - 1),
                to: Self.semesterStartDate(for: configuration, calendar: calendar)
            ) else { return false }
            return contains(occurrenceDate)
        }
    }

    static func academicYearID(semesterID: String) -> String? {
        academicYear(from: semesterID)?.id
    }

    private static func resolvePhase(
        on date: Date,
        configurations: [SemesterRuntimeConfig],
        vacations: [SchoolCalendarEvent],
        calendar: Calendar
    ) -> AcademicYearWeekPhase {
        if let configuration = configurations.reversed().first(where: { configuration in
            let start = Self.semesterStartDate(for: configuration, calendar: calendar)
            let end = calendar.date(
                byAdding: .day,
                value: 7 * SemesterConfig.timetableWeekCapacity,
                to: start
            )!
            return date >= start && date < end
        }) {
            let start = Self.semesterStartDate(for: configuration, calendar: calendar)
            let days = calendar.dateComponents([.day], from: start, to: date).day ?? 0
            return .teaching(
                semesterID: configuration.semesterID,
                weekNumber: min(SemesterConfig.timetableWeekCapacity, max(1, days / 7 + 1))
            )
        }

        if let vacation = vacations.first(where: { $0.contains(date, calendar: calendar) }),
           let category = vacation.academicCategory {
            return .vacation(title: vacation.title, category: category)
        }
        return .unconfigured
    }

    private static func resolveAcademicYear(
        for referenceDate: Date,
        configurations: [SemesterRuntimeConfig],
        calendar: Calendar
    ) -> AcademicYearIdentity {
        let referenceDay = calendar.startOfDay(for: referenceDate)

        if let configuration = configurations.reversed().first(where: { configuration in
            let start = Self.semesterStartDate(for: configuration, calendar: calendar)
            let end = calendar.date(
                byAdding: .day,
                value: 7 * SemesterConfig.timetableWeekCapacity,
                to: start
            )!
            return referenceDay >= start && referenceDay < end
        }), let academicYear = academicYear(from: configuration.semesterID) {
            return academicYear
        }

        if let configuration = configurations.first(where: { configuration in
            configuration.calendarEvents.contains { event in
                event.isVacation && event.contains(referenceDay, calendar: calendar)
            }
        }), let academicYear = academicYear(from: configuration.semesterID) {
            return academicYear
        }

        if let configuration = configurations.first(where: \.isActive),
           let academicYear = Self.academicYear(from: configuration.semesterID) {
            return academicYear
        }

        if let configuration = configurations.last(where: {
            Self.semesterStartDate(for: $0, calendar: calendar) <= referenceDay
        }),
           let academicYear = academicYear(from: configuration.semesterID) {
            return academicYear
        }

        if let configuration = configurations.first,
           let academicYear = academicYear(from: configuration.semesterID) {
            return academicYear
        }

        let year = calendar.component(.year, from: referenceDay)
        let month = calendar.component(.month, from: referenceDay)
        let startYear = month >= 9 ? year : year - 1
        return AcademicYearIdentity(startYear: startYear, endYear: startYear + 1)
    }

    private static func resolveBounds(
        for academicYear: AcademicYearIdentity,
        configurations: [SemesterRuntimeConfig],
        calendar: Calendar
    ) -> (start: Date, end: Date) {
        let fallStart = configurations.first { configuration in
            Self.academicYear(from: configuration.semesterID)?.id == academicYear.id
                && configuration.semesterID.split(separator: "-").last == "1"
        }.map { Self.semesterStartDate(for: $0, calendar: calendar) }

        let nextAcademicYear = AcademicYearIdentity(
            startYear: academicYear.endYear,
            endYear: academicYear.endYear + 1
        )
        let nextFallStart = configurations.first { configuration in
            Self.academicYear(from: configuration.semesterID)?.id == nextAcademicYear.id
                && configuration.semesterID.split(separator: "-").last == "1"
        }.map { Self.semesterStartDate(for: $0, calendar: calendar) }

        let resolvedStart: Date
        if let fallStart {
            resolvedStart = calendar.startOfDay(for: fallStart)
        } else if let nextFallStart,
                  let inferredStart = calendar.date(byAdding: .year, value: -1, to: nextFallStart) {
            resolvedStart = calendar.startOfDay(for: inferredStart)
        } else {
            resolvedStart = calendar.date(
                from: DateComponents(
                    calendar: calendar,
                    year: academicYear.startYear,
                    month: 9,
                    day: 1
                )
            )!
        }

        let resolvedEnd: Date
        if let nextFallStart {
            resolvedEnd = calendar.startOfDay(for: nextFallStart)
        } else if let inferredEnd = calendar.date(byAdding: .year, value: 1, to: resolvedStart) {
            resolvedEnd = calendar.startOfDay(for: inferredEnd)
        } else {
            resolvedEnd = calendar.date(
                from: DateComponents(
                    calendar: calendar,
                    year: academicYear.endYear,
                    month: 9,
                    day: 1
                )
            )!
        }

        if resolvedEnd > resolvedStart {
            return (resolvedStart, resolvedEnd)
        }
        return (
            resolvedStart,
            calendar.date(byAdding: .year, value: 1, to: resolvedStart)!
        )
    }

    private static func academicYear(from semesterID: String) -> AcademicYearIdentity? {
        let parts = semesterID.split(separator: "-")
        guard parts.count >= 2,
              let startYear = Int(parts[0]),
              let endYear = Int(parts[1]),
              endYear > startYear else { return nil }
        return AcademicYearIdentity(startYear: startYear, endYear: endYear)
    }

    private static func semesterStartDate(
        for configuration: SemesterRuntimeConfig,
        calendar: Calendar
    ) -> Date {
        let parts = configuration.semesterStartDateString.split(separator: "-")
        if parts.count == 3,
           let year = Int(parts[0]),
           let month = Int(parts[1]),
           let day = Int(parts[2]),
           let date = calendar.date(from: DateComponents(
               calendar: calendar,
               timeZone: calendar.timeZone,
               year: year,
               month: month,
               day: day
           )) {
            return date
        }
        return calendar.startOfDay(for: configuration.semesterStartDate)
    }

    private static func referenceDate(
        for weekStart: Date,
        rangeStart: Date,
        rangeEnd: Date,
        requestedDate: Date,
        calendar: Calendar
    ) -> Date {
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!
        if requestedDate >= weekStart,
           requestedDate < weekEnd,
           requestedDate >= rangeStart,
           requestedDate < rangeEnd {
            return requestedDate
        }
        return max(weekStart, rangeStart)
    }

    private static func monday(containing date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let mondayBasedOffset = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -mondayBasedOffset, to: day)!
    }
}

private nonisolated struct AcademicYearIdentity: Sendable {
    let startYear: Int
    let endYear: Int

    var id: String { "\(startYear)-\(endYear)" }
}

nonisolated struct AcademicYearWeek: Identifiable, Sendable {
    let id: Date
    let phase: AcademicYearWeekPhase
    let referenceDate: Date

    var weekStartDate: Date { id }

    func weekEndDate(calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 6, to: weekStartDate) ?? weekStartDate
    }
}

nonisolated enum AcademicYearWeekPhase: Equatable, Sendable {
    case teaching(semesterID: String, weekNumber: Int)
    case vacation(title: String, category: SchoolCalendarEvent.AcademicCategory)
    case unconfigured
}

nonisolated enum AcademicYearBoundaryDirection: Equatable, Sendable {
    case previous
    case next
}
