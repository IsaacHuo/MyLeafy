import Foundation
import SwiftData

struct TimetableRefreshResult {
    let adjustedWeek: Int?
    let sharedCourses: [SharedTimetableCourse]
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

    func fetchHTML() async throws -> String {
        try await repository.fetchTimetableHTML()
    }

    static func parseRecords(html: String) async throws -> [ParsedCourseRecord] {
        try await Task.detached(priority: .userInitiated) {
            try HTMLParser.parseTimetableRecords(html: html)
        }.value
    }

    @MainActor
    func persist(
        records: [ParsedCourseRecord],
        existingCourses: [Course],
        modelContext: ModelContext,
        semesterID: String = SemesterConfig.currentSemesterID
    ) throws {
        for course in existingCourses where course.sourceSemesterID == semesterID {
            modelContext.delete(course)
        }

        for course in records.map({ $0.makeCourse(semesterID: semesterID) }) {
            modelContext.insert(course)
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
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
