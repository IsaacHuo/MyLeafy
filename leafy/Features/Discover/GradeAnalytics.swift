import Foundation

struct GradeAnalytics: Hashable {
    struct CoursePerformance: Identifiable, Hashable {
        let id: UUID
        let term: String
        let name: String
        let credit: Double
        let score: Double?
        let rawScore: String
        let type: String
        let isPassed: Bool
        let attemptCount: Int
        let isIncludedInStatistics: Bool

        var impactScore: Double {
            guard let score else { return 0 }
            return abs(score - 80) * credit
        }
    }

    struct TermSummary: Identifiable, Hashable {
        let term: String
        let courses: [CoursePerformance]
        let totalCredits: Double
        let weightedAverage: Double?

        var id: String { term }

        var highestCourse: CoursePerformance? {
            courses
                .filter(\.isIncludedInStatistics)
                .max { ($0.score ?? 0) < ($1.score ?? 0) }
        }

        var lowestCourse: CoursePerformance? {
            courses
                .filter(\.isIncludedInStatistics)
                .min { ($0.score ?? 0) < ($1.score ?? 0) }
        }
    }

    struct CategorySummary: Identifiable, Hashable {
        let name: String
        let credits: Double
        let weightedAverage: Double?
        let courseCount: Int

        var id: String { name }
    }

    struct ScoreDistributionBucket: Identifiable, Hashable {
        let range: String
        let lowerBound: Double
        let upperBound: Double?
        let count: Int
        let credits: Double

        var id: String { range }
    }

    let totalCredits: Double
    let weightedAverage: Double?
    let officialGPA: Double?
    let officialWeightedAverage: Double?
    let officialCreditPoint: Double?
    let medianScore: Double?
    let standardDeviation: Double?
    let riskCourseCount: Int
    let passRate: Double?
    let passedCredits: Double
    let rawRecordCount: Int
    let effectiveCourseCount: Int
    let courses: [CoursePerformance]
    let termSummaries: [TermSummary]
    let categorySummaries: [CategorySummary]
    let scoreDistribution: [ScoreDistributionBucket]

    static let empty = GradeAnalytics(
        totalCredits: 0,
        weightedAverage: nil,
        officialGPA: nil,
        officialWeightedAverage: nil,
        officialCreditPoint: nil,
        medianScore: nil,
        standardDeviation: nil,
        riskCourseCount: 0,
        passRate: nil,
        passedCredits: 0,
        rawRecordCount: 0,
        effectiveCourseCount: 0,
        courses: [],
        termSummaries: [],
        categorySummaries: [],
        scoreDistribution: []
    )

    var displayGPA: Double? {
        officialGPA
    }

    var displayWeightedAverage: Double? {
        officialWeightedAverage ?? weightedAverage
    }

    var gpaSourceText: String {
        officialGPA == nil ? L10n.text("未获取官方值") : L10n.text("学校官方")
    }

    var weightedAverageSourceText: String {
        officialWeightedAverage == nil ? L10n.text("%@ 估算", AppBrand.displayName) : L10n.text("学校官方")
    }

    var currentTerm: TermSummary? {
        termSummaries.first
    }

    var highScoreCourses: [CoursePerformance] {
        courses
            .filter { ($0.score ?? 0) >= 90 }
            .sorted(by: Self.scoreDescending)
    }

    var lowScoreCourses: [CoursePerformance] {
        courses
            .filter { course in
                guard let score = course.score else { return false }
                return score < 70
            }
            .sorted {
                guard let leftScore = $0.score, let rightScore = $1.score else {
                    return Self.scoreDescending($0, $1)
                }
                return leftScore < rightScore
            }
    }

    var highImpactCourses: [CoursePerformance] {
        courses
            .sorted {
                switch ($0.score, $1.score) {
                case let (leftScore?, rightScore?):
                    let leftImpact = abs((leftScore - (weightedAverage ?? leftScore)) * $0.credit)
                    let rightImpact = abs((rightScore - (weightedAverage ?? rightScore)) * $1.credit)
                    if leftImpact != rightImpact { return leftImpact > rightImpact }
                    return Self.scoreDescending($0, $1)
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return Self.metadataAscending($0, $1)
                }
            }
    }

    var requiredCredits: Double {
        credits(matching: "必修")
    }

    var electiveCredits: Double {
        credits(matching: "选修")
    }

