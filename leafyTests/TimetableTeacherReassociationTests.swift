import Foundation
import SwiftData
import XCTest
@testable import Leafy

@MainActor
final class TimetableTeacherReassociationTests: XCTestCase {
    private let semesterID = "teacher-reassociation-semester"
    private let historicalSemesterID = "teacher-reassociation-history"

    func testTeacherSplitCopiesCourseDataAndMovesOccurrenceNotesByWeek() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let oldCourse = makeCourse(teacher: "教师甲", weeks: Array(1...16))
        let noteDate = Date(timeIntervalSince1970: 1_000)
        let reminderDate = Date(timeIntervalSince1970: 2_000)
        let occurrenceDate = Date(timeIntervalSince1970: 3_000)
        let courseNote = CourseNote(
            id: UUID(), courseKey: oldCourse.stableCourseKey, text: "全学期课程备注", updatedAt: noteDate
        )
        let reminderSetting = CourseReminderSetting(
            id: UUID(), courseKey: oldCourse.stableCourseKey, minutesBefore: 15,
            anchorPeriod: 3, updatedAt: reminderDate
        )
        let week3Note = CourseOccurrenceNote(
            id: UUID(), courseKey: oldCourse.stableCourseKey,
            occurrenceKey: oldCourse.occurrenceKey(week: 3), week: 3, dayOfWeek: 1,
            text: "甲老师第 3 周备注", updatedAt: occurrenceDate
        )
        let week11Note = CourseOccurrenceNote(
            id: UUID(), courseKey: oldCourse.stableCourseKey,
            occurrenceKey: oldCourse.occurrenceKey(week: 11), week: 11, dayOfWeek: 1,
            text: "换师后第 11 周备注", updatedAt: occurrenceDate
        )
        context.insert(oldCourse)
        context.insert(courseNote)
        context.insert(reminderSetting)
        context.insert(week3Note)
        context.insert(week11Note)
        try context.save()

        let result = try persistSplit(records: splitRecords(), existingCourses: [oldCourse], context: context)
        let courses = try context.fetch(FetchDescriptor<Course>())
        XCTAssertEqual(courses.count, 2)
        XCTAssertEqual(Set(courses.map(\.teacher)), Set(["教师甲", "教师乙"]))
        XCTAssertEqual(courses.first { $0.teacher == "教师甲" }?.weeks, Array(1...8))
        XCTAssertEqual(courses.first { $0.teacher == "教师乙" }?.weeks, Array(9...16))

        let currentKeys = Set(courses.map(\.stableCourseKey))
        let notes = try context.fetch(FetchDescriptor<CourseNote>())
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(Set(notes.map(\.courseKey)), currentKeys)
        XCTAssertTrue(notes.allSatisfy { $0.text == "全学期课程备注" && $0.updatedAt == noteDate })

        let settings = try context.fetch(FetchDescriptor<CourseReminderSetting>())
        XCTAssertEqual(settings.count, 2)
        XCTAssertEqual(Set(settings.map(\.courseKey)), currentKeys)
        XCTAssertTrue(settings.allSatisfy {
            $0.minutesBefore == 15 && $0.anchorPeriod == 3 && $0.updatedAt == reminderDate
        })

