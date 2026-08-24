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
            .filter { $0.sourceSemesterID == semesterID }
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
        try await Task.detached(priority: .userInitiated) {
            try HTMLParser.parseTimetableResult(html: html).records
        }.value
    }

    @MainActor
    @discardableResult
    func persist(
        records: [ParsedCourseRecord],
        existingCourses: [Course],
        modelContext: ModelContext,
        semesterID: String = SemesterConfig.currentSemesterID
    ) throws -> [Course] {
        for course in existingCourses where course.sourceSemesterID == semesterID {
            modelContext.delete(course)
        }

        let newCourses = records.map { $0.makeCourse(semesterID: semesterID) }
        for course in newCourses {
            modelContext.insert(course)
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        return newCourses
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
