import Foundation
import os
import SwiftData

@MainActor
enum LeafyWidgetSnapshotBuilder {
    private static let logger = Logger(subsystem: "com.isaachuo.leafy", category: "WidgetSnapshot")

    static func publish(
        courses: [Course],
        notes: [CourseNote],
        occurrenceNotes: [CourseOccurrenceNote],
        reminders: [CourseReminderSetting],
        isAuthenticated: Bool,
        date: Date = Date()
    ) {
        let archive = makeArchive(
            courses: courses, notes: notes, occurrenceNotes: occurrenceNotes,
            reminders: reminders, schedules: CustomScheduleStore.load(),
            isAuthenticated: isAuthenticated, date: date
        )
        Task { await WidgetSnapshotPublisher.shared.publish(archive) }
    }

    static func publish(from modelContext: ModelContext, isAuthenticated: Bool, date: Date = Date()) {
        do {
            let archive = makeArchive(
                courses: try modelContext.fetch(FetchDescriptor<Course>()),
                notes: try modelContext.fetch(FetchDescriptor<CourseNote>()),
                occurrenceNotes: try modelContext.fetch(FetchDescriptor<CourseOccurrenceNote>()),
                reminders: try modelContext.fetch(FetchDescriptor<CourseReminderSetting>()),
                schedules: CustomScheduleStore.load(), isAuthenticated: isAuthenticated, date: date
            )
            Task { await WidgetSnapshotPublisher.shared.publish(archive) }
        } catch {
            // A failed read must not replace the last valid widget with an empty timetable.
            logger.error("Widget snapshot read failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func publishNeedsLogin(date: Date = Date()) {
        let archive = makeArchive(courses: [], notes: [], occurrenceNotes: [], reminders: [],
                                  schedules: [], isAuthenticated: false, date: date)
        Task { await WidgetSnapshotPublisher.shared.publishNeedsLogin(archive) }
    }

    #if DEBUG
    static func makeArchiveForTesting(
        courses: [Course],
        notes: [CourseNote] = [],
        occurrenceNotes: [CourseOccurrenceNote] = [],
        reminders: [CourseReminderSetting] = [],
        schedules: [CustomScheduleEvent] = [],
        isAuthenticated: Bool,
        date: Date
    ) -> LeafyWidgetSnapshotArchive {
        makeArchive(courses: courses, notes: notes, occurrenceNotes: occurrenceNotes,
                    reminders: reminders, schedules: schedules, isAuthenticated: isAuthenticated, date: date)
    }
    #endif

    private static func makeArchive(
        courses: [Course],
        notes: [CourseNote],
        occurrenceNotes: [CourseOccurrenceNote],
        reminders: [CourseReminderSetting],
        schedules: [CustomScheduleEvent],
        isAuthenticated: Bool,
        date: Date
    ) -> LeafyWidgetSnapshotArchive {
        let language = AppLanguagePreference.current
        let configs = SemesterConfig.timelineConfigurations
        let notesByKey = TimetableNoteResolver.courseNotesByKey(notes)
        let occurrenceNotesByKey = TimetableNoteResolver.occurrenceNotesByKey(occurrenceNotes)
        let remindersByKey = Dictionary(reminders.map { ($0.courseKey, $0.minutesBefore) },
                                       uniquingKeysWith: { _, latest in latest })
        let configsByID = Dictionary(uniqueKeysWithValues: configs.map { ($0.semesterID, $0) })
        var items: [LeafyWidgetAgendaItem] = []
        if isAuthenticated {
            for course in courses {
                guard let config = configsByID[course.sourceSemesterID],
                      let first = course.duration.min(), let last = course.duration.max(),
                      (1...7).contains(course.dayOfWeek) else { continue }
                for week in Set(course.weeks).sorted() where (1...config.supportedWeeks).contains(week) {
                    guard let start = TimetablePeriodSchedule.startDate(
                        semesterStartDate: config.semesterStartDate, week: week,
                        dayOfWeek: course.dayOfWeek, period: first
                    ), let end = TimetablePeriodSchedule.endDate(
                        semesterStartDate: config.semesterStartDate, week: week,
                        dayOfWeek: course.dayOfWeek, period: last
                    ), end > start else { continue }
                    let minutes = TimetableNotificationManager.normalizedReminderMinutes(remindersByKey[course.stableCourseKey] ?? 0)
                    items.append(LeafyWidgetAgendaItem(
                        id: "course-\(course.id.uuidString)-\(week)", kind: .course,
                        sourceID: course.id.uuidString, title: trimmed(course.courseName) ?? L10n.text("未命名课程"),
                        startsAt: start, endsAt: end, locationText: course.locationTextForShare,
                        teacherText: trimmed(course.teacher),
                        noteText: TimetableNoteResolver.effectiveNote(for: course, week: week,
                            courseNotesByKey: notesByKey, occurrenceNotesByKey: occurrenceNotesByKey),
                        reminderText: minutes > 0 ? L10n.text("提前 %d 分钟", language: language, minutes) : nil,
                        accentIndex: accentIndex(for: course.courseName)
                    ))
                }
            }
            items += schedules.map { event in
                LeafyWidgetAgendaItem(
                    id: "schedule-\(event.id)", kind: .schedule, sourceID: event.id,
                    title: event.title, startsAt: event.startsAt, endsAt: event.endsAt,
                    locationText: event.locationText, teacherText: nil, noteText: nil,
                    reminderText: nil, accentIndex: accentIndex(for: event.id)
                )
            }
        }
        items.sort { ($0.startsAt, $0.id) < ($1.startsAt, $1.id) }
        let exams = isAuthenticated ? SchoolDataCache.loadExamSchedule().compactMap { exam -> LeafyWidgetExam? in
            guard let start = exam.startsAt else { return nil }
            return LeafyWidgetExam(startsAt: start, endsAt: exam.endsAt ?? start,
                text: L10n.text("考试：%@ · %@", language: language, exam.name, exam.date))
        }.sorted { $0.startsAt < $1.startsAt } : []
        let firstSlot = TimetablePeriodSchedule.slots.first
        let lastSlot = TimetablePeriodSchedule.slots.last
        return LeafyWidgetSnapshotArchive(
            generatedAt: date, isAuthenticated: isAuthenticated,
            semesters: configs.map { config in
                LeafyWidgetSemester(id: config.semesterID, startsAt: config.semesterStartDate,
                    weekCount: config.supportedWeeks,
                    hasTimetableCache: courses.contains { $0.sourceSemesterID == config.semesterID }
                        || TimetableCacheMetadata.lastSyncedSemesterID == config.semesterID)
            }, items: items, exams: exams,
            defaultStartMinute: firstSlot.map { $0.startHour * 60 + $0.startMinute } ?? 480,
            defaultEndMinute: lastSlot.map { $0.endHour * 60 + $0.endMinute } ?? 1305,
            syncText: TimetableCacheMetadata.lastSyncAt.map {
                L10n.text("最近同步：%@", language: language, DateFormatters.headerWithTime.string(from: $0))
            }, lastFailureText: trimmed(TimetableCacheMetadata.lastFailureMessage)
        )
    }

    private static func accentIndex(for key: String) -> Int {
        key.utf8.reduce(0) { ($0 * 31 + Int($1)) % 8 }
    }

    private static func trimmed(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }
}
