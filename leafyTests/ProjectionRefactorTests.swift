import XCTest
import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers
import Supabase
import SwiftData
@testable import Leafy

extension PerformanceRefactorTests {
    @MainActor
    func testGridSnapshotCacheReusesMatchingInputs() {
        let course = Course(
            courseName: "A",
            teacher: "T",
            room: "101",
            location: "",
            dayOfWeek: 1,
            weeks: [1, 2],
            duration: [1]
        )
        let cache = TimetableGridSnapshotCache()

        let first = cache.snapshot(
            courses: [course],
            notes: [],
            occurrenceNotes: [],
            cellReminders: [],
            hidesWeekends: false,
            totalWeeks: 2
        )
        let second = cache.snapshot(
            courses: [course],
            notes: [],
            occurrenceNotes: [],
            cellReminders: [],
            hidesWeekends: false,
            totalWeeks: 2
        )

        XCTAssertEqual(cache.buildCount, 1)
        XCTAssertEqual(first.layouts(day: 1, week: 1).map(\.course.courseName), ["A"])
        XCTAssertEqual(second.layouts(day: 1, week: 2).map(\.course.courseName), ["A"])

        let weekdaysOnly = cache.snapshot(
            courses: [course],
            notes: [],
            occurrenceNotes: [],
            cellReminders: [],
            hidesWeekends: true,
            totalWeeks: 2
        )
        XCTAssertEqual(cache.buildCount, 2)
        XCTAssertEqual(weekdaysOnly.visibleDays, [1, 2, 3, 4, 5])

        _ = cache.snapshot(
            courses: [course],
            notes: [],
            occurrenceNotes: [],
            cellReminders: [],
            hidesWeekends: true,
            totalWeeks: 3
        )
        XCTAssertEqual(cache.buildCount, 3)
    }

    func testTimetableScheduleProjectionSnapshotIndexesAndSortsByWeekDay() {
        let earlyCountdown = CustomCountdownEvent(
            id: "early",
            title: "Early",
            targetDate: semesterDate(week: 2, day: 1, hour: 8, minute: 10)
        )
        let lateCountdown = CustomCountdownEvent(
            id: "late",
            title: "Late",
            targetDate: semesterDate(week: 2, day: 1, hour: 9, minute: 55)
        )
        let otherDayCountdown = CustomCountdownEvent(
            id: "other",
            title: "Other",
            targetDate: semesterDate(week: 2, day: 2, hour: 8, minute: 10)
        )
        let exams = [
            ExamArrangement(id: 2, courseID: "B", name: "Second", date: "2026-03-16", start: "09:50", end: "10:35", location: "102"),
            ExamArrangement(id: 1, courseID: "A", name: "First", date: "2026-03-16", start: "08:00", end: "08:45", location: "101")
        ]

        let snapshot = TimetableScheduleProjectionSnapshot.make(
            countdownEvents: [lateCountdown, otherDayCountdown, earlyCountdown],
            exams: exams
        )

        XCTAssertEqual(snapshot.countdowns(week: 2, day: 1).map(\.title), ["Early", "Late"])
        XCTAssertEqual(snapshot.countdowns(week: 2, day: 2).map(\.title), ["Other"])
        XCTAssertEqual(snapshot.exams(week: 2, day: 1).map(\.name), ["First", "Second"])
        XCTAssertTrue(snapshot.exams(week: 19, day: 7).isEmpty)
    }

    @MainActor
    func testLearningWorkspaceIndexMatchesSummaryScopes() throws {
        let projectID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000124"))
        let now = reviewDate(2026, 5, 14)
        let sameWeek = reviewDate(2026, 5, 13)
        let materials = [
            LearningMaterialDocument(title: "CET", categoryRawValue: LearningMaterialCategory.cet.rawValue, originalFilename: "cet.pdf", localFilename: "cet.pdf", contentTypeIdentifier: UTType.pdf.identifier),
            LearningMaterialDocument(projectID: projectID.uuidString, title: "Project", originalFilename: "p.pdf", localFilename: "p.pdf", contentTypeIdentifier: UTType.pdf.identifier)
        ]
        let tasks = [
            LearningProjectTask(categoryRawValue: LearningMaterialCategory.cet.rawValue, title: "背单词"),
            LearningProjectTask(projectID: projectID.uuidString, title: "刷题", isCompleted: true)
        ]
        let records = [
            StudyTimeRecord(categoryRawValue: LearningMaterialCategory.cet.rawValue, startedAt: sameWeek, endedAt: sameWeek.addingTimeInterval(3600), content: "听力", location: "图书馆"),
            StudyTimeRecord(projectID: projectID.uuidString, startedAt: sameWeek, endedAt: sameWeek.addingTimeInterval(1800), content: "项目", location: "图书馆")
        ]

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let index = LearningWorkspaceIndex.make(materials: materials, tasks: tasks, records: records, now: now, calendar: calendar)

        XCTAssertEqual(
            index.summary(for: .fixed(.cet)),
            LearningWorkspaceSummary.make(destination: .fixed(.cet), materials: materials, tasks: tasks, records: records, now: now, calendar: calendar)
        )
        XCTAssertEqual(
            index.summary(for: .project(projectID)),
            LearningWorkspaceSummary.make(destination: .project(projectID), materials: materials, tasks: tasks, records: records, now: now, calendar: calendar)
        )
        XCTAssertEqual(index.tasks(for: .fixed(.cet)).map(\.title), ["背单词"])
    }

