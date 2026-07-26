import Foundation

@MainActor
struct GradePresentationSnapshot {
    static let empty = GradePresentationSnapshot(
        signature: GradePresentationSignature(),
        analytics: .empty,
        groupedGrades: [:],
        sortedTerms: [],
        termSummaries: [:]
    )

    let signature: GradePresentationSignature
    let analytics: GradeAnalytics
    let groupedGrades: [String: [Grade]]
    let sortedTerms: [String]
    let termSummaries: [String: GradeTermPresentationSummary]

    static func make(
        grades: [Grade],
        creditSummary: GradeCreditSummary?
    ) -> GradePresentationSnapshot {
        let signature = GradePresentationSignature(grades: grades, creditSummary: creditSummary)
        let groupedGrades = Dictionary(grouping: grades, by: { $0.term })
        let termSummaries = groupedGrades.mapValues {
            GradeTermPresentationSummary.make(grades: $0)
        }
        return GradePresentationSnapshot(
            signature: signature,
            analytics: GradeAnalytics.calculate(from: grades, creditSummary: creditSummary),
            groupedGrades: groupedGrades,
            sortedTerms: groupedGrades.keys.sorted(by: >),
            termSummaries: termSummaries
        )
    }
}

@MainActor
struct GradeTermPresentationSummary: Equatable {
    let effectiveCourseCount: Int
    let weightedAverage: Double?

    static func make(grades: [Grade]) -> GradeTermPresentationSummary {
        let analytics = GradeAnalytics.calculate(from: grades)
        return GradeTermPresentationSummary(
            effectiveCourseCount: analytics.effectiveCourseCount,
            weightedAverage: analytics.weightedAverage
        )
    }
}

@MainActor
struct GradePresentationSignature: Equatable {
    private let gradeItems: [GradeItem]
    private let creditSummary: GradeCreditSummary?

    init(grades: [Grade] = [], creditSummary: GradeCreditSummary? = nil) {
        gradeItems = grades.map(GradeItem.init(grade:))
        self.creditSummary = creditSummary
    }

    private struct GradeItem: Equatable {
        let id: UUID
        let term: String
        let courseName: String
        let credit: String
        let score: String
        let type: String

        init(grade: Grade) {
            id = grade.id
            term = grade.term
            courseName = grade.courseName
            credit = grade.credit
            score = grade.score
            type = grade.type
        }
    }
}
