import Foundation
import UserNotifications
import OSLog

@MainActor
protocol TimetableCourseReminderScheduling {
    func cancel(identifiers: [String])
    func schedule(course: Course, minutesBefore: Int, anchorPeriod: Int?) async throws
}

@MainActor
struct LiveTimetableCourseReminderScheduler: TimetableCourseReminderScheduling {
    nonisolated init() {}

    func cancel(identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func schedule(course: Course, minutesBefore: Int, anchorPeriod: Int?) async throws {
        // Restoring existing settings (including background prefetch) must not open a
        // permission prompt. Explicit reminder editing retains its existing consent flow.
        let scope = CampusOperationScope()
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        try scope.check()
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            throw TimetableNotificationError.permissionDenied
        }
        try await TimetableNotificationManager.applyReminder(
            minutesBefore: minutesBefore,
            anchorPeriod: anchorPeriod,
            course: course
        )
    }
}

@MainActor
struct TimetableReminderRefreshPlan {
    enum FailureContext: Equatable { case timetableRefresh, settingsUpdate }

    struct Schedule {
        let course: Course
        let minutesBefore: Int
        let anchorPeriod: Int?
    }

    let obsoleteIdentifiers: [String]
    let schedules: [Schedule]
    private let scope = CampusOperationScope()

    init(oldIdentifiers: [String], courses: [Course], settings: [CourseReminderSetting]) throws {
        obsoleteIdentifiers = oldIdentifiers
        struct Configuration: Hashable {
            let minutes: Int
            let anchor: Int?
        }
        let byKey = Dictionary(grouping: settings.filter { !$0.isUnassociated }, by: \.courseKey)
        schedules = try courses.flatMap { course -> [Schedule] in
            let matches = byKey[course.stableCourseKey] ?? []
            for group in Dictionary(grouping: matches, by: \.week).values {
                guard let first = group.first,
                      group
                          .allSatisfy({
                              $0.minutesBefore == first.minutesBefore && $0.anchorPeriod == first.anchorPeriod })
                else { throw TimetableLocalDataConflict.conflictingRecords(course.courseName) }
            }
            var weeksByConfiguration: [Configuration: [Int]] = [:]
            for week in Set(course.weeks).sorted() {
                guard let setting = CourseReminderResolver.effective(courseKey: course.stableCourseKey, week: week,
                                                                     settings: matches),
                    setting.minutesBefore > 0 else { continue }
                let configuration = Configuration(minutes: setting.minutesBefore, anchor: setting.anchorPeriod)
                weeksByConfiguration[configuration, default: []].append(week)
            }
            return weeksByConfiguration.map { configuration, weeks in
                // Scheduling suspends; keep unmanaged value snapshots with only the weeks using this setting.
                let snapshot = Self.courseSnapshot(course)
                snapshot.weeks = weeks
                return Schedule(
                    course: snapshot,
                    minutesBefore: configuration.minutes,
                    anchorPeriod: configuration.anchor
                )
            }.sorted { ($0.course.weeks.first ?? 0) < ($1.course.weeks.first ?? 0) }
        }
        var identifiers = Set<String>()
        for schedule in schedules {
            for week in Set(schedule.course.weeks) {
                let identifier = TimetableNotificationManager.notificationID(
                    courseKey: schedule.course.stableCourseKey,
                    week: week
                )
                guard identifiers.insert(identifier).inserted else {
                    throw TimetableLocalDataConflict.conflictingRecords(schedule.course.courseName)
                }
            }
        }
    }

    static func courseSnapshot(_ course: Course) -> Course {
        Course(
            id: course.id, courseName: course.courseName, teacher: course.teacher, classInfo: course.classInfo,
            room: course.room, location: course.location, dayOfWeek: course.dayOfWeek,
            weeks: course.weeks, duration: course.duration, sourceSemesterID: course.sourceSemesterID
        )
    }

    /// Called only after the database commit. Rebuilding from persisted settings on every
    /// successful refresh also retries any previously failed notification scheduling.
    func restore(using scheduler: any TimetableCourseReminderScheduling = LiveTimetableCourseReminderScheduler(),
                 context: FailureContext = .timetableRefresh) async
        -> String? {
        guard scope.isCurrent, !Task.isCancelled else { return nil }
        scheduler.cancel(identifiers: obsoleteIdentifiers)
        var failureCount = 0
        var firstError: Error?
        for schedule in schedules {
            guard scope.isCurrent, !Task.isCancelled else { return nil }
            do {
                try await scheduler.schedule(
                    course: schedule.course, minutesBefore: schedule.minutesBefore, anchorPeriod: schedule.anchorPeriod
                )
            } catch {
                failureCount += 1
                if firstError == nil { firstError = error }
            }
        }
        guard let firstError else { return nil }
        Logger(subsystem: "com.isaachuo.leafy", category: "TimetableRefresh")
            .error("Course reminder restoration failed for \(failureCount) schedules after timetable commit")
        if context == .settingsUpdate {
            return L10n.text("提醒设置已保存，但 %d 项系统提醒排期失败：%@。请检查通知设置后再次应用。",
                             failureCount, firstError.localizedDescription)
        }
        return L10n.text(
            "课表已更新，但 %d 项课程提醒未恢复：%@。请检查通知设置后再次刷新课表。",
            failureCount, firstError.localizedDescription
        )
    }
}

@MainActor
struct TimetablePersistResult {
    let courses: [Course]
    let reminders: TimetableReminderRefreshPlan
    let sharedCourses: [SharedTimetableCourse]

    init(courses: [Course], reminders: TimetableReminderRefreshPlan) {
        self.courses = courses
        self.reminders = reminders
        sharedCourses = courses.map(SharedTimetableCourse.init(course:))
    }
}
