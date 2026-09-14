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
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            throw TimetableNotificationError.permissionDenied
        }
        try await TimetableNotificationManager.applyReminder(minutesBefore: minutesBefore, anchorPeriod: anchorPeriod, course: course)
    }
}

@MainActor
struct TimetableReminderRefreshPlan {
    struct Schedule {
        let course: Course
        let minutesBefore: Int
        let anchorPeriod: Int?
    }

    let obsoleteIdentifiers: [String]
    let schedules: [Schedule]

    init(oldIdentifiers: [String], courses: [Course], settings: [CourseReminderSetting]) throws {
        obsoleteIdentifiers = oldIdentifiers
        let byKey = Dictionary(grouping: settings, by: \.courseKey)
        schedules = try courses.compactMap { course in
            guard let matches = byKey[course.stableCourseKey],
                  let setting = matches.max(by: { $0.updatedAt < $1.updatedAt }) else { return nil }
            guard matches.allSatisfy({ $0.minutesBefore == setting.minutesBefore && $0.anchorPeriod == setting.anchorPeriod }) else {
                throw TimetableLocalDataConflict.conflictingRecords(course.courseName)
            }
            guard setting.minutesBefore > 0 else { return nil }
            // Notification APIs suspend. A later refresh can delete the persisted model
            // while this plan is waiting, so retain an unmanaged copy for scheduling.
            let snapshot = Course(
                id: course.id, courseName: course.courseName, teacher: course.teacher, classInfo: course.classInfo,
                room: course.room, location: course.location, dayOfWeek: course.dayOfWeek,
                weeks: course.weeks, duration: course.duration, sourceSemesterID: course.sourceSemesterID
            )
            return Schedule(course: snapshot, minutesBefore: setting.minutesBefore, anchorPeriod: setting.anchorPeriod)
        }
        var identifiers = Set<String>()
        for schedule in schedules {
            for week in Set(schedule.course.weeks) {
                let identifier = TimetableNotificationManager.notificationID(courseKey: schedule.course.stableCourseKey, week: week)
                guard identifiers.insert(identifier).inserted else {
                    throw TimetableLocalDataConflict.conflictingRecords(schedule.course.courseName)
                }
            }
        }
    }

    /// Called only after the database commit. Rebuilding from persisted settings on every
    /// successful refresh also retries any previously failed notification scheduling.
    func restore(using scheduler: any TimetableCourseReminderScheduling = LiveTimetableCourseReminderScheduler()) async -> String? {
        scheduler.cancel(identifiers: obsoleteIdentifiers)
        var failureCount = 0
        var firstError: Error?
        for schedule in schedules {
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
