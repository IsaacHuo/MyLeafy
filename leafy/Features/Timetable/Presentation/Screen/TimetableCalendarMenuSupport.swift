import Foundation

nonisolated struct TimetableCalendarMenuModel {
    let academicYears: [TimetableCalendarMenuAcademicYear]
    let currentSemesterID: String?
    let currentVacationID: String?
    let defaultExpandedSemesterIDs: Set<String>
    let unavailableFutureConfigurationMessage: String?
    let primaryTimeViewAcademicYearID: String?

    var timeViewAcademicYears: [TimetableCalendarMenuAcademicYear] {
        academicYears.compactMap { academicYear in
            guard academicYear.academicYear == primaryTimeViewAcademicYearID else { return nil }
            let stages = academicYear.stages.filter { $0.semesterID != nil }
            guard !stages.isEmpty else { return nil }
            return TimetableCalendarMenuAcademicYear(
                academicYear: academicYear.academicYear,
                stages: stages
            )
        }
    }

    var historyTimeViewAcademicYears: [TimetableCalendarMenuAcademicYear] {
        academicYears.filter { $0.academicYear != primaryTimeViewAcademicYearID }
    }

    init(
        timetable: AcademicYearTimetable,
        configurations: [SemesterRuntimeConfig],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) {
        let referencePhase = timetable.phase(for: referenceDate)
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let sortedConfigurations = configurations.sorted { $0.semesterStartDate < $1.semesterStartDate }
        let primaryConfiguration = sortedConfigurations.first {
            calendar.startOfDay(for: $0.semesterStartDate) >= referenceDay
        } ?? sortedConfigurations.last
        primaryTimeViewAcademicYearID = primaryConfiguration.map {
            Self.academicYearTitle(semesterID: $0.semesterID)
        }
        let resolvedCurrentSemesterID: String?
        if case let .teaching(semesterID, _) = referencePhase {
            resolvedCurrentSemesterID = semesterID
        } else {
            resolvedCurrentSemesterID = nil
        }
        currentSemesterID = resolvedCurrentSemesterID

        var stagesByAcademicYear: [String: [TimetableCalendarMenuStage]] = [:]
        for configuration in sortedConfigurations {
            let academicYear = Self.academicYearTitle(semesterID: configuration.semesterID)
            let weeks: [TimetableCalendarMenuWeek] = (1...SemesterConfig.timetableWeekCapacity).compactMap { weekNumber -> TimetableCalendarMenuWeek? in
                guard let targetDate = calendar.date(
                    byAdding: .day,
                    value: (weekNumber - 1) * 7,
                    to: configuration.semesterStartDate
                ) else { return nil }
                let targetTimetable = timetable.contains(targetDate)
                    ? timetable
                    : AcademicYearTimetable(
                        configurations: sortedConfigurations,
                        semanticEvents: sortedConfigurations.flatMap(\.calendarEvents),
                        referenceDate: targetDate,
                        calendar: calendar
                    )
                guard let page = targetTimetable.pageIndex(containing: targetDate) else { return nil }
                return TimetableCalendarMenuWeek(
                    page: page,
                    weekNumber: weekNumber,
                    targetDate: targetDate
                )
            }
            let semester = TimetableCalendarMenuSemester(
                semesterID: configuration.semesterID,
                title: Self.semesterSeasonTitle(
                    semesterID: configuration.semesterID,
                    semesterStartDate: configuration.semesterStartDate,
                    calendar: calendar
                ),
                weeks: weeks,
                startDate: configuration.semesterStartDate,
                endDate: configuration.calendarEvents.first {
                    $0.academicCategory == .semesterEnd
                }?.endDate
            )
            stagesByAcademicYear[academicYear, default: []].append(.semester(semester))
        }

        var seenVacations = Set<String>()
        var resolvedCurrentVacationID: String?
        var currentVacationEndDate: Date?
        for configuration in sortedConfigurations {
            let academicYear = Self.academicYearTitle(semesterID: configuration.semesterID)
            for event in configuration.calendarEvents where event.isVacation {
                guard let category = event.academicCategory,
                      let startDate = event.startDate,
                      let target = Self.vacationTarget(
                        for: event,
                        timetable: timetable,
                        configurations: sortedConfigurations,
                        referenceDate: referenceDate,
                        calendar: calendar
                      ) else { continue }
                let identity = "\(academicYear)-\(category.rawValue)"
                guard seenVacations.insert(identity).inserted else { continue }

                if event.contains(referenceDay, calendar: calendar) {
                    resolvedCurrentVacationID = identity
                    currentVacationEndDate = event.endDate
                }

                stagesByAcademicYear[academicYear, default: []].append(
                    .vacation(
                        TimetableCalendarMenuVacation(
                            id: identity,
                            title: Self.vacationTitle(category: category),
                            page: target.page,
                            targetDate: target.date,
                            startDate: startDate,
                            weeks: Self.vacationWeeks(
                                for: event,
                                configurations: sortedConfigurations,
                                calendar: calendar
                            )
                        )
                    )
                )
            }
        }
        currentVacationID = resolvedCurrentVacationID

        if resolvedCurrentSemesterID != nil {
            defaultExpandedSemesterIDs = Set([resolvedCurrentSemesterID].compactMap { $0 })
            unavailableFutureConfigurationMessage = nil
        } else if resolvedCurrentVacationID != nil {
            let nextConfiguration = sortedConfigurations.first { configuration in
                configuration.semesterStartDate > (currentVacationEndDate ?? referenceDay)
            }
            defaultExpandedSemesterIDs = Set([nextConfiguration?.semesterID].compactMap { $0 })
            unavailableFutureConfigurationMessage = nextConfiguration == nil ? "暂无下学期配置" : nil
        } else {
            let nearestConfiguration = sortedConfigurations.first { $0.semesterStartDate >= referenceDay }
                ?? sortedConfigurations.last
            defaultExpandedSemesterIDs = Set([nearestConfiguration?.semesterID].compactMap { $0 })
            unavailableFutureConfigurationMessage = nil
        }

        academicYears = stagesByAcademicYear.map { academicYear, stages in
            TimetableCalendarMenuAcademicYear(
                academicYear: academicYear,
                stages: stages.sorted { $0.startDate > $1.startDate }
            )
        }.sorted { lhs, rhs in
            let lhsStartDate = lhs.stages.first?.startDate ?? .distantPast
            let rhsStartDate = rhs.stages.first?.startDate ?? .distantPast
            if lhsStartDate != rhsStartDate {
                return lhsStartDate > rhsStartDate
            }
            return lhs.academicYear > rhs.academicYear
        }
    }

    static func academicYearTitle(semesterID: String) -> String {
        let parts = semesterID.split(separator: "-")
        guard parts.count >= 2 else { return semesterID }
        return parts.prefix(2).joined(separator: "–")
    }

    static func semesterSeasonTitle(
        semesterID: String,
        semesterStartDate: Date?,
        calendar: Calendar = .current
    ) -> String {
        switch semesterID.split(separator: "-").last {
        case "1":
            return "秋季学期"
        case "2":
            return "春季学期"
        default:
            let month = semesterStartDate.map { calendar.component(.month, from: $0) } ?? 1
            return month >= 7 ? "秋季学期" : "春季学期"
        }
    }

    static func vacationTitle(
        category: SchoolCalendarEvent.AcademicCategory,
        language: AppLanguagePreference = .current
    ) -> String {
        switch category {
        case .winterBreak:
            return L10n.text("寒假", language: language)
        case .summerBreak:
            return L10n.text("暑假", language: language)
        case .publicHoliday, .importantDate, .semesterEnd:
            return L10n.text("假期", language: language)
        }
    }

    private static func vacationTarget(
        for event: SchoolCalendarEvent,
        timetable: AcademicYearTimetable,
        configurations: [SemesterRuntimeConfig],
        referenceDate: Date,
        calendar: Calendar
    ) -> (page: Int, date: Date)? {
        let referenceDay = calendar.startOfDay(for: referenceDate)
        if event.contains(referenceDay, calendar: calendar),
           let page = timetable.pageIndex(containing: referenceDay) {
            return (page, referenceDay)
        }

        guard let eventStart = event.startDate,
              let eventEnd = event.endDate else { return nil }
        let start = calendar.startOfDay(for: eventStart)
        let end = calendar.startOfDay(for: eventEnd)

        let targetDate: Date
        let targetTimetable: AcademicYearTimetable
        if start < timetable.endDate, end >= timetable.startDate {
            targetDate = max(start, timetable.startDate)
            targetTimetable = timetable
        } else {
            targetDate = start
            targetTimetable = AcademicYearTimetable(
                configurations: configurations,
                semanticEvents: configurations.flatMap(\.calendarEvents),
                referenceDate: targetDate,
                calendar: calendar
            )
        }
        guard let page = targetTimetable.pageIndex(containing: targetDate) else { return nil }
        return (page, targetDate)
    }

    private static func vacationWeeks(
        for event: SchoolCalendarEvent,
        configurations: [SemesterRuntimeConfig],
        calendar: Calendar
    ) -> [TimetableCalendarMenuVacationWeek] {
        guard let eventStart = event.startDate,
              let eventEnd = event.endDate else { return [] }
        let start = calendar.startOfDay(for: eventStart)
        let end = calendar.startOfDay(for: eventEnd)
        let weekday = calendar.component(.weekday, from: start)
        let daysSinceMonday = (weekday + 5) % 7
        guard var weekStart = calendar.date(byAdding: .day, value: -daysSinceMonday, to: start) else {
            return []
        }

        var weeks: [TimetableCalendarMenuVacationWeek] = []
        while weekStart <= end {
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            let clippedStart = max(weekStart, start)
            let clippedEnd = min(weekEnd, end)
            let targetTimetable = AcademicYearTimetable(
                configurations: configurations,
                semanticEvents: configurations.flatMap(\.calendarEvents),
                referenceDate: clippedStart,
                calendar: calendar
            )
            if let page = targetTimetable.pageIndex(containing: clippedStart) {
                weeks.append(
                    TimetableCalendarMenuVacationWeek(
                        page: page,
                        targetDate: clippedStart,
                        startDate: clippedStart,
                        endDate: clippedEnd
                    )
                )
            }
            guard let nextWeek = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
                break
            }
            weekStart = nextWeek
        }
        return weeks
    }
}