        let occurrences = try context.fetch(FetchDescriptor<CourseOccurrenceNote>())
        XCTAssertEqual(occurrences.count, 2)
        let coursesByTeacher = Dictionary(uniqueKeysWithValues: courses.map { ($0.teacher, $0) })
        let occurrencesByID = Dictionary(uniqueKeysWithValues: occurrences.map { ($0.id, $0) })
        let persistedWeek3 = try XCTUnwrap(occurrencesByID[week3Note.id])
        let persistedWeek11 = try XCTUnwrap(occurrencesByID[week11Note.id])
        XCTAssertEqual(persistedWeek3.courseKey, coursesByTeacher["教师甲"]?.stableCourseKey)
        XCTAssertEqual(persistedWeek3.occurrenceKey, coursesByTeacher["教师甲"]?.occurrenceKey(week: 3))
        XCTAssertEqual(persistedWeek3.text, "甲老师第 3 周备注")
        XCTAssertEqual(persistedWeek3.updatedAt, occurrenceDate)
        XCTAssertEqual(persistedWeek11.courseKey, coursesByTeacher["教师乙"]?.stableCourseKey)
        XCTAssertEqual(persistedWeek11.occurrenceKey, coursesByTeacher["教师乙"]?.occurrenceKey(week: 11))
        XCTAssertEqual(persistedWeek11.text, "换师后第 11 周备注")
        XCTAssertEqual(persistedWeek11.updatedAt, occurrenceDate)
        XCTAssertEqual(result.courses.count, 2)
    }

    func testTeacherSplitPreservesHistoricalCourseAndPersonalCellReminder() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let currentCourse = makeCourse(teacher: "教师甲", weeks: Array(1...16))
        let historicalCourse = makeCourse(
            semesterID: historicalSemesterID, teacher: "历史教师", weeks: [2, 4], room: "202", dayOfWeek: 2
        )
        let reminderID = UUID()
        let createdAt = Date(timeIntervalSince1970: 4_000)
        let updatedAt = Date(timeIntervalSince1970: 5_000)
        let startsAt = Date(timeIntervalSince1970: 6_000)
        let endsAt = Date(timeIntervalSince1970: 6_900)
        let cellReminder = TimetableCellReminder(
            id: reminderID, week: 7, dayOfWeek: 4, period: 5, endPeriod: 6,
            title: "个人格子提醒", location: "图书馆", note: "自定义备注",
            startsAt: startsAt, endsAt: endsAt, minutesBefore: 20,
            createdAt: createdAt, updatedAt: updatedAt
        )
        context.insert(currentCourse)
        context.insert(historicalCourse)
        context.insert(cellReminder)
        try context.save()

        _ = try persistSplit(records: splitRecords(), existingCourses: [currentCourse, historicalCourse], context: context)

        let courses = try context.fetch(FetchDescriptor<Course>())
        let savedHistorical = try XCTUnwrap(courses.first { $0.id == historicalCourse.id })
        XCTAssertEqual(savedHistorical.sourceSemesterID, historicalSemesterID)
        XCTAssertEqual(savedHistorical.teacher, "历史教师")
        XCTAssertEqual(savedHistorical.weeks, [2, 4])
        XCTAssertEqual(savedHistorical.room, "202")
        XCTAssertEqual(savedHistorical.dayOfWeek, 2)
        XCTAssertEqual(courses.filter { $0.sourceSemesterID == semesterID }.count, 2)

        let reminders = try context.fetch(FetchDescriptor<TimetableCellReminder>())
        let savedReminder = try XCTUnwrap(reminders.first { $0.id == reminderID })
        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(savedReminder.cellKey, cellReminder.cellKey)
        XCTAssertEqual(savedReminder.week, 7)
        XCTAssertEqual(savedReminder.dayOfWeek, 4)
        XCTAssertEqual(savedReminder.period, 5)
        XCTAssertEqual(savedReminder.displayEndPeriod, 6)
        XCTAssertEqual(savedReminder.title, "个人格子提醒")
        XCTAssertEqual(savedReminder.locationText, "图书馆")
        XCTAssertEqual(savedReminder.noteText, "自定义备注")
        XCTAssertEqual(savedReminder.startsAt, startsAt)
        XCTAssertEqual(savedReminder.endsAt, endsAt)
        XCTAssertEqual(savedReminder.minutesBefore, 20)
        XCTAssertEqual(savedReminder.createdAt, createdAt)
        XCTAssertEqual(savedReminder.updatedAt, updatedAt)
    }

    func testRepeatedRefreshIsIdempotentAndLaterTeacherSegmentsCanBeEditedIndependently() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let oldCourse = makeCourse(teacher: "教师甲", weeks: Array(1...16))
        let noteDate = Date(timeIntervalSince1970: 7_000)
        let settingDate = Date(timeIntervalSince1970: 8_000)
        context.insert(oldCourse)
        context.insert(CourseNote(courseKey: oldCourse.stableCourseKey, text: "公共备注", updatedAt: noteDate))
        context.insert(CourseReminderSetting(
            courseKey: oldCourse.stableCourseKey, minutesBefore: 10, anchorPeriod: 3, updatedAt: settingDate
        ))
        context.insert(CourseOccurrenceNote(
            courseKey: oldCourse.stableCourseKey, occurrenceKey: oldCourse.occurrenceKey(week: 3),
            week: 3, dayOfWeek: 1, text: "第 3 周", updatedAt: noteDate
        ))
        context.insert(CourseOccurrenceNote(
            courseKey: oldCourse.stableCourseKey, occurrenceKey: oldCourse.occurrenceKey(week: 11),
            week: 11, dayOfWeek: 1, text: "第 11 周", updatedAt: noteDate
        ))
        try context.save()

        _ = try persistSplit(records: splitRecords(), existingCourses: [oldCourse], context: context)
        let firstNotes = try context.fetch(FetchDescriptor<CourseNote>())
        let firstOccurrences = try context.fetch(FetchDescriptor<CourseOccurrenceNote>())
        let firstSettings = try context.fetch(FetchDescriptor<CourseReminderSetting>())
        let firstNoteIDs = Set(firstNotes.map(\.id))
        let firstOccurrenceIDs = Set(firstOccurrences.map(\.id))
        let firstSettingIDs = Set(firstSettings.map(\.id))

        _ = try persistSplit(
            records: splitRecords(),
            existingCourses: try context.fetch(FetchDescriptor<Course>()),
            context: context
        )
        XCTAssertEqual(Set((try context.fetch(FetchDescriptor<CourseNote>())).map(\.id)), firstNoteIDs)
        XCTAssertEqual(Set((try context.fetch(FetchDescriptor<CourseOccurrenceNote>())).map(\.id)), firstOccurrenceIDs)
        XCTAssertEqual(Set((try context.fetch(FetchDescriptor<CourseReminderSetting>())).map(\.id)), firstSettingIDs)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CourseNote>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CourseReminderSetting>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CourseOccurrenceNote>()).count, 2)

        let refreshedCourses = try context.fetch(FetchDescriptor<Course>())
        let teacherB = try XCTUnwrap(refreshedCourses.first { $0.teacher == "教师乙" })
        let teacherANote = try XCTUnwrap(
            (try context.fetch(FetchDescriptor<CourseNote>())).first { $0.courseKey == refreshedCourses.first { $0.teacher == "教师甲" }?.stableCourseKey }
        )
        let teacherBNote = try XCTUnwrap(
            (try context.fetch(FetchDescriptor<CourseNote>())).first { $0.courseKey == teacherB.stableCourseKey }
        )
        let teacherBSetting = try XCTUnwrap(
            (try context.fetch(FetchDescriptor<CourseReminderSetting>())).first { $0.courseKey == teacherB.stableCourseKey }
        )
        let editedDate = Date(timeIntervalSince1970: 9_000)
        teacherBNote.text = "乙教师段独立备注"
        teacherBNote.updatedAt = editedDate
        teacherBSetting.minutesBefore = 30
        teacherBSetting.updatedAt = editedDate
        try context.save()

        _ = try persistSplit(
            records: splitRecords(),
            existingCourses: try context.fetch(FetchDescriptor<Course>()),
            context: context
        )
        let finalCourses = try context.fetch(FetchDescriptor<Course>())
        let finalAKey = try XCTUnwrap(finalCourses.first { $0.teacher == "教师甲" }?.stableCourseKey)
        let finalBKey = try XCTUnwrap(finalCourses.first { $0.teacher == "教师乙" }?.stableCourseKey)
        let finalNotes = try context.fetch(FetchDescriptor<CourseNote>())
        let finalSettings = try context.fetch(FetchDescriptor<CourseReminderSetting>())
        XCTAssertEqual(finalNotes.first { $0.courseKey == finalAKey }?.text, "公共备注")
        XCTAssertEqual(finalNotes.first { $0.courseKey == finalBKey }?.text, "乙教师段独立备注")
        XCTAssertEqual(finalNotes.first { $0.courseKey == finalBKey }?.updatedAt, editedDate)
        XCTAssertEqual(finalSettings.first { $0.courseKey == finalAKey }?.minutesBefore, 10)
        XCTAssertEqual(finalSettings.first { $0.courseKey == finalBKey }?.minutesBefore, 30)
        XCTAssertEqual(finalSettings.first { $0.courseKey == finalBKey }?.updatedAt, editedDate)
        XCTAssertEqual(finalCourses.count, 2)
        XCTAssertNotNil(teacherANote)
    }

    func testExistingTargetRecordsWithSameValuesAreDeduplicated() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let oldCourse = makeCourse(teacher: "教师甲", weeks: Array(1...16))
        let targetCourse = makeCourse(teacher: "教师乙", weeks: Array(9...16))
        let sourceDate = Date(timeIntervalSince1970: 10_000)
        let oldNote = CourseNote(
            courseKey: oldCourse.stableCourseKey, text: "相同内容", updatedAt: sourceDate
        )
        let targetNoteOld = CourseNote(
            id: UUID(), courseKey: targetCourse.stableCourseKey, text: "相同内容",
            updatedAt: Date(timeIntervalSince1970: 9_000)
        )
        let targetNoteNewest = CourseNote(
            id: UUID(), courseKey: targetCourse.stableCourseKey, text: "相同内容",
            updatedAt: Date(timeIntervalSince1970: 9_500)
        )
        let oldSetting = CourseReminderSetting(
            courseKey: oldCourse.stableCourseKey, minutesBefore: 10, anchorPeriod: 3, updatedAt: sourceDate
        )
        let targetSettingOld = CourseReminderSetting(
            id: UUID(), courseKey: targetCourse.stableCourseKey, minutesBefore: 10, anchorPeriod: 3,
            updatedAt: Date(timeIntervalSince1970: 9_000)
        )
        let targetSettingNewest = CourseReminderSetting(
            id: UUID(), courseKey: targetCourse.stableCourseKey, minutesBefore: 10, anchorPeriod: 3,
            updatedAt: Date(timeIntervalSince1970: 9_500)
        )
        context.insert(oldCourse)
        context.insert(oldNote)
        context.insert(targetNoteOld)
        context.insert(targetNoteNewest)
        context.insert(oldSetting)
        context.insert(targetSettingOld)
        context.insert(targetSettingNewest)
        try context.save()

        _ = try persistSplit(records: splitRecords(), existingCourses: [oldCourse], context: context)
        let notes = try context.fetch(FetchDescriptor<CourseNote>())
        let settings = try context.fetch(FetchDescriptor<CourseReminderSetting>())
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(settings.count, 2)
        XCTAssertEqual(notes.filter { $0.courseKey == targetCourse.stableCourseKey }.count, 1)
        XCTAssertEqual(settings.filter { $0.courseKey == targetCourse.stableCourseKey }.count, 1)
        XCTAssertEqual(notes.first { $0.courseKey == targetCourse.stableCourseKey }?.id, targetNoteNewest.id)
        XCTAssertEqual(notes.first { $0.courseKey == targetCourse.stableCourseKey }?.text, "相同内容")
        XCTAssertEqual(notes.first { $0.courseKey == targetCourse.stableCourseKey }?.updatedAt, sourceDate)
        XCTAssertEqual(settings.first { $0.courseKey == targetCourse.stableCourseKey }?.id, targetSettingNewest.id)
        XCTAssertEqual(settings.first { $0.courseKey == targetCourse.stableCourseKey }?.minutesBefore, 10)
        XCTAssertEqual(settings.first { $0.courseKey == targetCourse.stableCourseKey }?.updatedAt, sourceDate)
    }

    func testDifferentTargetCourseNoteFailsWithoutChangingExistingData() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let oldCourse = makeCourse(teacher: "教师甲", weeks: Array(1...16))
        let targetCourse = makeCourse(teacher: "教师乙", weeks: Array(9...16))
        let sourceNote = CourseNote(courseKey: oldCourse.stableCourseKey, text: "甲段内容")
        let targetNote = CourseNote(courseKey: targetCourse.stableCourseKey, text: "乙段内容")
        context.insert(oldCourse)
        context.insert(sourceNote)
        context.insert(targetNote)
        try context.save()

        XCTAssertThrowsError(
            try persistSplit(records: splitRecords(), existingCourses: [oldCourse], context: context)
        )
        let courses = try context.fetch(FetchDescriptor<Course>())
        XCTAssertEqual(courses.count, 1)
        XCTAssertEqual(courses.first?.id, oldCourse.id)
        XCTAssertEqual(courses.first?.teacher, "教师甲")
        let notes = try context.fetch(FetchDescriptor<CourseNote>())
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes.first { $0.courseKey == oldCourse.stableCourseKey }?.text, "甲段内容")
        XCTAssertEqual(notes.first { $0.courseKey == targetCourse.stableCourseKey }?.text, "乙段内容")
    }

    func testDifferentTargetReminderFailsWithoutChangingExistingData() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let oldCourse = makeCourse(teacher: "教师甲", weeks: Array(1...16))
        let targetCourse = makeCourse(teacher: "教师乙", weeks: Array(9...16))
        let sourceSetting = CourseReminderSetting(
            courseKey: oldCourse.stableCourseKey, minutesBefore: 10, anchorPeriod: 3
        )
        let targetSetting = CourseReminderSetting(
            courseKey: targetCourse.stableCourseKey, minutesBefore: 20, anchorPeriod: 3
        )
        context.insert(oldCourse)
        context.insert(sourceSetting)
        context.insert(targetSetting)
        try context.save()

        XCTAssertThrowsError(
            try persistSplit(records: splitRecords(), existingCourses: [oldCourse], context: context)
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<Course>()).count, 1)
        let settings = try context.fetch(FetchDescriptor<CourseReminderSetting>())
        XCTAssertEqual(settings.count, 2)
        XCTAssertEqual(settings.first { $0.courseKey == oldCourse.stableCourseKey }?.minutesBefore, 10)
        XCTAssertEqual(settings.first { $0.courseKey == targetCourse.stableCourseKey }?.minutesBefore, 20)
    }

    func testSameCourseNameWithDifferentClassOrRoomDoesNotReassociateLocalData() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let oldCourse = makeCourse(
            teacher: "教师甲", weeks: Array(1...16), room: "101", classInfo: "林业 1 班"
        )
        let oldCourseKey = oldCourse.stableCourseKey
        let unrelatedIncoming = makeRecord(
            teacher: "教师乙", weeks: Array(9...16), classInfo: "林业 2 班", room: "202"
        )
        let note = CourseNote(courseKey: oldCourse.stableCourseKey, text: "原班级备注")
        context.insert(oldCourse)
        context.insert(note)
        try context.save()

        _ = try persistSplit(records: [unrelatedIncoming], existingCourses: [oldCourse], context: context)
        let courses = try context.fetch(FetchDescriptor<Course>())
        XCTAssertEqual(courses.count, 1)
        XCTAssertEqual(courses.first?.teacher, "教师乙")
        XCTAssertEqual(courses.first?.classInfo, "林业 2 班")
        XCTAssertEqual(courses.first?.room, "202")
        let notes = try context.fetch(FetchDescriptor<CourseNote>())
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.courseKey, oldCourseKey)
        XCTAssertEqual(notes.first?.text, "原班级备注")
        XCTAssertNotEqual(notes.first?.courseKey, courses.first?.stableCourseKey)
    }

    func testAlreadySeparatedSameWeekTeachersKeepIndependentNotesAcrossRefreshes() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let teacherACourse = makeCourse(teacher: "教师甲", weeks: [1])
        let teacherBCourse = makeCourse(teacher: "教师乙", weeks: [1])
        let teacherAKey = teacherACourse.stableCourseKey
        let teacherBKey = teacherBCourse.stableCourseKey
        let teacherANote = CourseNote(courseKey: teacherACourse.stableCourseKey, text: "甲段备注")
        let teacherBNote = CourseNote(courseKey: teacherBCourse.stableCourseKey, text: "乙段备注")
        context.insert(teacherACourse)
        context.insert(teacherBCourse)
        context.insert(teacherANote)
        context.insert(teacherBNote)
        try context.save()
        let records = [
            makeRecord(teacher: "教师甲", weeks: [1]),
            makeRecord(teacher: "教师乙", weeks: [1])
        ]

        _ = try persistSplit(records: records, existingCourses: [teacherACourse, teacherBCourse], context: context)
        var courses = try context.fetch(FetchDescriptor<Course>())
        var notes = try context.fetch(FetchDescriptor<CourseNote>())
        XCTAssertEqual(courses.count, 2)
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes.first { $0.courseKey == teacherAKey }?.text, "甲段备注")
        XCTAssertEqual(notes.first { $0.courseKey == teacherBKey }?.text, "乙段备注")

        let refreshedBCourse = try XCTUnwrap(courses.first { $0.teacher == "教师乙" })
        let refreshedBNote = try XCTUnwrap(notes.first { $0.courseKey == refreshedBCourse.stableCourseKey })
        refreshedBNote.text = "乙段独立编辑"
        try context.save()

        _ = try persistSplit(
            records: records,
            existingCourses: try context.fetch(FetchDescriptor<Course>()),
            context: context
        )
        courses = try context.fetch(FetchDescriptor<Course>())
        notes = try context.fetch(FetchDescriptor<CourseNote>())
        XCTAssertEqual(courses.count, 2)
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes.first { $0.courseKey == teacherAKey }?.text, "甲段备注")
        XCTAssertEqual(notes.first { $0.courseKey == teacherBKey }?.text, "乙段独立编辑")
    }

    func testSameWeekMultipleTeacherCandidatesRejectWithoutMutation() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let oldCourse = makeCourse(teacher: "教师甲", weeks: Array(1...16))
        let occurrence = CourseOccurrenceNote(
            courseKey: oldCourse.stableCourseKey, occurrenceKey: oldCourse.occurrenceKey(week: 1),
            week: 1, dayOfWeek: 1, text: "待确认的第 1 周备注"
        )
        context.insert(oldCourse)
        context.insert(occurrence)
        try context.save()
        let ambiguousRecords = [
            makeRecord(teacher: "教师甲", weeks: Array(1...8)),
            makeRecord(teacher: "教师乙", weeks: Array(1...8))
        ]

        XCTAssertThrowsError(
            try persistSplit(records: ambiguousRecords, existingCourses: [oldCourse], context: context)
        )
        let courses = try context.fetch(FetchDescriptor<Course>())
        XCTAssertEqual(courses.count, 1)
        XCTAssertEqual(courses.first?.id, oldCourse.id)
        XCTAssertEqual(courses.first?.weeks, Array(1...16))
        let savedOccurrence = try XCTUnwrap(try context.fetch(FetchDescriptor<CourseOccurrenceNote>()).first)
        XCTAssertEqual(savedOccurrence.id, occurrence.id)
        XCTAssertEqual(savedOccurrence.courseKey, oldCourse.stableCourseKey)
        XCTAssertEqual(savedOccurrence.occurrenceKey, oldCourse.occurrenceKey(week: 1))
        XCTAssertEqual(savedOccurrence.text, "待确认的第 1 周备注")
    }

    func testInjectedSaveFailureRollsBackCoursesAndAllCourseLocalData() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let oldCourse = makeCourse(teacher: "教师甲", weeks: Array(1...16))
        let noteDate = Date(timeIntervalSince1970: 11_000)
        let reminderDate = Date(timeIntervalSince1970: 12_000)
        let occurrenceDate = Date(timeIntervalSince1970: 13_000)
        let note = CourseNote(
            courseKey: oldCourse.stableCourseKey, text: "回滚课程备注", updatedAt: noteDate
        )
        let occurrence = CourseOccurrenceNote(
            courseKey: oldCourse.stableCourseKey, occurrenceKey: oldCourse.occurrenceKey(week: 11),
            week: 11, dayOfWeek: 1, text: "回滚课次备注", updatedAt: occurrenceDate
        )
        let setting = CourseReminderSetting(
            courseKey: oldCourse.stableCourseKey, minutesBefore: 25, anchorPeriod: 3, updatedAt: reminderDate
        )
        context.insert(oldCourse)
        context.insert(note)
        context.insert(occurrence)
        context.insert(setting)
        try context.save()

        XCTAssertThrowsError(
            try persistSplit(
                records: splitRecords(), existingCourses: [oldCourse], context: context,
                save: { _ in throw InjectedSaveError.failure }
            )
        ) { error in
            XCTAssertTrue(error is InjectedSaveError)
        }

        let courses = try context.fetch(FetchDescriptor<Course>())
        XCTAssertEqual(courses.count, 1)
        XCTAssertEqual(courses.first?.id, oldCourse.id)
        XCTAssertEqual(courses.first?.teacher, "教师甲")
        XCTAssertEqual(courses.first?.weeks, Array(1...16))
        let savedNote = try XCTUnwrap(try context.fetch(FetchDescriptor<CourseNote>()).first)
        XCTAssertEqual(savedNote.id, note.id)
        XCTAssertEqual(savedNote.courseKey, oldCourse.stableCourseKey)
        XCTAssertEqual(savedNote.text, "回滚课程备注")
        XCTAssertEqual(savedNote.updatedAt, noteDate)
        let savedOccurrence = try XCTUnwrap(try context.fetch(FetchDescriptor<CourseOccurrenceNote>()).first)
        XCTAssertEqual(savedOccurrence.id, occurrence.id)
        XCTAssertEqual(savedOccurrence.courseKey, oldCourse.stableCourseKey)
        XCTAssertEqual(savedOccurrence.occurrenceKey, oldCourse.occurrenceKey(week: 11))
        XCTAssertEqual(savedOccurrence.text, "回滚课次备注")
        XCTAssertEqual(savedOccurrence.updatedAt, occurrenceDate)
        let savedSetting = try XCTUnwrap(try context.fetch(FetchDescriptor<CourseReminderSetting>()).first)
        XCTAssertEqual(savedSetting.id, setting.id)
        XCTAssertEqual(savedSetting.courseKey, oldCourse.stableCourseKey)
        XCTAssertEqual(savedSetting.minutesBefore, 25)
        XCTAssertEqual(savedSetting.anchorPeriod, 3)
        XCTAssertEqual(savedSetting.updatedAt, reminderDate)
    }

    func testReminderRefreshCancelsObsoleteIDsAndSchedulesPersistedTeacherSegments() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let oldCourse = makeCourse(teacher: "教师甲", weeks: Array(1...16))
        let expectedOldIdentifiers = Set(TimetableNotificationManager.courseReminderIdentifiers(for: oldCourse))
        context.insert(oldCourse)
        context.insert(CourseReminderSetting(
            courseKey: oldCourse.stableCourseKey, minutesBefore: 15, anchorPeriod: 3
        ))
        try context.save()

        let result = try persistSplit(records: splitRecords(), existingCourses: [oldCourse], context: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Course>()).count, 2)
        let scheduler = RecordingTimetableCourseReminderScheduler()
        let warning = await result.reminders.restore(using: scheduler)

        XCTAssertNil(warning)
        XCTAssertEqual(scheduler.cancelCalls.count, 1)
        XCTAssertEqual(Set(scheduler.cancelCalls[0]), expectedOldIdentifiers)
        XCTAssertEqual(scheduler.events.first, "cancel")
        XCTAssertEqual(scheduler.scheduleCalls.count, 2)
        XCTAssertEqual(Set(scheduler.scheduleCalls.map(\.courseKey)), Set(result.courses.map(\.stableCourseKey)))
        XCTAssertTrue(scheduler.scheduleCalls.allSatisfy {
            $0.minutesBefore == 15 && $0.anchorPeriod == 3
        })
        XCTAssertEqual(Set(scheduler.scheduleCalls.map(\.teacher)), Set(["教师甲", "教师乙"]))
    }

    func testReminderSchedulingFailureLeavesSavedDataAndNextRefreshRetries() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let oldCourse = makeCourse(teacher: "教师甲", weeks: Array(1...16))
        let note = CourseNote(courseKey: oldCourse.stableCourseKey, text: "保留备注")
        context.insert(oldCourse)
        context.insert(note)
        context.insert(CourseReminderSetting(
            courseKey: oldCourse.stableCourseKey, minutesBefore: 15, anchorPeriod: 3
        ))
        try context.save()

        let first = try persistSplit(records: splitRecords(), existingCourses: [oldCourse], context: context)
        let scheduler = RecordingTimetableCourseReminderScheduler(failuresRemaining: 1)
        let firstWarning = await first.reminders.restore(using: scheduler)
        XCTAssertNotNil(firstWarning)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Course>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CourseNote>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CourseReminderSetting>()).count, 2)
        XCTAssertEqual(scheduler.scheduleCalls.count, 2)

        let second = try persistSplit(
            records: splitRecords(),
            existingCourses: try context.fetch(FetchDescriptor<Course>()),
            context: context
        )
        let secondWarning = await second.reminders.restore(using: scheduler)
        XCTAssertNil(secondWarning)
        XCTAssertEqual(scheduler.scheduleCalls.count, 4)
        XCTAssertEqual(
            Set(scheduler.scheduleCalls.suffix(2).map(\.teacher)),
            Set(["教师甲", "教师乙"])
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<Course>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CourseNote>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CourseReminderSetting>()).count, 2)
    }

    func testLongSharedCourseKeyPrefixesStillProduceDistinctNotificationIDs() {
        let longPrefix = String(repeating: "同名课程", count: 80)
        let first = makeCourse(courseName: longPrefix, teacher: "教师甲", dayOfWeek: 1)
        let second = makeCourse(courseName: longPrefix, teacher: "教师乙", dayOfWeek: 2)
        let firstID = TimetableNotificationManager.notificationID(courseKey: first.stableCourseKey, week: 11)
        let secondID = TimetableNotificationManager.notificationID(courseKey: second.stableCourseKey, week: 11)

        XCTAssertNotEqual(first.stableCourseKey, second.stableCourseKey)
        XCTAssertNotEqual(firstID, secondID)
        XCTAssertEqual(Set([firstID, secondID]).count, 2)
    }

    func testOverlappingReminderIdentifiersRollBackAssociationChanges() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let old = makeCourse(teacher: "教师甲")
        let oldKey = old.stableCourseKey
        context.insert(old)
        context.insert(CourseNote(courseKey: oldKey, text: "保留课程备注"))
        context.insert(CourseReminderSetting(courseKey: oldKey, minutesBefore: 10))
        try context.save()
        let first = makeRecord(teacher: "教师乙", weeks: Array(1...16))
        var second = first
        second.room = "102" // Existing stable keys include the building, but not the room.

        XCTAssertThrowsError(try persistSplit(records: [first, second], existingCourses: [old], context: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Course>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CourseNote>()).map(\.courseKey), [oldKey])
        XCTAssertEqual(try context.fetch(FetchDescriptor<CourseReminderSetting>()).map(\.courseKey), [oldKey])
    }

    func testOccurrenceOutsideOldWeekCoverageBlocksAnAffectedSplit() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let old = makeCourse(teacher: "教师甲")
        let oldKey = old.stableCourseKey
        context.insert(old)
        context.insert(CourseOccurrenceNote(courseKey: oldKey, occurrenceKey: old.occurrenceKey(week: 17),
                                            week: 17, dayOfWeek: 1, text: "保留未匹配备注"))
        try context.save()

        XCTAssertThrowsError(try persistSplit(records: splitRecords(), existingCourses: [old], context: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Course>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CourseOccurrenceNote>()).first?.courseKey, oldKey)
    }

    func testPeriodSplitPreservesReminderAnchorAndUsesExistingFallback() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let old = makeCourse(teacher: "教师甲")
        context.insert(old)
        context.insert(CourseReminderSetting(courseKey: old.stableCourseKey, minutesBefore: 15, anchorPeriod: 4))
        try context.save()
        var first = makeRecord(teacher: "教师甲", weeks: Array(1...16))
        first.duration = [3]
        var second = makeRecord(teacher: "教师乙", weeks: Array(1...16))
        second.duration = [4]
        let result = try persistSplit(records: [first, second], existingCourses: [old], context: context)

        XCTAssertEqual(result.reminders.schedules.count, 2)
        for schedule in result.reminders.schedules {
            XCTAssertEqual(schedule.minutesBefore, 15)
            XCTAssertEqual(schedule.anchorPeriod, 4)
            XCTAssertEqual(TimetableNotificationManager.resolvedAnchorPeriod(schedule.anchorPeriod, for: schedule.course),
                           schedule.course.duration.first)
        }
    }

    func testOccurrenceDestinationsDeduplicateEqualTextAndRejectDifferentText() throws {
        for targetText in ["相同备注", "不同备注"] {
            let container = try makeContainer()
            let context = container.mainContext
            let old = makeCourse(teacher: "教师甲")
            let oldKey = old.stableCourseKey
            let target = makeCourse(teacher: "教师乙", weeks: Array(9...16))
            let sourceID = UUID()
            context.insert(old)
            context.insert(CourseOccurrenceNote(id: sourceID, courseKey: oldKey,
                occurrenceKey: old.occurrenceKey(week: 11), week: 11, dayOfWeek: 1,
                text: "相同备注", updatedAt: Date(timeIntervalSince1970: 2_000)))
            context.insert(CourseOccurrenceNote(courseKey: target.stableCourseKey,
                occurrenceKey: target.occurrenceKey(week: 11), week: 11, dayOfWeek: 1,
                text: targetText, updatedAt: Date(timeIntervalSince1970: 1_000)))
            try context.save()
            if targetText == "相同备注" {
                _ = try persistSplit(records: splitRecords(), existingCourses: [old], context: context)
                let notes = try context.fetch(FetchDescriptor<CourseOccurrenceNote>())
                XCTAssertEqual(notes.count, 1)
                XCTAssertEqual(notes.first?.id, sourceID)
                XCTAssertEqual(notes.first?.courseKey, target.stableCourseKey)
            } else {
                XCTAssertThrowsError(try persistSplit(records: splitRecords(), existingCourses: [old], context: context))
                XCTAssertEqual(try context.fetch(FetchDescriptor<Course>()).count, 1)
                let notes = try context.fetch(FetchDescriptor<CourseOccurrenceNote>())
                XCTAssertEqual(notes.count, 2)
                XCTAssertEqual(notes.first { $0.id == sourceID }?.courseKey, oldKey)
            }
        }
    }

    func testAsyncReminderAndSharingPayloadsSurviveASecondCourseReplacement() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let old = makeCourse(teacher: "教师甲")
        context.insert(old)
        context.insert(CourseReminderSetting(courseKey: old.stableCourseKey, minutesBefore: 15))
        try context.save()
        let first = try persistSplit(records: splitRecords(), existingCourses: [old], context: context)
        let laterRecords = splitRecords().map { record in
            var updated = record
            updated.teacher += "更新"
            return updated
        }
        _ = try persistSplit(records: laterRecords, existingCourses: first.courses, context: context)
        XCTAssertEqual(Set(first.reminders.schedules.map { $0.course.teacher }), ["教师甲", "教师乙"])
        XCTAssertEqual(Set(first.sharedCourses.map(\.teacher)), ["教师甲", "教师乙"])
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<Course>()).map(\.teacher)), ["教师甲更新", "教师乙更新"])
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Course.self,
            CourseNote.self,
            CourseOccurrenceNote.self,
            CourseReminderSetting.self,
            TimetableCellReminder.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeCourse(
        courseName: String = "分段课程",
        semesterID: String? = nil,
        teacher: String,
        weeks: [Int] = Array(1...16),
        room: String = "101",
        dayOfWeek: Int = 1,
        classInfo: String = "林业 1 班",
        location: String = "二教"
    ) -> Course {
        Course(
            courseName: courseName,
            teacher: teacher,
            classInfo: classInfo,
            room: room,
            location: location,
            dayOfWeek: dayOfWeek,
            weeks: weeks,
            duration: [3, 4],
            sourceSemesterID: semesterID ?? self.semesterID
        )
    }

    private func makeRecord(
        teacher: String,
        weeks: [Int],
        courseName: String = "分段课程",
        dayOfWeek: Int = 1,
        classInfo: String = "林业 1 班",
        room: String = "101",
        location: String = "二教"
    ) -> ParsedCourseRecord {
        ParsedCourseRecord(
            courseName: courseName,
            teacher: teacher,
            classInfo: classInfo,
            room: room,
            location: location,
            dayOfWeek: dayOfWeek,
            weeks: weeks,
            duration: [3, 4]
        )
    }

    private func splitRecords() -> [ParsedCourseRecord] {
        [
            makeRecord(teacher: "教师甲", weeks: Array(1...8)),
            makeRecord(teacher: "教师乙", weeks: Array(9...16))
        ]
    }

    private func persistSplit(
        records: [ParsedCourseRecord],
        existingCourses: [Course],
        context: ModelContext,
        save: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> TimetablePersistResult {
        try TimetableRefreshUseCase().persist(
            records: records,
            existingCourses: existingCourses,
            modelContext: context,
            semesterID: semesterID,
            save: save
        )
    }
}

@MainActor
private final class RecordingTimetableCourseReminderScheduler: TimetableCourseReminderScheduling {
    struct ScheduledCall {
        let courseKey: String
        let teacher: String
        let weeks: [Int]
        let minutesBefore: Int
        let anchorPeriod: Int?
    }

    enum SchedulerError: Error {
        case injected
    }

    var cancelCalls: [[String]] = []
    var scheduleCalls: [ScheduledCall] = []
    var events: [String] = []
    var failuresRemaining: Int

    init(failuresRemaining: Int = 0) {
        self.failuresRemaining = failuresRemaining
    }

    func cancel(identifiers: [String]) {
        events.append("cancel")
        cancelCalls.append(identifiers)
    }

    func schedule(course: Course, minutesBefore: Int, anchorPeriod: Int?) async throws {
        events.append("schedule")
        scheduleCalls.append(ScheduledCall(
            courseKey: course.stableCourseKey,
            teacher: course.teacher,
            weeks: course.weeks,
            minutesBefore: minutesBefore,
            anchorPeriod: anchorPeriod
        ))
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw SchedulerError.injected
        }
    }
}

private enum InjectedSaveError: Error {
    case failure
}
