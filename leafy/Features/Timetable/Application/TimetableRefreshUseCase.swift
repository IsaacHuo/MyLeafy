import Foundation
import SwiftData

struct TimetableRefreshResult {
    let adjustedWeek: Int?
    let sharedCourses: [SharedTimetableCourse]
}

struct TimetableRefreshSummary: Equatable {
    let courseCount: Int
    let scheduleCount: Int
    let hasChanges: Bool

    @MainActor
    static func compare(
        records: [ParsedCourseRecord],
        existingCourses: [Course],
        semesterID: String
    ) -> TimetableRefreshSummary {
        let incomingSignatures = records.map(TimetableCourseContentSignature.init(record:))
        let existingSignatures = existingCourses
            .map(TimetableCourseContentSignature.init(course:))

        return TimetableRefreshSummary(
            courseCount: Set(records.map(\.courseName)).count,
            scheduleCount: records.count,
            hasChanges: signatureCounts(incomingSignatures) != signatureCounts(existingSignatures)
        )
    }

    private static func signatureCounts(
        _ signatures: [TimetableCourseContentSignature]
    ) -> [TimetableCourseContentSignature: Int] {
        Dictionary(grouping: signatures, by: { $0 }).mapValues(\.count)
    }
}

private struct TimetableCourseContentSignature: Hashable {
    let courseName: String
    let teacher: String
    let classInfo: String
    let room: String
    let location: String
    let dayOfWeek: Int
    let weeks: [Int]
    let duration: [Int]

    init(record: ParsedCourseRecord) {
        courseName = record.courseName
        teacher = record.teacher
        classInfo = record.classInfo
        room = record.room
        location = record.location
        dayOfWeek = record.dayOfWeek
        weeks = record.weeks.sorted()
        duration = record.duration.sorted()
    }

    @MainActor
    init(course: Course) {
        courseName = course.courseName
        teacher = course.teacher
        classInfo = course.classInfo
        room = course.room
        location = course.location
        dayOfWeek = course.dayOfWeek
        weeks = course.weeks.sorted()
        duration = course.duration.sorted()
    }
}

@MainActor
extension ParsedCourseRecord {
    func makeCourse(semesterID: String) -> Course {
        Course(
            courseName: courseName,
            teacher: teacher,
            classInfo: classInfo,
            room: room,
            location: location,
            dayOfWeek: dayOfWeek,
            weeks: weeks,
            duration: duration,
            sourceSemesterID: semesterID
        )
    }
}

struct TimetableRefreshUseCase {
    let repository: any SchoolTimetableRepository

    init(repository: any SchoolTimetableRepository = LiveSchoolTimetableRepository()) {
        self.repository = repository
    }

    func fetchDocument() async throws -> FetchedTimetableDocument {
        try await repository.fetchTimetableDocument()
    }

    static func parseRecords(html: String) async throws -> [ParsedCourseRecord] {
        try Task.checkCancellation()
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try HTMLParser.parseTimetableResult(html: html).records
        }
        let records = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        try Task.checkCancellation()
        return records
    }

    @MainActor
    @discardableResult
    func persist(
        records: [ParsedCourseRecord],
        existingCourses: [Course],
        modelContext: ModelContext,
        semesterID: String = SemesterConfig.currentSemesterID,
        allowsEmpty: Bool = false,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> TimetablePersistResult {
        guard !records.isEmpty || allowsEmpty else { throw TimetableEmptyResult() }
        let requiredPeriods = records.flatMap(\.duration).max() ?? 1
        if requiredPeriods > TimetablePeriodSchedule.slots.count {
            guard requiredPeriods <= 24 else { throw CocoaError(.fileReadCorruptFile) }
            try TimetablePendingImportStore.save(records: records, semesterID: semesterID)
            throw TimetableConfigurationRequired(periods: requiredPeriods)
        }
        let oldCourses = existingCourses
        let oldIdentifiers = Array(Set(oldCourses.flatMap {
            TimetableNotificationManager.courseReminderIdentifiers(for: $0)
        }))
        let newCourses = records.map { $0.makeCourse(semesterID: semesterID) }
        for group in Dictionary(grouping: newCourses, by: \.stableCourseKey).values {
            for (index, course) in group.enumerated() {
                if group.dropFirst(index + 1).contains(where: {
                    !Set($0.weeks).isDisjoint(with: course.weeks)
                    && ($0.room != course.room || $0.classInfo != course.classInfo)
                }) { throw TimetableLocalDataConflict.ambiguousArrangement(course.courseName) }
            }
        }
        let associations = try TimetableLocalDataReassociation(oldCourses: oldCourses, newCourses: newCourses, context: modelContext)
        let undoPersonalData = try TimetableLocalDataReassociation.personalDataUndo(in: modelContext)
        do {
            try associations.apply(to: modelContext)
            let reminderPlan = try TimetableReminderRefreshPlan(
                oldIdentifiers: oldIdentifiers, courses: newCourses,
                settings: modelContext.fetch(FetchDescriptor<CourseReminderSetting>())
            )
            for course in oldCourses { modelContext.delete(course) }
            for course in newCourses { modelContext.insert(course) }
            try save(modelContext)
            return TimetablePersistResult(courses: newCourses, reminders: reminderPlan)
        } catch {
            for course in newCourses where course.modelContext === modelContext { modelContext.delete(course) }
            for course in oldCourses { modelContext.insert(course) }
            undoPersonalData()
            throw error
        }
    }

    static func nearestAvailableWeek(from parsedCourses: [ParsedCourseRecord], preferredWeek: Int) -> Int? {
        let weeks = Set(parsedCourses.flatMap(\.weeks)).sorted()
        guard !weeks.isEmpty else { return nil }
        if weeks.contains(preferredWeek) { return preferredWeek }

        return weeks.min { lhs, rhs in
            let leftDistance = abs(lhs - preferredWeek)
            let rightDistance = abs(rhs - preferredWeek)
            if leftDistance == rightDistance { return lhs < rhs }
            return leftDistance < rightDistance
        }
    }
}

struct TimetableEmptyResult: LocalizedError {
    var errorDescription: String? { "学校暂未提供有课程的课表，已保留当前课表。可在课表刷新提示中确认清空课程；备注、提醒和个人日程会保留。" }
}
