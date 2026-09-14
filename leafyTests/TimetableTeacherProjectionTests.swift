import Foundation
import XCTest
@testable import Leafy

@MainActor
final class TimetableTeacherProjectionTests: XCTestCase {
    func testParsedTeacherSegmentsReachCoursesAndGridWithTheCorrectWeekTeacher() throws {
        let records = try HTMLParser.parseTimetableRecords(
            html: TimetableTeacherParserFixtures.completeTableHTML(
                entries: TimetableTeacherParserFixtures.segmentedSchedule
            )
        )
        let courses = records.map { $0.makeCourse() }

        let snapshot = TimetableGridSnapshot.make(
            courses: courses,
            notes: [],
            occurrenceNotes: [],
            cellReminders: [],
            hidesWeekends: false,
            totalWeeks: 14
        )

        let mondayTeachersByWeek = (2...14).compactMap { week in
            snapshot.layouts(day: 1, week: week)
                .first { $0.course.displayCourseName == "课程甲" }
                .map { (week, $0.course.teacher) }
        }
        XCTAssertEqual(
            mondayTeachersByWeek.map(\.0),
            Array(2...9) + Array(11...14)
        )
        XCTAssertEqual(
            mondayTeachersByWeek.map(\.1),
            Array(repeating: "教师甲", count: 8) + Array(repeating: "教师乙", count: 4)
        )

        let courseBTeachersByWeek = [2, 3, 6, 7, 8, 9, 10, 11].compactMap { week in
            snapshot.layouts(day: 3, week: week)
                .first { $0.course.displayCourseName == "课程乙" }
                .map { (week, $0.course.teacher) }
        }
        XCTAssertEqual(courseBTeachersByWeek.map(\.1), [
            "教师甲", "教师甲", "教师乙", "教师乙",
            "教师丙", "教师丙", "教师丙", "教师丙"
        ])
        XCTAssertTrue(snapshot.layouts(day: 3, week: 4).allSatisfy { $0.course.displayCourseName != "课程乙" })
        XCTAssertTrue(snapshot.layouts(day: 3, week: 5).allSatisfy { $0.course.displayCourseName != "课程乙" })
    }

    func testWidgetSnapshotUsesTeacherForTheCourseSegmentContainingEachWeek() throws {
        try withPreviousSpringConfig {
            let records = try HTMLParser.parseTimetableRecords(
                html: TimetableTeacherParserFixtures.completeTableHTML(
                    entries: TimetableTeacherParserFixtures.segmentedSchedule
                )
            )
            let courses = records.map { $0.makeCourse() }

            for (week, expectedTeacher) in [(2, "教师甲"), (6, "教师乙"), (8, "教师丙")] {
                let date = semesterDate(week: week, day: 3, hour: 11, minute: 30)
                let archive = LeafyWidgetSnapshotBuilder.makeArchiveForTesting(
                    courses: courses,
                    isAuthenticated: true,
                    date: date
                )
                let snapshot = try XCTUnwrap(archive.snapshot(for: 0))
                let course = try XCTUnwrap(snapshot.courses.first { $0.title == "课程乙" })

                XCTAssertEqual(course.teacherText, expectedTeacher, "第 \(week) 周教师不正确")
            }
        }
    }