nonisolated struct TimetableCalendarMenuAcademicYear: Identifiable {
    let academicYear: String
    let stages: [TimetableCalendarMenuStage]

    var id: String { academicYear }

    var semesters: [TimetableCalendarMenuSemester] {
        stages.compactMap { stage in
            guard case let .semester(semester) = stage else { return nil }
            return semester
        }
    }
}

nonisolated enum TimetableCalendarMenuStage: Identifiable {
    case semester(TimetableCalendarMenuSemester)
    case vacation(TimetableCalendarMenuVacation)

    var id: String {
        switch self {
        case let .semester(semester):
            return "semester-\(semester.id)"
        case let .vacation(vacation):
            return "vacation-\(vacation.id)"
        }
    }

    var startDate: Date {
        switch self {
        case let .semester(semester):
            return semester.startDate
        case let .vacation(vacation):
            return vacation.startDate
        }
    }

    var semesterID: String? {
        guard case let .semester(semester) = self else { return nil }
        return semester.semesterID
    }
}

nonisolated struct TimetableCalendarMenuSemester: Identifiable {
    let semesterID: String
    let title: String
    let weeks: [TimetableCalendarMenuWeek]
    let startDate: Date
    let endDate: Date?

    var id: String { semesterID }
}

nonisolated struct TimetableCalendarMenuWeek: Identifiable {
    let page: Int
    let weekNumber: Int
    let targetDate: Date

    var id: String { "\(weekNumber)-\(targetDate.timeIntervalSinceReferenceDate)" }
}

nonisolated struct TimetableCalendarMenuVacation: Identifiable {
    let id: String
    let title: String
    let page: Int
    let targetDate: Date
    let startDate: Date
    let weeks: [TimetableCalendarMenuVacationWeek]
}

nonisolated struct TimetableCalendarMenuVacationWeek: Identifiable {
    let page: Int
    let targetDate: Date
    let startDate: Date
    let endDate: Date

    var id: String { "\(startDate.timeIntervalSinceReferenceDate)" }
}