    static func calculate(from grades: [Grade], creditSummary: GradeCreditSummary? = nil) -> GradeAnalytics {
        let effectiveCourses = EffectiveGradeCourseResolver.resolve(from: grades)
        let parsedCourses = effectiveCourses.map { course in
            CoursePerformance(
                id: course.recordID,
                term: course.term,
                name: course.name,
                credit: course.credit,
                score: course.score,
                rawScore: course.rawScore,
                type: course.type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? L10n.text("未分类") : course.type,
                isPassed: course.isPassed,
                attemptCount: course.attemptCount,
                isIncludedInStatistics: course.score != nil
            )
        }

        let totalCredits = parsedCourses.reduce(0) { $0 + $1.credit }
        let passedCredits = parsedCourses.filter(\.isPassed).reduce(0) { $0 + $1.credit }
        let weightedAverage = computeWeightedAverage(for: parsedCourses)
        let scores = parsedCourses.compactMap(\.score).sorted()
        let medianScore = computeMedian(scores)
        let standardDeviation = computeStandardDeviation(scores)
        let scoreDistribution = makeScoreDistribution(from: parsedCourses)
        let groupedByTerm = Dictionary(grouping: parsedCourses, by: \.term)
        let termSummaries = groupedByTerm.keys.sorted(by: >).map { term in
            let termCourses = groupedByTerm[term] ?? []
            return TermSummary(
                term: term,
                courses: termCourses.sorted(by: Self.scoreDescending),
                totalCredits: termCourses.reduce(0) { $0 + $1.credit },
                weightedAverage: computeWeightedAverage(for: termCourses)
            )
        }

        let groupedByCategory = Dictionary(grouping: parsedCourses) { course in
            course.type.isEmpty ? L10n.text("未分类") : course.type
        }
        let categorySummaries = groupedByCategory.keys.sorted().map { category in
            let categoryCourses = groupedByCategory[category] ?? []
            return CategorySummary(
                name: category,
                credits: categoryCourses.reduce(0) { $0 + $1.credit },
                weightedAverage: computeWeightedAverage(for: categoryCourses),
                courseCount: categoryCourses.count
            )
        }

        return GradeAnalytics(
            totalCredits: totalCredits,
            weightedAverage: weightedAverage,
            officialGPA: creditSummary?.officialGPA,
            officialWeightedAverage: creditSummary?.officialWeightedAverage,
            officialCreditPoint: creditSummary?.officialCreditPoint,
            medianScore: medianScore,
            standardDeviation: standardDeviation,
            riskCourseCount: parsedCourses.filter { !$0.isPassed }.count,
            passRate: parsedCourses.isEmpty ? nil : Double(parsedCourses.filter(\.isPassed).count) / Double(parsedCourses.count),
            passedCredits: passedCredits,
            rawRecordCount: grades.count,
            effectiveCourseCount: parsedCourses.count,
            courses: parsedCourses,
            termSummaries: termSummaries,
            categorySummaries: categorySummaries,
            scoreDistribution: scoreDistribution
        )
    }

    func credits(matching keyword: String) -> Double {
        courses
            .filter { $0.type.localizedCaseInsensitiveContains(keyword) }
            .reduce(0) { $0 + $1.credit }
    }

    private static func computeWeightedAverage(for courses: [CoursePerformance]) -> Double? {
        let scoredCourses = courses.filter(\.isIncludedInStatistics)
        let credits = scoredCourses.reduce(0) { $0 + $1.credit }
        guard credits > 0 else { return nil }
        return scoredCourses.reduce(0) { $0 + ($1.score ?? 0) * $1.credit } / credits
    }

    private static func computeMedian(_ scores: [Double]) -> Double? {
        guard !scores.isEmpty else { return nil }
        let midpoint = scores.count / 2
        if scores.count.isMultiple(of: 2) {
            return (scores[midpoint - 1] + scores[midpoint]) / 2
        }
        return scores[midpoint]
    }

    private static func computeStandardDeviation(_ scores: [Double]) -> Double? {
        guard scores.count > 1 else { return nil }
        let average = scores.reduce(0, +) / Double(scores.count)
        let variance = scores.reduce(0) { $0 + pow($1 - average, 2) } / Double(scores.count)
        return sqrt(variance)
    }

    private static func makeScoreDistribution(from courses: [CoursePerformance]) -> [ScoreDistributionBucket] {
        let definitions: [(String, Double, Double?)] = [
            ("90+", 90, nil),
            ("80-89", 80, 90),
            ("70-79", 70, 80),
            ("60-69", 60, 70),
            ("<60", 0, 60)
        ]

        return definitions.map { range, lower, upper in
            let bucketCourses = courses.filter { course in
                guard let score = course.score else { return false }
                if let upper {
                    return score >= lower && score < upper
                }
                return score >= lower
            }
            return ScoreDistributionBucket(
                range: range,
                lowerBound: lower,
                upperBound: upper,
                count: bucketCourses.count,
                credits: bucketCourses.reduce(0) { $0 + $1.credit }
            )
        }
    }