    @MainActor
    func testGradePresentationSnapshotMatchesExistingAnalyticsAndGrouping() {
        let grades = [
            Grade(term: "2025-2026-2", courseName: "森林生态学", credit: "2.0", score: "92", type: "必修"),
            Grade(term: "2025-2026-1", courseName: "高等数学", credit: "4.0", score: "85", type: "必修")
        ]

        let snapshot = GradePresentationSnapshot.make(grades: grades, creditSummary: nil)
        let directAnalytics = GradeAnalytics.calculate(from: grades, creditSummary: nil)

        XCTAssertEqual(snapshot.analytics.totalCredits, directAnalytics.totalCredits)
        XCTAssertEqual(snapshot.analytics.effectiveCourseCount, directAnalytics.effectiveCourseCount)
        XCTAssertEqual(snapshot.sortedTerms, ["2025-2026-2", "2025-2026-1"])
        XCTAssertEqual(snapshot.groupedGrades["2025-2026-2"]?.map(\.courseName), ["森林生态学"])
    }

    @MainActor
    func testWeeklyTimetableProjectionPrecomputesVisibleLayoutsAndMetadata() {
        let selection = TimetableDaySelection(
            week: 1,
            day: 1,
            date: SemesterConfig.startOfSemesterDate
        )
        let mondayCourse = Course(
            courseName: "森林生态学",
            teacher: "T",
            room: "101",
            location: "",
            dayOfWeek: 1,
            weeks: [1],
            duration: [1, 2]
        )
        let saturdayCourse = Course(
            courseName: "周末课程",
            teacher: "T",
            room: "102",
            location: "",
            dayOfWeek: 6,
            weeks: [1],
            duration: [1]
        )
        let note = CourseNote(courseKey: mondayCourse.stableCourseKey, text: "带实验服")
        let reminder = TimetableCellReminder(week: 1, dayOfWeek: 1, period: 3, title: "预习")
        let exam = ExamArrangement(
            id: 1,
            courseID: "exam-1",
            name: "植物学考试",
            date: "2026-03-09",
            start: "08:00",
            end: "09:00",
            location: "二教"
        )

        let weekdaysOnly = WeeklyTimetableProjection.make(
            selection: selection,
            courses: [mondayCourse, saturdayCourse],
            cellReminders: [reminder],
            exams: [exam],
            courseNotes: [note],
            occurrenceNotes: [],
            includesWeekends: false
        )
        let fullWeek = WeeklyTimetableProjection.make(
            selection: selection,
            courses: [mondayCourse, saturdayCourse],
            cellReminders: [reminder],
            exams: [exam],
            courseNotes: [note],
            occurrenceNotes: [],
            includesWeekends: true
        )

        XCTAssertEqual(weekdaysOnly.days, [1, 2, 3, 4, 5])
        XCTAssertEqual(weekdaysOnly.layouts(for: 1).map(\.course.courseName), ["森林生态学"])
        XCTAssertTrue(weekdaysOnly.layouts(for: 6).isEmpty)
        XCTAssertTrue(weekdaysOnly.hasNote(for: mondayCourse))
        XCTAssertEqual(weekdaysOnly.reminders.map(\.title), ["预习"])
        XCTAssertEqual(weekdaysOnly.examProjections.map(\.name), ["植物学考试"])
        XCTAssertEqual(fullWeek.layouts(for: 6).map(\.course.courseName), ["周末课程"])
    }
}
