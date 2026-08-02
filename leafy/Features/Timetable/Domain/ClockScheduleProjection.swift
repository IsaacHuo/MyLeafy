import Foundation

/// The half of the day in which a clock-schedule fragment is rendered.
nonisolated enum ClockScheduleDayPart: String, CaseIterable, Hashable, Sendable {
    case am
    case pm

    var title: String {
        switch self {
        case .am:
            return "上午"
        case .pm:
            return "下午"
        }
    }
}

/// The three local sources that are intentionally visible in the clock schedule.
/// Exam arrangements are deliberately not represented by this type.
nonisolated enum ClockScheduleSource: String, Hashable, Sendable {
    case course
    case reminder
    case customSchedule

    var title: String {
        switch self {
        case .course:
            return "课程"
        case .reminder:
            return "课表日程"
        case .customSchedule:
            return "自定日程"
        }
    }
}

/// A value-only fragment rendered by the clock schedule.
///
/// A source can produce more than one fragment when it crosses noon or a
/// natural-day boundary. `sourceID` remains the durable source identity while
/// `id` identifies the deterministic fragment used by SwiftUI.
nonisolated struct ClockScheduleEvent: Identifiable, Hashable, Sendable {
    let id: String
    let source: ClockScheduleSource
    let sourceID: String
    let title: String
    /// The source interval used by the detail surface. Fragment dates below
    /// may be clipped to one day or one half-day for dial geometry.
    let sourceStartsAt: Date
    let sourceEndsAt: Date?
    let startsAt: Date
    let endsAt: Date?
    let location: String?
    let note: String?
    let period: Int?
    let dayPart: ClockScheduleDayPart
    let lane: Int
    let laneCount: Int

    var isPoint: Bool {
        endsAt == nil
    }

    var startText: String {
        Self.timeString(sourceStartsAt)
    }

    var endText: String? {
        sourceEndsAt.map(Self.timeString)
    }

    var timeText: String {
        guard let endText else {
            return startText
        }
        return "\(startText)–\(endText)"
    }

    private static func timeString(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return String(
            format: "%02d:%02d",
            calendar.component(.hour, from: date),
            calendar.component(.minute, from: date)
        )
    }
}

/// Pure projection input/output for one natural day. It contains no
/// `ExamArrangement` and no SwiftData model references.
nonisolated struct ClockScheduleDayProjection: Hashable, Sendable {
    let date: Date
    let events: [ClockScheduleEvent]

    var isEmpty: Bool {
        events.isEmpty
    }

    var earliestEvent: ClockScheduleEvent? {
        events.first
    }

    var eventsForAM: [ClockScheduleEvent] {
        events.filter { $0.dayPart == .am }
    }

    var eventsForPM: [ClockScheduleEvent] {
        events.filter { $0.dayPart == .pm }
    }

    func events(for dayPart: ClockScheduleDayPart) -> [ClockScheduleEvent] {
        events.filter { $0.dayPart == dayPart }
    }
}

enum ClockScheduleProjection {
    /// Projects all supported sources for `date` into deterministic timeline
    /// fragments. Course occurrences are filtered by the active semester and
    /// weekday; reminders use their resolved dates; custom events can fall on
    /// any date. Exam arrangements are intentionally not accepted here.
    static func make(
        date: Date,
        courses: [Course],
        reminders: [TimetableCellReminder],
        customEvents: [CustomScheduleEvent],
        calendar: Calendar = .current
    ) -> ClockScheduleDayProjection {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 60 * 60)
        var rawFragments: [RawFragment] = []

        if let weekAndDay = semesterWeekAndDay(on: dayStart, calendar: calendar) {
            for course in courses where course.dayOfWeek == weekAndDay.day && course.weeks.contains(weekAndDay.week) {
                rawFragments.append(contentsOf: courseFragments(
                    course,
                    week: weekAndDay.week,
                    dayStart: dayStart,
                    dayEnd: dayEnd,
                    calendar: calendar
                ))
            }

            for reminder in reminders {
                guard let startsAt = reminder.resolvedStartDate else { continue }
                let endsAt = reminder.resolvedEndDate
                rawFragments.append(contentsOf: intervalFragments(
                    source: .reminder,
                    sourceID: reminder.id.uuidString,
                    title: reminder.title,
                    startsAt: startsAt,
                    endsAt: endsAt,
                    location: reminder.locationText,
                    note: reminder.noteText,
                    period: reminder.displayStartPeriod,
                    dayStart: dayStart,
                    dayEnd: dayEnd,
                    calendar: calendar,
                    fragmentPrefix: "reminder-\(reminder.id.uuidString)"
                ))
            }
        } else {
            // Reminders may still carry an explicit resolved date outside the
            // active semester. They remain visible as local date entries.
            for reminder in reminders {
                guard let startsAt = reminder.resolvedStartDate else { continue }
                rawFragments.append(contentsOf: intervalFragments(
                    source: .reminder,
                    sourceID: reminder.id.uuidString,
                    title: reminder.title,
                    startsAt: startsAt,
                    endsAt: reminder.resolvedEndDate,
                    location: reminder.locationText,
                    note: reminder.noteText,
                    period: reminder.displayStartPeriod,
                    dayStart: dayStart,
                    dayEnd: dayEnd,
                    calendar: calendar,
                    fragmentPrefix: "reminder-\(reminder.id.uuidString)"
                ))
            }
        }

