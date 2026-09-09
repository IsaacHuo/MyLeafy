import XCTest
import SwiftData
@testable import Leafy

final class AcademicReliabilityTests: XCTestCase {
    @MainActor
    func testCourseCodeSeparatesRepeatedSubjectsAndGroupsOnlyRealRetakes() {
        let grades = [
            Grade(term: "2025-1", courseName: "体育", credit: "1.6", score: "80", type: "必修", courseCode: "PE-1"),
            Grade(term: "2025-2", courseName: "体育", credit: "1.6", score: "90", type: "必修", courseCode: "PE-2"),
            Grade(term: "2025-1", courseName: "代数", credit: "3", score: "40", type: "必修", courseCode: "MA-1"),
            Grade(term: "2025-2", courseName: "代数", credit: "3", score: "70", type: "必修", courseCode: "MA-1")
        ]
        let result = GradeAnalytics.calculate(from: grades)
        XCTAssertEqual(result.effectiveCourseCount, 3)
        XCTAssertEqual(result.passedCredits, 6.2, accuracy: 0.00001)
        XCTAssertEqual(result.courses.first { $0.name == "代数" }?.attemptCount, 2)
        XCTAssertEqual(result.weightedAverage!, (1.6 * 80 + 1.6 * 90 + 3 * 70) / 6.2, accuracy: 0.00001)
    }

    @MainActor
    func testLegacyCoursesDoNotMergeAcrossTermsAndTextGradesHaveNoInventedScore() {
        let grades = [
            Grade(term: "2025-1", courseName: "体育", credit: "1", score: "良好", type: "必修"),
            Grade(term: "2025-2", courseName: "体育", credit: "1", score: "优秀", type: "必修"),
            Grade(term: "2025-2", courseName: "实践", credit: "0", score: "合格", type: "必修"),
            Grade(term: "2025-2", courseName: "数学", credit: "2", score: "80", type: "必修")
        ]
        let result = GradeAnalytics.calculate(from: grades)
        XCTAssertEqual(result.effectiveCourseCount, 4)
        XCTAssertEqual(result.passedCredits, 4)
        XCTAssertEqual(result.weightedAverage, 80)
        XCTAssertNil(EffectiveGradeCourseResolver.numericScore(from: "优秀"))
        XCTAssertFalse(EffectiveGradeCourseResolver.isPassingScore("不合格"))
        XCTAssertNil(EffectiveGradeCourseResolver.numericScore(from: "nan"))
    }

    @MainActor
    func testGradesReadReorderedColumnsAndPreserveOriginalIdentityFields() throws {
        let grades = try HTMLParser.parseGrades(html: """
        <table><tr><th>成绩</th><th>课程名称</th><th>学分</th><th>开课学期</th><th>课程编号</th><th>考试性质</th><th>课程属性</th><th>课程分类</th></tr>
        <tr><td>合格</td><td>实践</td><td>0</td><td>2025-2</td><td>LAB-4</td><td>补考</td><td>必修</td><td>实践教育</td></tr></table>
        """)
        XCTAssertEqual(grades.count, 1)
        XCTAssertEqual(grades[0].courseCode, "LAB-4")
        XCTAssertEqual(grades[0].courseAttribute, "必修")
        XCTAssertEqual(grades[0].courseCategory, "实践教育")
        XCTAssertEqual(grades[0].examNature, "补考")
        XCTAssertEqual(grades[0].credit, "0")
    }

