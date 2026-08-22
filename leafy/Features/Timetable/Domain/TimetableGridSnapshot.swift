import Foundation
import os

nonisolated enum TimetableDisplayMode: Equatable, Sendable {
    case week
    case threeDay
}

@MainActor
struct TimetableCourseWeekProjection: Hashable {
    let displayWeeks: [Int]
    let semesterWeekByDisplayWeek: [Int: Int]
}

struct TimetableCellReminderProjection: Hashable {
    let displayWeek: Int
    let dayOfWeek: Int
}

struct TimetableRenderInput {
    let courses: [Course]
    let notes: [CourseNote]
    let occurrenceNotes: [CourseOccurrenceNote]
    let cellReminders: [TimetableCellReminder]
    let courseWeekProjections: [UUID: TimetableCourseWeekProjection]
    let cellReminderProjections: [UUID: TimetableCellReminderProjection]
    let signature: TimetableGridInputSignature

    init(
        courses: [Course],
        notes: [CourseNote],
        occurrenceNotes: [CourseOccurrenceNote],
        cellReminders: [TimetableCellReminder],
        hidesWeekends: Bool,
        courseWeekProjections: [UUID: TimetableCourseWeekProjection] = [:],
        cellReminderProjections: [UUID: TimetableCellReminderProjection] = [:]
    ) {
        self.courses = courses
        self.notes = notes
        self.occurrenceNotes = occurrenceNotes
        self.cellReminders = cellReminders
        self.courseWeekProjections = courseWeekProjections
        self.cellReminderProjections = cellReminderProjections
        signature = TimetableGridInputSignature(
            courses: courses,
            notes: notes,
            occurrenceNotes: occurrenceNotes,
            cellReminders: cellReminders,
            hidesWeekends: hidesWeekends,
            courseWeekProjections: courseWeekProjections,
            cellReminderProjections: cellReminderProjections
        )
    }
}

@MainActor
struct TimetableGridInputSignature: Equatable, Hashable {
    let hidesWeekends: Bool
    let courseSignatures: [CourseSignature]
    let noteSignatures: [NoteSignature]
    let occurrenceNoteSignatures: [OccurrenceNoteSignature]
    let cellReminderSignatures: [CellReminderSignature]