    func testCalendarDraftsKeepTeacherNotesTimeLocationAndCountPerWeek() throws {
        try withPreviousSpringConfig {
            let semesterID = SemesterRuntimeConfig.previousSpring.semesterID
            let firstTeacher = Course(
                courseName: "分段课程",
                teacher: "教师甲",
                room: "101",
                location: "二教",
                dayOfWeek: 3,
                weeks: [2, 3],
                duration: [5],
                sourceSemesterID: semesterID
            )
            let secondTeacher = Course(
                courseName: "分段课程",
                teacher: "教师乙",
                room: "101",
                location: "二教",
                dayOfWeek: 3,
                weeks: [6, 7, 8],
                duration: [5],
                sourceSemesterID: semesterID
            )
            let occurrenceNote = CourseOccurrenceNote(
                courseKey: secondTeacher.stableCourseKey,
                occurrenceKey: secondTeacher.occurrenceKey(week: 6),
                week: 6,
                dayOfWeek: 3,
                text: "换师后课次备注"
            )

            let drafts = TimetableCalendarExportBuilder.drafts(
                courses: [firstTeacher, secondTeacher],
                courseNotes: [],
                occurrenceNotes: [occurrenceNote],
                range: .fullSemester,
                currentWeek: 1,
                totalWeeks: 8
            )

            XCTAssertEqual(drafts.count, 5)
            XCTAssertEqual(Set(drafts.map(\.occurrenceKey)).count, 5)

            let expected: [(Course, Int, String)] = [
                (firstTeacher, 2, "教师甲"),
                (firstTeacher, 3, "教师甲"),
                (secondTeacher, 6, "教师乙"),
                (secondTeacher, 7, "教师乙"),
                (secondTeacher, 8, "教师乙")
            ]
            for (course, week, teacher) in expected {
                let draft = try XCTUnwrap(
                    drafts.first { $0.occurrenceKey == course.occurrenceKey(week: week) }
                )
                XCTAssertTrue(draft.notes.contains(L10n.text("教师：%@", teacher)))
                XCTAssertEqual(draft.location, "二教 101")
                XCTAssertEqual(
                    draft.startDate,
                    try XCTUnwrap(TimetablePeriodSchedule.startDate(for: course, week: week))
                )
                XCTAssertEqual(
                    draft.endDate,
                    try XCTUnwrap(TimetablePeriodSchedule.endDate(for: course, week: week))
                )
            }

            let notedDraft = try XCTUnwrap(
                drafts.first { $0.occurrenceKey == secondTeacher.occurrenceKey(week: 6) }
            )
            XCTAssertTrue(notedDraft.notes.contains(L10n.text("周次：第 %d 周", 6)))
            XCTAssertTrue(notedDraft.notes.contains(L10n.text("备注：%@", "换师后课次备注")))
        }
    }

    func testParsedFixtureProducesThirtyTwoCalendarDraftsAndOnlyReplacesChangedTeacherKeys() throws {
        try withPreviousSpringConfig {
            let records = try HTMLParser.parseTimetableRecords(
                html: TimetableTeacherParserFixtures.completeTableHTML(
                    entries: TimetableTeacherParserFixtures.segmentedSchedule
                )
            )
            let newCourses = records.map { $0.makeCourse() }
            let oldCourses = legacyMergedCourses(from: newCourses)

            let newDrafts = TimetableCalendarExportBuilder.drafts(
                courses: newCourses,
                courseNotes: [],
                occurrenceNotes: [],
                range: .fullSemester,
                currentWeek: 1,
                totalWeeks: 14
            )
            let oldDrafts = TimetableCalendarExportBuilder.drafts(
                courses: oldCourses,
                courseNotes: [],
                occurrenceNotes: [],
                range: .fullSemester,
                currentWeek: 1,
                totalWeeks: 14
            )

            XCTAssertEqual(newDrafts.count, 32)
            XCTAssertEqual(oldDrafts.count, 32)
            XCTAssertEqual(presentationCounts(newDrafts), presentationCounts(oldDrafts))
            XCTAssertTrue(newDrafts.allSatisfy {
                TimetableCalendarExportBuilder.occurrenceKey(from: $0.url) == $0.occurrenceKey
            })
            XCTAssertTrue(oldDrafts.allSatisfy {
                TimetableCalendarExportBuilder.occurrenceKey(from: $0.url) == $0.occurrenceKey
            })

            let newKeys = Set(newDrafts.map(\.occurrenceKey))
            let oldKeys = Set(oldDrafts.map(\.occurrenceKey))
            XCTAssertEqual(oldKeys.intersection(newKeys).count, 18)
            XCTAssertEqual(oldKeys.subtracting(newKeys).count, 14)
            XCTAssertEqual(newKeys.subtracting(oldKeys).count, 14)

            let newTeacherByPresentation = teacherByPresentation(for: newCourses)
            let oldTeacherByPresentation = teacherByPresentation(for: oldCourses)
            XCTAssertEqual(Set(newTeacherByPresentation.keys), Set(oldTeacherByPresentation.keys))
            let changedPresentations = Set(newTeacherByPresentation.keys).filter {
                newTeacherByPresentation[$0] != oldTeacherByPresentation[$0]
            }
            XCTAssertEqual(changedPresentations.count, 14)

            let oldKeyByPresentation = Dictionary(uniqueKeysWithValues: oldDrafts.map {
                (DraftPresentation($0), $0.occurrenceKey)
            })
            let newKeyByPresentation = Dictionary(uniqueKeysWithValues: newDrafts.map {
                (DraftPresentation($0), $0.occurrenceKey)
            })
            let replacedOldKeys = Set(changedPresentations.compactMap { oldKeyByPresentation[$0] })
            let replacedNewKeys = Set(changedPresentations.compactMap { newKeyByPresentation[$0] })
            XCTAssertEqual(replacedOldKeys, oldKeys.subtracting(newKeys))
            XCTAssertEqual(replacedNewKeys, newKeys.subtracting(oldKeys))

            for course in newCourses {
                for week in course.weeks {
                    let draft = try XCTUnwrap(
                        newDrafts.first { $0.occurrenceKey == course.occurrenceKey(week: week) }
                    )
                    XCTAssertEqual(draft.title, course.displayCourseName)
                    XCTAssertEqual(draft.location, course.locationTextForShare)
                    XCTAssertEqual(
                        draft.startDate,
                        try XCTUnwrap(TimetablePeriodSchedule.startDate(for: course, week: week))
                    )
                    XCTAssertEqual(
                        draft.endDate,
                        try XCTUnwrap(TimetablePeriodSchedule.endDate(for: course, week: week))
                    )
                    XCTAssertTrue(draft.notes.contains(L10n.text("教师：%@", course.teacher)))
                    XCTAssertTrue(draft.notes.contains(L10n.text("周次：第 %d 周", week)))
                }
            }

            let repeatedDrafts = TimetableCalendarExportBuilder.drafts(
                courses: newCourses,
                courseNotes: [],
                occurrenceNotes: [],
                range: .fullSemester,
                currentWeek: 1,
                totalWeeks: 14
            )
            XCTAssertEqual(
                Set(repeatedDrafts.map(\.occurrenceKey)),
                newKeys
            )
        }
    }

