import Foundation

struct TimetableScheduleProjectionSnapshot {
    static let empty = TimetableScheduleProjectionSnapshot(
        signature: TimetableScheduleProjectionSignature(countdowns: [], exams: []),
        countdownsByDay: [:],
        examsByDay: [:]
    )

    let signature: TimetableScheduleProjectionSignature
    private let countdownsByDay: [TimetableScheduleProjectionDayKey: [TimetableCountdownProjection]]
    private let examsByDay: [TimetableScheduleProjectionDayKey: [TimetableExamProjection]]

    static func make(
        countdownEvents: [CustomScheduleEvent],
        exams: [ExamArrangement]
    ) -> TimetableScheduleProjectionSnapshot {
        let countdowns = countdownEvents
            .compactMap(\.timetableProjection)
            .sorted { lhs, rhs in
                if lhs.week != rhs.week { return lhs.week < rhs.week }
                if lhs.dayOfWeek != rhs.dayOfWeek { return lhs.dayOfWeek < rhs.dayOfWeek }
                if lhs.period != rhs.period { return lhs.period < rhs.period }
                return lhs.targetDate < rhs.targetDate
            }
        let exams = exams
            .compactMap(\.timetableProjection)
            .sorted { lhs, rhs in
                if lhs.week != rhs.week { return lhs.week < rhs.week }
                if lhs.dayOfWeek != rhs.dayOfWeek { return lhs.dayOfWeek < rhs.dayOfWeek }
                if lhs.period != rhs.period { return lhs.period < rhs.period }
                return lhs.startsAt < rhs.startsAt
            }

        return snapshot(countdowns: countdowns, exams: exams)
    }

    static func make(
        countdownEvents: [CustomScheduleEvent],
        exams: [ExamArrangement],
        calendarYear: CalendarYearTimetable,
        calendar: Calendar = .current
    ) -> TimetableScheduleProjectionSnapshot {
        let countdowns = countdownEvents.compactMap { event -> TimetableCountdownProjection? in
            guard let week = calendarYear.pageIndex(containing: event.startsAt) else { return nil }
            let weekday = calendar.component(.weekday, from: event.startsAt)
            let day = ((weekday + 5) % 7) + 1
            let effectiveEnd = event.endsAt.flatMap { $0 > event.startsAt ? $0 : nil }
                ?? event.startsAt.addingTimeInterval(45 * 60)
            let period = TimetablePeriodSchedule.period(containing: event.startsAt)?.period
                ?? TimetablePeriodSchedule.periodForFocus(containing: event.startsAt)?.period
                ?? 1
            let periodRange = TimetablePeriodSchedule.periodRange(
                overlapping: event.startsAt,
                endDate: effectiveEnd
            )
            return TimetableCountdownProjection(
                eventID: event.id,
                title: event.title,
                startsAt: event.startsAt,
                endsAt: effectiveEnd,
                week: week,
                dayOfWeek: day,
                startPeriod: periodRange?.lowerBound ?? period,
                endPeriod: periodRange?.upperBound ?? period
            )
        }
        .sorted { lhs, rhs in
            if lhs.week != rhs.week { return lhs.week < rhs.week }
            if lhs.dayOfWeek != rhs.dayOfWeek { return lhs.dayOfWeek < rhs.dayOfWeek }
            if lhs.period != rhs.period { return lhs.period < rhs.period }
            return lhs.targetDate < rhs.targetDate
        }

        let examProjections = exams.compactMap { exam -> TimetableExamProjection? in
            guard let startsAt = exam.startsAt,
                  let week = calendarYear.pageIndex(containing: startsAt) else { return nil }
            let weekday = calendar.component(.weekday, from: startsAt)
            let day = ((weekday + 5) % 7) + 1
            let period = TimetablePeriodSchedule.period(containing: startsAt)?.period
                ?? TimetablePeriodSchedule.periodForFocus(containing: startsAt)?.period
                ?? 1
            return TimetableExamProjection(
                examID: exam.id,
                name: exam.name,
                startsAt: startsAt,
                endsAt: exam.endsAt ?? startsAt,
                startText: exam.start,
                location: exam.location,
                week: week,
                dayOfWeek: day,
                period: period
            )
        }
        .sorted { lhs, rhs in
            if lhs.week != rhs.week { return lhs.week < rhs.week }
            if lhs.dayOfWeek != rhs.dayOfWeek { return lhs.dayOfWeek < rhs.dayOfWeek }
            if lhs.period != rhs.period { return lhs.period < rhs.period }
            return lhs.startsAt < rhs.startsAt
        }

        return snapshot(countdowns: countdowns, exams: examProjections)
    }

    private static func snapshot(
        countdowns: [TimetableCountdownProjection],
        exams: [TimetableExamProjection]
    ) -> TimetableScheduleProjectionSnapshot {
        TimetableScheduleProjectionSnapshot(
            signature: TimetableScheduleProjectionSignature(countdowns: countdowns, exams: exams),
            countdownsByDay: Dictionary(grouping: countdowns) {
                TimetableScheduleProjectionDayKey(week: $0.week, day: $0.dayOfWeek)
            },
            examsByDay: Dictionary(grouping: exams) {
                TimetableScheduleProjectionDayKey(week: $0.week, day: $0.dayOfWeek)
            }
        )
    }

    func countdowns(week: Int, day: Int) -> [TimetableCountdownProjection] {
        countdownsByDay[TimetableScheduleProjectionDayKey(week: week, day: day)] ?? []
    }

    func exams(week: Int, day: Int) -> [TimetableExamProjection] {
        examsByDay[TimetableScheduleProjectionDayKey(week: week, day: day)] ?? []
    }
}

struct TimetableScheduleProjectionSignature: Hashable {
    let countdowns: [TimetableCountdownProjection]
    let exams: [TimetableExamProjection]
}

struct TimetableScheduleProjectionDayKey: Hashable {
    let week: Int
    let day: Int
}