    init(
        courses: [Course],
        notes: [CourseNote],
        occurrenceNotes: [CourseOccurrenceNote],
        cellReminders: [TimetableCellReminder],
        hidesWeekends: Bool,
        courseWeekProjections: [UUID: TimetableCourseWeekProjection] = [:],
        cellReminderProjections: [UUID: TimetableCellReminderProjection] = [:]
    ) {
        self.hidesWeekends = hidesWeekends
        courseSignatures = courses
            .map { CourseSignature(course: $0, projection: courseWeekProjections[$0.id]) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        noteSignatures = notes
            .map(NoteSignature.init(note:))
            .sorted { $0.id.uuidString < $1.id.uuidString }
        occurrenceNoteSignatures = occurrenceNotes
            .map(OccurrenceNoteSignature.init(note:))
            .sorted { $0.id.uuidString < $1.id.uuidString }
        cellReminderSignatures = cellReminders
            .map { CellReminderSignature(reminder: $0, projection: cellReminderProjections[$0.id]) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    struct CourseSignature: Equatable, Hashable {
        let id: UUID
        let name: String
        let teacher: String
        let location: String
        let room: String
        let sourceSemesterID: String
        let dayOfWeek: Int
        let weeks: [Int]
        let duration: [Int]

        init(course: Course, projection: TimetableCourseWeekProjection?) {
            id = course.id
            name = course.courseName
            teacher = course.teacher
            location = course.location
            room = course.room
            sourceSemesterID = course.sourceSemesterID
            dayOfWeek = course.dayOfWeek
            weeks = (projection?.displayWeeks ?? course.weeks).sorted()
            duration = course.duration.sorted()
        }
    }

    struct NoteSignature: Equatable, Hashable {
        let id: UUID
        let courseKey: String
        let text: String
        let updatedAt: Date

        init(note: CourseNote) {
            id = note.id
            courseKey = note.courseKey
            text = note.text
            updatedAt = note.updatedAt
        }
    }

    struct OccurrenceNoteSignature: Equatable, Hashable {
        let id: UUID
        let courseKey: String
        let occurrenceKey: String
        let week: Int
        let dayOfWeek: Int
        let text: String
        let updatedAt: Date

        init(note: CourseOccurrenceNote) {
            id = note.id
            courseKey = note.courseKey
            occurrenceKey = note.occurrenceKey
            week = note.week
            dayOfWeek = note.dayOfWeek
            text = note.text
            updatedAt = note.updatedAt
        }
    }

    struct CellReminderSignature: Equatable, Hashable {
        let id: UUID
        let cellKey: String
        let title: String
        let location: String
        let note: String
        let endPeriod: Int
        let startsAt: Date?
        let endsAt: Date?
        let minutesBefore: Int
        let updatedAt: Date
        let displayWeek: Int
        let displayDay: Int

        init(reminder: TimetableCellReminder, projection: TimetableCellReminderProjection?) {
            id = reminder.id
            cellKey = reminder.cellKey
            title = reminder.title
            location = reminder.locationText
            note = reminder.noteText
            endPeriod = reminder.displayEndPeriod
            startsAt = reminder.startsAt
            endsAt = reminder.endsAt
            minutesBefore = reminder.minutesBefore
            updatedAt = reminder.updatedAt
            displayWeek = projection?.displayWeek ?? reminder.week
            displayDay = projection?.dayOfWeek ?? reminder.dayOfWeek
        }
    }
}

struct TimetableCourseRenderValue: Identifiable, Hashable {
    let id: UUID
    let courseName: String
    let displayCourseName: String
    let teacher: String
    let classInfo: String
    let room: String
    let location: String
    let locationText: String
    let timetableCardLocationText: String
    let sourceSemesterID: String
    let dayOfWeek: Int
    let weeks: [Int]
    let duration: [Int]
    let stableCourseKey: String
    let semesterWeekByDisplayWeek: [Int: Int]

    @MainActor
    init(course: Course, projection: TimetableCourseWeekProjection? = nil) {
        id = course.id
        courseName = course.courseName
        displayCourseName = course.displayCourseName
        teacher = course.teacher
        classInfo = course.classInfo
        room = course.room
        location = course.location
        locationText = course.locationText
        timetableCardLocationText = course.timetableCardLocationText
        sourceSemesterID = course.sourceSemesterID
        dayOfWeek = course.dayOfWeek
        weeks = projection?.displayWeeks ?? course.weeks
        duration = course.duration
        stableCourseKey = course.stableCourseKey
        semesterWeekByDisplayWeek = projection?.semesterWeekByDisplayWeek ?? Dictionary(
            uniqueKeysWithValues: course.weeks.map { ($0, $0) }
        )
    }

    func semesterWeek(for displayWeek: Int) -> Int? {
        semesterWeekByDisplayWeek[displayWeek]
    }

    func occurrenceKey(week displayWeek: Int) -> String {
        let semesterWeek = semesterWeek(for: displayWeek) ?? displayWeek
        return CourseOccurrenceNote.occurrenceKey(
            courseKey: stableCourseKey,
            semesterID: sourceSemesterID,
            week: semesterWeek
        )
    }

}

struct TimetableCellReminderRenderValue: Identifiable, Hashable {
    let id: UUID
    let cellKey: String
    let week: Int
    let dayOfWeek: Int
    let period: Int
    let title: String
    let locationText: String
    let noteText: String
    let startsAt: Date?
    let endsAt: Date?
    let minutesBefore: Int
    let updatedAt: Date
    let displayStartPeriod: Int
    let displayEndPeriod: Int
    let resolvedStartDate: Date?
    let resolvedEndDate: Date?

    var displayPeriodRange: ClosedRange<Int> {
        displayStartPeriod...displayEndPeriod
    }

    @MainActor
    init(reminder: TimetableCellReminder, projection: TimetableCellReminderProjection? = nil) {
        id = reminder.id
        cellKey = reminder.cellKey
        week = projection?.displayWeek ?? reminder.week
        dayOfWeek = projection?.dayOfWeek ?? reminder.dayOfWeek
        period = reminder.period
        title = reminder.title
        locationText = reminder.locationText
        noteText = reminder.noteText
        startsAt = reminder.startsAt
        endsAt = reminder.endsAt
        minutesBefore = reminder.minutesBefore
        updatedAt = reminder.updatedAt
        displayStartPeriod = reminder.displayStartPeriod
        displayEndPeriod = reminder.displayEndPeriod
        resolvedStartDate = reminder.resolvedStartDate
        resolvedEndDate = reminder.resolvedEndDate
    }
}

struct TimetableGridCourseLayout: Identifiable {
    let course: TimetableCourseRenderValue
    let laneIndex: Int
    let laneCount: Int

    var id: UUID { course.id }
}

enum TimetableGridCourseLayoutBuilder {
    static func layouts(for courses: [TimetableCourseRenderValue]) -> [TimetableGridCourseLayout] {
        guard !courses.isEmpty else { return [] }

        var result: [TimetableGridCourseLayout] = []
        var cluster: [TimetableCourseRenderValue] = []
        var clusterMaxEnd = 0

        func flushCluster() {
            guard !cluster.isEmpty else { return }
            result.append(contentsOf: layoutsForCluster(cluster))
            cluster.removeAll()
            clusterMaxEnd = 0
        }

        for course in courses {
            let start = course.duration.min() ?? 0
            let end = course.duration.max() ?? 0

            if cluster.isEmpty {
                cluster = [course]
                clusterMaxEnd = end
            } else if start <= clusterMaxEnd {
                cluster.append(course)
                clusterMaxEnd = max(clusterMaxEnd, end)
            } else {
                flushCluster()
                cluster = [course]
                clusterMaxEnd = end
            }
        }

        flushCluster()
        return result
    }

    private static func layoutsForCluster(
        _ cluster: [TimetableCourseRenderValue]
    ) -> [TimetableGridCourseLayout] {
        var laneEndings: [Int] = []
        var placements: [(TimetableCourseRenderValue, Int)] = []

        for course in cluster {
            let start = course.duration.min() ?? 0
            let end = course.duration.max() ?? 0

            if let reusableLane = laneEndings.firstIndex(where: { $0 < start }) {
                laneEndings[reusableLane] = end
                placements.append((course, reusableLane))
            } else {
                laneEndings.append(end)
                placements.append((course, laneEndings.count - 1))
            }
        }

        return placements.map { course, laneIndex in
            TimetableGridCourseLayout(
                course: course,
                laneIndex: laneIndex,
                laneCount: max(1, laneEndings.count)
            )
        }
    }
}

@MainActor
struct TimetableGridSnapshot {
    let signature: TimetableGridInputSignature
    let totalWeeks: Int
    let visibleDays: [Int]
    let courseNoteKeys: Set<String>
    let occurrenceNoteKeys: Set<String>

    private let layoutsByDay: [TimetableGridDayKey: [TimetableGridCourseLayout]]
    private let occupiedPeriodsByDay: [TimetableGridDayKey: Set<Int>]
    private let latestCellReminderByKey: [String: TimetableCellReminderRenderValue]
    private let cellRemindersByDay: [TimetableGridDayKey: [TimetableCellReminderRenderValue]]
    private let courseNotesByKey: [String: String]
    private let occurrenceNotesByKey: [String: String]

    static func make(
        courses: [Course],
        notes: [CourseNote],
        occurrenceNotes: [CourseOccurrenceNote],
        cellReminders: [TimetableCellReminder],
        hidesWeekends: Bool,
        totalWeeks: Int,
        courseWeekProjections: [UUID: TimetableCourseWeekProjection] = [:],
        cellReminderProjections: [UUID: TimetableCellReminderProjection] = [:],
        signature providedSignature: TimetableGridInputSignature? = nil
    ) -> TimetableGridSnapshot {
        let state = LeafyPerformanceSignposter.timetable.beginInterval("grid-snapshot")
        defer { LeafyPerformanceSignposter.timetable.endInterval("grid-snapshot", state) }

        let signature = providedSignature ?? TimetableGridInputSignature(
            courses: courses,
            notes: notes,
            occurrenceNotes: occurrenceNotes,
            cellReminders: cellReminders,
            hidesWeekends: hidesWeekends,
            courseWeekProjections: courseWeekProjections,
            cellReminderProjections: cellReminderProjections
        )
        let visibleDays = hidesWeekends ? Array(1...5) : Array(1...7)
        let courseNotesByKey = TimetableNoteResolver.courseNotesByKey(notes)
        let occurrenceNotesByKey = TimetableNoteResolver.occurrenceNotesByKey(occurrenceNotes)
        let courseNoteKeys = Set(courseNotesByKey.keys)
        let occurrenceNoteKeys = Set(occurrenceNotesByKey.keys)
        let courseValues = courses.map {
            TimetableCourseRenderValue(course: $0, projection: courseWeekProjections[$0.id])
        }
        let reminderValues = cellReminders.map {
            TimetableCellReminderRenderValue(reminder: $0, projection: cellReminderProjections[$0.id])
        }

        var coursesByDay: [TimetableGridDayKey: [TimetableCourseRenderValue]] = [:]
        for course in courseValues where (1...7).contains(course.dayOfWeek) {
            for week in course.weeks where (1...totalWeeks).contains(week) {
                coursesByDay[TimetableGridDayKey(week: week, day: course.dayOfWeek), default: []].append(course)
            }
        }
        var layoutsByDay: [TimetableGridDayKey: [TimetableGridCourseLayout]] = [:]
        var occupiedPeriodsByDay: [TimetableGridDayKey: Set<Int>] = [:]

        for (key, courses) in coursesByDay {
            let sortedCourses = courses.sorted { lhs, rhs in
                let lhsStart = lhs.duration.min() ?? Int.max
                let rhsStart = rhs.duration.min() ?? Int.max
                if lhsStart != rhsStart {
                    return lhsStart < rhsStart
                }
                return lhs.displayCourseName.localizedCompare(rhs.displayCourseName) == .orderedAscending
            }
            let layouts = TimetableGridCourseLayoutBuilder.layouts(for: sortedCourses)
            layoutsByDay[key] = layouts
            occupiedPeriodsByDay[key] = Set(layouts.flatMap(\.course.duration))
        }

        let latestCellReminderByKey = Dictionary(
            reminderValues
                .sorted { $0.updatedAt > $1.updatedAt }
                .map {
                    (
                        TimetableCellReminder.cellKey(
                            week: $0.week,
                            dayOfWeek: $0.dayOfWeek,
                            period: $0.period
                        ),
                        $0
                    )
                },
            uniquingKeysWith: { first, _ in first }
        )
        let cellRemindersByDay = Dictionary(
            grouping: latestCellReminderByKey.values,
            by: { TimetableGridDayKey(week: $0.week, day: $0.dayOfWeek) }
        )
        .mapValues { reminders in
            reminders.sorted { lhs, rhs in
                if lhs.displayStartPeriod != rhs.displayStartPeriod {
                    return lhs.displayStartPeriod < rhs.displayStartPeriod
                }
                return lhs.title.localizedCompare(rhs.title) == .orderedAscending
            }
        }

        return TimetableGridSnapshot(
            signature: signature,
            totalWeeks: totalWeeks,
            visibleDays: visibleDays,
            courseNoteKeys: courseNoteKeys,
            occurrenceNoteKeys: occurrenceNoteKeys,
            layoutsByDay: layoutsByDay,
            occupiedPeriodsByDay: occupiedPeriodsByDay,
            latestCellReminderByKey: latestCellReminderByKey,
            cellRemindersByDay: cellRemindersByDay,
            courseNotesByKey: courseNotesByKey,
            occurrenceNotesByKey: occurrenceNotesByKey
        )
    }

    func layouts(day: Int, week: Int) -> [TimetableGridCourseLayout] {
        layoutsByDay[TimetableGridDayKey(week: week, day: day)] ?? []
    }

    func occupiedPeriods(day: Int, week: Int) -> Set<Int> {
        occupiedPeriodsByDay[TimetableGridDayKey(week: week, day: day)] ?? []
    }

    func cellReminder(week: Int, day: Int, period: Int) -> TimetableCellReminderRenderValue? {
        latestCellReminderByKey[TimetableCellReminder.cellKey(week: week, dayOfWeek: day, period: period)]
    }

    func cellReminders(week: Int, day: Int) -> [TimetableCellReminderRenderValue] {
        cellRemindersByDay[TimetableGridDayKey(week: week, day: day)] ?? []
    }

    func hasNote(for course: Course, week: Int) -> Bool {
        note(for: course, week: week) != nil
    }

    func note(for course: Course, week: Int) -> String? {
        TimetableNoteResolver.effectiveNote(
            for: course,
            week: week,
            courseNotesByKey: courseNotesByKey,
            occurrenceNotesByKey: occurrenceNotesByKey
        )
    }

    func hasNote(for course: TimetableCourseRenderValue, week: Int) -> Bool {
        note(for: course, week: week) != nil
    }

    func note(for course: TimetableCourseRenderValue, week: Int) -> String? {
        let occurrenceText = occurrenceNotesByKey[course.occurrenceKey(week: week)]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let occurrenceText, !occurrenceText.isEmpty {
            return occurrenceText
        }

        let courseText = courseNotesByKey[course.stableCourseKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return courseText?.isEmpty == false ? courseText : nil
    }
}

@MainActor
final class TimetableGridSnapshotCache {
    private var cachedSnapshot: TimetableGridSnapshot?
    private(set) var buildCount = 0

    func snapshot(
        courses: [Course],
        notes: [CourseNote],
        occurrenceNotes: [CourseOccurrenceNote],
        cellReminders: [TimetableCellReminder],
        hidesWeekends: Bool,
        totalWeeks: Int
    ) -> TimetableGridSnapshot {
        snapshot(
            input: TimetableRenderInput(
                courses: courses,
                notes: notes,
                occurrenceNotes: occurrenceNotes,
                cellReminders: cellReminders,
                hidesWeekends: hidesWeekends
            ),
            totalWeeks: totalWeeks
        )
    }

    func snapshot(input: TimetableRenderInput, totalWeeks: Int) -> TimetableGridSnapshot {
        let signature = input.signature

        if let cachedSnapshot,
           cachedSnapshot.signature == signature,
           cachedSnapshot.totalWeeks == totalWeeks {
            return cachedSnapshot
        }

        let snapshot = TimetableGridSnapshot.make(
            courses: input.courses,
            notes: input.notes,
            occurrenceNotes: input.occurrenceNotes,
            cellReminders: input.cellReminders,
            hidesWeekends: signature.hidesWeekends,
            totalWeeks: totalWeeks,
            courseWeekProjections: input.courseWeekProjections,
            cellReminderProjections: input.cellReminderProjections,
            signature: signature
        )
        cachedSnapshot = snapshot
        buildCount += 1
        return snapshot
    }

    func invalidate() {
        cachedSnapshot = nil
    }
}

struct TimetableGridDayKey: Hashable {
    let week: Int
    let day: Int
}

@MainActor
struct DayCourseLayout: Identifiable {
    let course: Course
    let laneIndex: Int
    let laneCount: Int

    var id: UUID { course.id }
}

@MainActor
enum DayCourseLayoutBuilder {
    static func layouts(for courses: [Course]) -> [DayCourseLayout] {
        guard !courses.isEmpty else { return [] }

        var result: [DayCourseLayout] = []
        var cluster: [Course] = []
        var clusterMaxEnd = 0

        func flushCluster() {
            guard !cluster.isEmpty else { return }
            result.append(contentsOf: layoutsForCluster(cluster))
            cluster.removeAll()
            clusterMaxEnd = 0
        }

        for course in courses {
            let start = course.duration.min() ?? 0
            let end = course.duration.max() ?? 0

            if cluster.isEmpty {
                cluster = [course]
                clusterMaxEnd = end
                continue
            }

            if start <= clusterMaxEnd {
                cluster.append(course)
                clusterMaxEnd = max(clusterMaxEnd, end)
            } else {
                flushCluster()
                cluster = [course]
                clusterMaxEnd = end
            }
        }

        flushCluster()
        return result
    }

    private static func layoutsForCluster(_ cluster: [Course]) -> [DayCourseLayout] {
        var laneEndings: [Int] = []
        var placements: [(Course, Int)] = []

        for course in cluster {
            let start = course.duration.min() ?? 0
            let end = course.duration.max() ?? 0

            if let reusableLane = laneEndings.firstIndex(where: { $0 < start }) {
                laneEndings[reusableLane] = end
                placements.append((course, reusableLane))
            } else {
                laneEndings.append(end)
                placements.append((course, laneEndings.count - 1))
            }
        }

        return placements.map { course, laneIndex in
            DayCourseLayout(course: course, laneIndex: laneIndex, laneCount: max(1, laneEndings.count))
        }
    }
}