    private func withPreviousSpringConfig<T>(_ body: () throws -> T) rethrows -> T {
        let savedConfig = SemesterRuntimeConfigCache.load()
        SemesterRuntimeConfigCache.save(.previousSpring)
        defer {
            if let savedConfig {
                SemesterRuntimeConfigCache.save(savedConfig)
            } else {
                SemesterRuntimeConfigCache.clear()
            }
        }
        return try body()
    }

    private struct LegacyArrangementKey: Hashable {
        let courseName: String
        let classInfo: String
        let room: String
        let location: String
        let dayOfWeek: Int
        let duration: [Int]

        init(course: Course) {
            courseName = course.courseName
            classInfo = course.classInfo
            room = course.room
            location = course.location
            dayOfWeek = course.dayOfWeek
            duration = course.duration.sorted()
        }
    }

    private struct DraftPresentation: Hashable {
        let title: String
        let location: String
        let startDate: Date
        let endDate: Date

        init(title: String, location: String, startDate: Date, endDate: Date) {
            self.title = title
            self.location = location
            self.startDate = startDate
            self.endDate = endDate
        }

        init(_ draft: TimetableCalendarEventDraft) {
            title = draft.title
            location = draft.location
            startDate = draft.startDate
            endDate = draft.endDate
        }
    }

    private func legacyMergedCourses(from courses: [Course]) -> [Course] {
        Dictionary(grouping: courses, by: LegacyArrangementKey.init).values.map { segments in
            let first = segments.min {
                ($0.weeks.min() ?? Int.max) < ($1.weeks.min() ?? Int.max)
            }!
            return Course(
                courseName: first.courseName,
                teacher: first.teacher,
                classInfo: first.classInfo,
                room: first.room,
                location: first.location,
                dayOfWeek: first.dayOfWeek,
                weeks: Set(segments.flatMap(\.weeks)).sorted(),
                duration: first.duration,
                sourceSemesterID: first.sourceSemesterID
            )
        }
    }

    private func presentationCounts(_ drafts: [TimetableCalendarEventDraft]) -> [DraftPresentation: Int] {
        Dictionary(grouping: drafts, by: DraftPresentation.init).mapValues(\.count)
    }

    private func teacherByPresentation(for courses: [Course]) -> [DraftPresentation: String] {
        Dictionary(uniqueKeysWithValues: courses.flatMap { course in
            course.weeks.compactMap { week -> (DraftPresentation, String)? in
                guard let startDate = TimetablePeriodSchedule.startDate(for: course, week: week),
                      let endDate = TimetablePeriodSchedule.endDate(for: course, week: week) else {
                    return nil
                }
                let presentation = DraftPresentation(
                    title: course.displayCourseName,
                    location: course.locationTextForShare,
                    startDate: startDate,
                    endDate: endDate
                )
                return (presentation, course.teacher)
            }
        })
    }
}
