import Foundation

nonisolated struct TimetableCalendarMenuModel {
    let academicYears: [TimetableCalendarMenuAcademicYear]
    let currentSemesterID: String?

    init(
        timetable: CalendarYearTimetable,
        configurations: [SemesterRuntimeConfig],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) {
        struct SemesterAccumulator {
            let semesterID: String
            let academicYear: String
            let title: String
            let startDate: Date
            var weeks: [TimetableCalendarMenuWeek]
        }

        let referencePhase = timetable.phase(for: referenceDate)
        let resolvedCurrentSemesterID: String?
        if case let .teaching(semesterID, _) = referencePhase {
            resolvedCurrentSemesterID = semesterID
        } else {
            resolvedCurrentSemesterID = configurations.first(where: \.isActive)?.semesterID
        }
        currentSemesterID = resolvedCurrentSemesterID

        var semesterOrder: [String] = []
        var semesterAccumulators: [String: SemesterAccumulator] = [:]

        for (index, week) in timetable.weeks.enumerated() {
            guard case let .teaching(semesterID, weekNumber) = week.phase else { continue }
            let configuration = timetable.configuration(semesterID: semesterID)

            if semesterAccumulators[semesterID] == nil {
                semesterOrder.append(semesterID)
                semesterAccumulators[semesterID] = SemesterAccumulator(
                    semesterID: semesterID,
                    academicYear: Self.academicYearTitle(semesterID: semesterID),
                    title: Self.semesterSeasonTitle(
                        semesterID: semesterID,
                        semesterStartDate: configuration?.semesterStartDate,
                        calendar: calendar
                    ),
                    startDate: week.referenceDate,
                    weeks: []
                )
            }
            semesterAccumulators[semesterID]?.weeks.append(
                TimetableCalendarMenuWeek(page: index + 1, weekNumber: weekNumber)
            )
        }

        var stagesByAcademicYear: [String: [TimetableCalendarMenuStage]] = [:]
        for semesterID in semesterOrder {
            guard let accumulator = semesterAccumulators[semesterID] else { continue }
            let semester = TimetableCalendarMenuSemester(
                semesterID: accumulator.semesterID,
                title: accumulator.title,
                weeks: accumulator.weeks,
                startDate: accumulator.startDate
            )
            stagesByAcademicYear[accumulator.academicYear, default: []].append(.semester(semester))
        }

        var seenVacations = Set<String>()
        for configuration in configurations.sorted(by: { $0.semesterStartDate < $1.semesterStartDate }) {
            let academicYear = Self.academicYearTitle(semesterID: configuration.semesterID)
            for event in configuration.calendarEvents where event.isVacation {
                guard let category = event.academicCategory,
                      let startDate = event.startDate,
                      let targetPage = Self.vacationTargetPage(
                        for: event,
                        timetable: timetable,
                        referenceDate: referenceDate,
                        calendar: calendar
                      ) else { continue }
                let identity = "\(academicYear)-\(category.rawValue)"
                guard seenVacations.insert(identity).inserted else { continue }

                stagesByAcademicYear[academicYear, default: []].append(
                    .vacation(
                        TimetableCalendarMenuVacation(
                            id: identity,
                            title: Self.vacationTitle(category: category),
                            page: targetPage,
                            startDate: startDate
                        )
                    )
                )
            }
        }

        academicYears = stagesByAcademicYear.map { academicYear, stages in
            TimetableCalendarMenuAcademicYear(
                academicYear: academicYear,
                stages: stages.sorted { lhs, rhs in
                    let lhsIsCurrent = lhs.semesterID == resolvedCurrentSemesterID
                    let rhsIsCurrent = rhs.semesterID == resolvedCurrentSemesterID
                    if lhsIsCurrent != rhsIsCurrent { return lhsIsCurrent }
                    return lhs.startDate < rhs.startDate
                }
            )
        }
        .sorted { lhs, rhs in
            let lhsContainsCurrent = lhs.stages.contains { $0.semesterID == resolvedCurrentSemesterID }
            let rhsContainsCurrent = rhs.stages.contains { $0.semesterID == resolvedCurrentSemesterID }
            if lhsContainsCurrent != rhsContainsCurrent { return lhsContainsCurrent }
            let lhsStart = lhs.stages.first?.startDate ?? .distantFuture
            let rhsStart = rhs.stages.first?.startDate ?? .distantFuture
            if lhsStart != rhsStart { return lhsStart < rhsStart }
            return lhs.academicYear < rhs.academicYear
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

    static func vacationTitle(category: SchoolCalendarEvent.AcademicCategory) -> String {
        switch category {
        case .winterBreak:
            return "寒假"
        case .summerBreak:
            return "暑假"
        case .publicHoliday, .importantDate, .semesterEnd:
            return "假期"
        }
    }

    private static func vacationTargetPage(
        for event: SchoolCalendarEvent,
        timetable: CalendarYearTimetable,
        referenceDate: Date,
        calendar: Calendar
    ) -> Int? {
        let referenceDay = calendar.startOfDay(for: referenceDate)
        if event.contains(referenceDay, calendar: calendar),
           let page = timetable.pageIndex(containing: referenceDay) {
            return page
        }

        guard let eventStart = event.startDate,
              let eventEnd = event.endDate else { return nil }
        let start = calendar.startOfDay(for: eventStart)
        let end = calendar.startOfDay(for: eventEnd)

        return timetable.weeks.enumerated().first { _, week in
            let weekEnd = week.weekEndDate(calendar: calendar)
            return week.weekStartDate <= end && weekEnd >= start
        }.map { $0.offset + 1 }
    }
}

nonisolated struct TimetableCalendarMenuAcademicYear: Identifiable {
    let academicYear: String
    let stages: [TimetableCalendarMenuStage]

    var id: String { academicYear }
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

    var id: String { semesterID }
}

nonisolated struct TimetableCalendarMenuWeek: Identifiable {
    let page: Int
    let weekNumber: Int

    var id: Int { page }
}

nonisolated struct TimetableCalendarMenuVacation: Identifiable {
    let id: String
    let title: String
    let page: Int
    let startDate: Date
}