    nonisolated private static func scoreDescending(_ lhs: CoursePerformance, _ rhs: CoursePerformance) -> Bool {
        switch (lhs.score, rhs.score) {
        case let (leftScore?, rightScore?):
            if leftScore != rightScore { return leftScore > rightScore }
            return metadataAscending(lhs, rhs)
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return metadataAscending(lhs, rhs)
        }
    }

    nonisolated private static func metadataAscending(_ lhs: CoursePerformance, _ rhs: CoursePerformance) -> Bool {
        if lhs.isPassed != rhs.isPassed {
            return !lhs.isPassed && rhs.isPassed
        }
        if lhs.term != rhs.term {
            return lhs.term > rhs.term
        }
        return lhs.name.localizedCompare(rhs.name) == .orderedAscending
    }

}

enum EffectiveGradeCourseResolver {
    struct Course: Hashable {
        let recordID: UUID
        let term: String
        let name: String
        let credit: Double
        let score: Double?
        let rawScore: String
        let type: String
        let isPassed: Bool
        let attemptCount: Int
    }

    private struct Attempt: Hashable {
        let recordID: UUID
        let courseKey: String
        let term: String
        let name: String
        let credit: Double
        let score: Double?
        let rawScore: String
        let type: String
        let isPassed: Bool
    }

    static func resolve(from grades: [Grade]) -> [Course] {
        let attempts = grades.compactMap { grade in
            makeAttempt(from: grade)
        }
        let groupedAttempts = Dictionary(grouping: attempts, by: \.courseKey)

        return groupedAttempts.values.compactMap { attempts in
            guard let preferred = preferredAttempt(from: attempts) else { return nil }
            return Course(
                recordID: preferred.recordID,
                term: preferred.term,
                name: preferred.name,
                credit: preferred.credit,
                score: preferred.score,
                rawScore: preferred.rawScore,
                type: preferred.type,
                isPassed: preferred.isPassed,
                attemptCount: attempts.count
            )
        }
        .sorted { lhs, rhs in
            if lhs.term != rhs.term {
                return lhs.term > rhs.term
            }
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
    }

    static func numericScore(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Double(trimmed) {
            return value
        }

        if containsFailingText(trimmed) { return nil }
        if trimmed.contains("优秀") { return 95 }
        if trimmed.contains("良好") { return 85 }
        if trimmed.contains("中等") { return 75 }
        return nil
    }

    static func isPassingScore(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !containsFailingText(trimmed) else { return false }
        if let score = numericScore(from: trimmed) {
            return score >= 60
        }
        return containsPassingText(trimmed)
    }

    static func normalizedCourseName(_ name: String) -> String {
        name
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }

    private static func makeAttempt(from grade: Grade) -> Attempt? {
        let rawScore = grade.score.trimmingCharacters(in: .whitespacesAndNewlines)
        let score = numericScore(from: rawScore)
        let isPassed = isPassingScore(rawScore)
        guard let credit = Double(grade.credit.trimmingCharacters(in: .whitespacesAndNewlines)),
              credit > 0,
              !rawScore.isEmpty,
              score != nil || isPassed || containsFailingText(rawScore) else {
            return nil
        }

        let courseKey = [
            normalizedCourseName(grade.courseName),
            String(format: "%.3f", credit)
        ].joined(separator: "|")

        return Attempt(
            recordID: grade.id,
            courseKey: courseKey,
            term: grade.term,
            name: grade.courseName,
            credit: credit,
            score: score,
            rawScore: rawScore,
            type: grade.type,
            isPassed: isPassed
        )
    }

    private static func preferredAttempt(from attempts: [Attempt]) -> Attempt? {
        let passingAttempts = attempts.filter(\.isPassed)
        let candidates = passingAttempts.isEmpty ? attempts : passingAttempts

        return candidates.sorted { lhs, rhs in
            switch (lhs.score, rhs.score) {
            case let (leftScore?, rightScore?):
                if leftScore != rightScore { return leftScore > rightScore }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                break
            }
            if lhs.term != rhs.term {
                return lhs.term > rhs.term
            }
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
        .first
    }

    private static func containsFailingText(_ text: String) -> Bool {
        text.contains("不及格")
            || text.contains("不合格")
            || text.contains("未通过")
            || text.contains("不通过")
    }

    private static func containsPassingText(_ text: String) -> Bool {
        text.contains("及格")
            || text.contains("合格")
            || text.contains("通过")
    }
}