    func testTeachingPlanReadsMergedTermsAndColumnNames() throws {
        let sections = try HTMLParser.parseTeachingPlan(html: """
        <table><tr><th>课程名称</th><th>课程编号</th><th>学分</th><th>开课学期</th><th>课程属性</th></tr>
        <tr><td>基础课程</td><td>COURSE-1</td><td>2.5</td><td rowspan="2">2025-1</td><td>必修</td></tr>
        <tr><td>实践课程</td><td>COURSE-2</td><td>0</td><td>选修</td></tr></table>
        """)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].courses.map(\.courseCode), ["COURSE-1", "COURSE-2"])
        XCTAssertEqual(sections[0].totalCredits, 2.5)
    }

    func testOfficialCreditsUseMultilevelHeadersAndDynamicElectiveBuckets() throws {
        let summary = try HTMLParser.parseGradeCreditSummary(html: creditSummaryFixture)
        XCTAssertEqual(summary.totalCredits, 102.5)
        XCTAssertEqual(summary.professionalElectiveCredits, 5)
        XCTAssertEqual(summary.professionalMajorElectiveCredits, 2)
        XCTAssertEqual(summary.professionalCrossMajorElectiveCredits, 3)
        XCTAssertEqual(summary.publicElectiveCredits, 7.5)
        XCTAssertEqual(summary.publicElectiveBuckets.map(\.name), ["新增类别", "写作"])
        XCTAssertEqual(summary.publicElectiveBuckets.map(\.credits), [1.5, 6])
        XCTAssertNil(summary.officialGPA)
        XCTAssertNil(summary.officialCreditPoint, "Ranking row index must not become a credit-point value")
        XCTAssertNotNil(summary.syncedAt)
    }

    func testOfficialSummaryOnlyReadsExplicitMetricsAndAcceptsVerifiedZero() throws {
        let html = creditSummaryFixture.replacingOccurrences(of: "102.5", with: "0")
            + "<p>平均绩点：3.45</p><p>加权平均分：81.25</p><p>学分积为82.17</p>"
        let summary = try HTMLParser.parseGradeCreditSummary(html: html)
        XCTAssertTrue(summary.hasCreditTotals)
        XCTAssertEqual(summary.totalCredits, 0)
        XCTAssertEqual(summary.officialGPA, 3.45)
        XCTAssertEqual(summary.officialWeightedAverage, 81.25)
        XCTAssertEqual(summary.officialCreditPoint, 82.17)
    }

    @MainActor
    func testProgramRequirementsComeFromDocumentAndUnknownProgressIsNotZero() throws {
        let document = try HTMLParser.parseTrainingProgram(html: """
        <p>测试专业本科培养方案</p><p>一、毕业要求</p><p>第二课堂不列入总学分。</p>
        <table><tr><td>毕业生应取得总学分</td><td><span>1</span> <span>6</span> <span>7</span></td></tr>
        <tr><td>本专业选修课最低选修学分</td><td>7</td></tr>
        <tr><td>通识选修课学分</td><td>8.5</td></tr>
        <tr><td>跨学科基础课学分</td><td>22.5</td></tr></table>
        """)
        XCTAssertEqual(document.creditRequirements.first { $0.kind == .total }?.requiredCredits, 167)
        XCTAssertTrue(document.creditRequirements.contains { $0.category == "跨学科基础课" && $0.requiredCredits == 22.5 })
        XCTAssertEqual(document.tables?.count, 1)
        XCTAssertTrue(document.sections[0].body.contains("第二课堂"))
        let summary = try HTMLParser.parseGradeCreditSummary(html: creditSummaryFixture)
        let progress = GraduationCreditProgressCalculator.calculate(requirements: document.creditRequirements, grades: [], creditSummary: summary)
        XCTAssertEqual(progress.totalRequiredCredits, 167)
        XCTAssertEqual(progress.totalCompletedCredits, 102.5)
        let professional = try XCTUnwrap(progress.categories.first { $0.kind == .professionalElective })
        XCTAssertEqual(professional.completedCredits, 2, "Cross-major credits cannot satisfy the major requirement")
        XCTAssertEqual(professional.remainingCredits, 5)
        XCTAssertFalse(progress.categories.first { $0.kind == .other }!.hasCompletedCredits)
        XCTAssertNil(progress.categories.first { $0.kind == .other }!.completionRatio)
    }

    @MainActor
    func testExistingGradeStoreAutomaticallyMigratesWithoutLosingRecords() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("grades.store")
        try autoreleasepool {
            let schema = Schema(versionedSchema: OriginalGradeSchema.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let context = ModelContext(container)
            context.insert(OriginalGradeSchema.Grade(term: "2025-1", courseName: "保留的成绩"))
            try context.save()
        }
        let schema = Schema([Grade.self])
        let upgraded = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        let restored = try ModelContext(upgraded).fetch(FetchDescriptor<Grade>())
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored[0].courseName, "保留的成绩")
        XCTAssertEqual(restored[0].score, "88")
        XCTAssertNil(restored[0].courseCode)
    }

    @MainActor
    func testGradeFieldsSurvivePersistenceWithoutRequiringOldRecordsToHaveCodes() throws {
        let schema = Schema([Grade.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        context.insert(Grade(term: "2025-1", courseName: "旧课程", credit: "2", score: "80", type: "必修"))
        context.insert(Grade(term: "2025-2", courseName: "新课程", credit: "3", score: "90", type: "必修", courseCode: "NEW-1", examNature: "正常考试"))
        try context.save()
        let restored = try ModelContext(container).fetch(FetchDescriptor<Grade>())
        XCTAssertEqual(restored.count, 2)
        XCTAssertNil(restored.first { $0.courseName == "旧课程" }!.courseCode)
        XCTAssertEqual(restored.first { $0.courseName == "新课程" }!.courseCode, "NEW-1")
    }
}

private let creditSummaryFixture = """
<table id="dataList"><tr><th rowspan="2">序号</th><th rowspan="2">所得学分</th><th rowspan="2">必修学分</th><th colspan="3">专业选修学分</th><th colspan="3">公共选修课</th></tr>
<tr><th>总计</th><th>本专业</th><th>外专业</th><th>总计</th><th>新增类别</th><th>写作</th></tr>
<tr><td>1</td><td>102.5</td><td>90</td><td>5</td><td>2</td><td>3</td><td>7.5</td><td>1.5</td><td>6</td></tr></table>
<table id="dataList"><tr><th>序号</th><th>学年</th><th>学分积</th><th>班级排名</th><th>专业排名</th></tr><tr><td>1</td><td>2025-2026</td><td>83.5</td><td>2</td><td>3</td></tr></table>
"""

private enum OriginalGradeSchema: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Grade.self] }

    @Model
    final class Grade {
        var id: UUID
        var term: String
        var courseName: String
        var credit: String
        var score: String
        var type: String

        init(term: String, courseName: String) {
            self.id = UUID()
            self.term = term
            self.courseName = courseName
            self.credit = "2"
            self.score = "88"
            self.type = "必修"
        }
    }
}