        for event in customEvents {
            rawFragments.append(contentsOf: intervalFragments(
                source: .customSchedule,
                sourceID: event.id,
                title: event.title,
                startsAt: event.startsAt,
                endsAt: event.endsAt,
                location: event.locationText,
                note: event.noteText,
                period: nil,
                dayStart: dayStart,
                dayEnd: dayEnd,
                calendar: calendar,
                fragmentPrefix: "custom-\(event.id)"
            ))
        }

        return ClockScheduleDayProjection(
            date: dayStart,
            events: assignLanes(rawFragments)
        )
    }

    static func events(
        on date: Date,
        courses: [Course],
        reminders: [TimetableCellReminder],
        customEvents: [CustomScheduleEvent],
        calendar: Calendar = .current
    ) -> [ClockScheduleEvent] {
        make(
            date: date,
            courses: courses,
            reminders: reminders,
            customEvents: customEvents,
            calendar: calendar
        ).events
    }

    private struct RawFragment {
        let id: String
        let source: ClockScheduleSource
        let sourceID: String
        let title: String
        let sourceStartsAt: Date
        let sourceEndsAt: Date?
        let startsAt: Date
        let endsAt: Date?
        let location: String?
        let note: String?
        let period: Int?
        let dayPart: ClockScheduleDayPart
    }

    private static func courseFragments(
        _ course: Course,
        week: Int,
        dayStart: Date,
        dayEnd: Date,
        calendar: Calendar
    ) -> [RawFragment] {
        let periods = Array(Set(course.duration)).sorted()
        return periods.flatMap { period -> [RawFragment] in
            guard let slot = TimetablePeriodSchedule.slot(for: period),
                  let startsAt = calendar.date(
                      bySettingHour: slot.startHour,
                      minute: slot.startMinute,
                      second: 0,
                      of: dayStart
                  ),
                  let endsAt = calendar.date(
                      bySettingHour: slot.endHour,
                      minute: slot.endMinute,
                      second: 0,
                      of: dayStart
                  )
            else {
                return []
            }

            let fragments = splitInterval(
                startsAt: startsAt,
                endsAt: endsAt,
                dayStart: dayStart,
                dayEnd: dayEnd,
                calendar: calendar
            )
            return fragments.map { fragment in
                RawFragment(
                    id: "course-\(course.id.uuidString)-week-\(week)-period-\(period)-\(fragment.suffix)",
                    source: .course,
                    sourceID: course.id.uuidString,
                    title: course.courseName,
                    sourceStartsAt: startsAt,
                    sourceEndsAt: endsAt,
                    startsAt: fragment.startsAt,
                    endsAt: fragment.endsAt,
                    location: course.locationTextForShare.nilIfEmpty,
                    note: nil,
                    period: period,
                    dayPart: fragment.dayPart
                )
            }
        }
    }

    private static func intervalFragments(
        source: ClockScheduleSource,
        sourceID: String,
        title: String,
        startsAt: Date,
        endsAt: Date?,
        location: String?,
        note: String?,
        period: Int?,
        dayStart: Date,
        dayEnd: Date,
        calendar: Calendar,
        fragmentPrefix: String
    ) -> [RawFragment] {
        let pieces = splitInterval(
            startsAt: startsAt,
            endsAt: endsAt,
            dayStart: dayStart,
            dayEnd: dayEnd,
            calendar: calendar
        )
        return pieces.map { piece in
            RawFragment(
                id: "\(fragmentPrefix)-\(piece.suffix)",
                source: source,
                sourceID: sourceID,
                title: title,
                sourceStartsAt: startsAt,
                sourceEndsAt: endsAt,
                startsAt: piece.startsAt,
                endsAt: piece.endsAt,
                location: location.nilIfEmpty,
                note: note.nilIfEmpty,
                period: period,
                dayPart: piece.dayPart
            )
        }
    }

    private struct SplitPiece {
        let startsAt: Date
        let endsAt: Date?
        let dayPart: ClockScheduleDayPart
        let suffix: String
    }

    private static func splitInterval(
        startsAt: Date,
        endsAt: Date?,
        dayStart: Date,
        dayEnd: Date,
        calendar: Calendar
    ) -> [SplitPiece] {
        guard startsAt < dayEnd else { return [] }

        if endsAt == nil {
            guard startsAt >= dayStart else { return [] }
            return [SplitPiece(
                startsAt: startsAt,
                endsAt: nil,
                dayPart: dayPart(for: startsAt, dayStart: dayStart, calendar: calendar),
                suffix: "point-\(minuteKey(for: startsAt, calendar: calendar))"
            )]
        }

        guard let endsAt, endsAt > startsAt else {
            guard startsAt >= dayStart else { return [] }
            return [SplitPiece(
                startsAt: startsAt,
                endsAt: nil,
                dayPart: dayPart(for: startsAt, dayStart: dayStart, calendar: calendar),
                suffix: "point-\(minuteKey(for: startsAt, calendar: calendar))"
            )]
        }

        let clippedStart = max(startsAt, dayStart)
        let clippedEnd = min(endsAt, dayEnd)
        guard clippedEnd > clippedStart else { return [] }

        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: dayStart) ?? dayStart.addingTimeInterval(12 * 60 * 60)
        if clippedStart < noon, clippedEnd > noon {
            return [
                SplitPiece(
                    startsAt: clippedStart,
                    endsAt: noon,
                    dayPart: .am,
                    suffix: "am-\(minuteKey(for: clippedStart, calendar: calendar))"
                ),
                SplitPiece(
                    startsAt: noon,
                    endsAt: clippedEnd,
                    dayPart: .pm,
                    suffix: "pm-\(minuteKey(for: clippedEnd, calendar: calendar))"
                )
            ]
        }

        return [SplitPiece(
            startsAt: clippedStart,
            endsAt: clippedEnd,
            dayPart: clippedStart < noon ? .am : .pm,
            suffix: "segment-\(minuteKey(for: clippedStart, calendar: calendar))"
        )]
    }

    private static func assignLanes(_ rawFragments: [RawFragment]) -> [ClockScheduleEvent] {
        let sorted = rawFragments.sorted { lhs, rhs in
            if lhs.startsAt != rhs.startsAt { return lhs.startsAt < rhs.startsAt }
            if (lhs.endsAt ?? lhs.startsAt) != (rhs.endsAt ?? rhs.startsAt) {
                return (lhs.endsAt ?? lhs.startsAt) < (rhs.endsAt ?? rhs.startsAt)
            }
            if lhs.source.rawValue != rhs.source.rawValue {
                return lhs.source.rawValue < rhs.source.rawValue
            }
            if lhs.sourceID != rhs.sourceID { return lhs.sourceID < rhs.sourceID }
            return lhs.id < rhs.id
        }

        var laneEndsByPart: [ClockScheduleDayPart: [Date]] = [:]
        var assignments: [(RawFragment, Int)] = []
        for fragment in sorted {
            var laneEnds = laneEndsByPart[fragment.dayPart] ?? []
            let visualEnd = fragment.endsAt ?? fragment.startsAt.addingTimeInterval(1)
            let lane = laneEnds.firstIndex(where: { $0 <= fragment.startsAt }) ?? laneEnds.count
            if lane == laneEnds.count {
                laneEnds.append(visualEnd)
            } else {
                laneEnds[lane] = visualEnd
            }
            laneEndsByPart[fragment.dayPart] = laneEnds
            assignments.append((fragment, lane))
        }

        let laneCounts = Dictionary(uniqueKeysWithValues: laneEndsByPart.map { ($0.key, $0.value.count) })
        return assignments.map { fragment, lane in
            ClockScheduleEvent(
                id: fragment.id,
                source: fragment.source,
                sourceID: fragment.sourceID,
                title: fragment.title,
                sourceStartsAt: fragment.sourceStartsAt,
                sourceEndsAt: fragment.sourceEndsAt,
                startsAt: fragment.startsAt,
                endsAt: fragment.endsAt,
                location: fragment.location,
                note: fragment.note,
                period: fragment.period,
                dayPart: fragment.dayPart,
                lane: lane,
                laneCount: laneCounts[fragment.dayPart] ?? 1
            )
        }
    }

    private static func semesterWeekAndDay(on date: Date, calendar: Calendar) -> (week: Int, day: Int)? {
        let semesterStart = calendar.startOfDay(for: SemesterConfig.startOfSemesterDate)
        let dayStart = calendar.startOfDay(for: date)
        let dayOffset = calendar.dateComponents([.day], from: semesterStart, to: dayStart).day ?? 0
        guard dayOffset >= 0, dayOffset < SemesterConfig.supportedWeeks * 7 else {
            return nil
        }
        return (dayOffset / 7 + 1, dayOffset % 7 + 1)
    }

    private static func dayPart(for date: Date, dayStart: Date, calendar: Calendar) -> ClockScheduleDayPart {
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: dayStart) ?? dayStart.addingTimeInterval(12 * 60 * 60)
        return date < noon ? .am : .pm
    }

    private static func minuteKey(for date: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return String(format: "%02d%02d", hour, minute)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Optional where Wrapped == String {
    var nilIfEmpty: String? {
        flatMap { $0.nilIfEmpty }
    }
}
