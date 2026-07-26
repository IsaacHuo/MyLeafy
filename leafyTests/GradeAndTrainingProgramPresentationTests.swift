import XCTest
@testable import Leafy

final class GradeAndTrainingProgramPresentationTests: XCTestCase {
    func testTrainingProgramParserCollectsLinksWithoutRepeatingPureLinkParagraphs() throws {
        let html = """
        <html>
          <body>
            <p>电气工程及其自动化专业本科培养方案</p>
            <p>一、培养目标</p>
            <p>掌握专业基础知识。</p>
            <p><a href="/jsxsd/pyfa/detail?id=1">专业教学计划表</a></p>
            <p>二、培养要求</p>
            <p>详细要求见 <a href="https://jwc.bjfu.edu.cn/document.pdf">学校附件</a>。</p>
            <p><a href="javascript:alert('x')">无效附件</a></p>
          </body>
        </html>
        """

        let document = try HTMLParser.parseTrainingProgram(html: html)

        XCTAssertEqual(document.sections.count, 2)
        XCTAssertEqual(document.sections[0].body, "掌握专业基础知识。")
        XCTAssertEqual(document.sections[0].links.map(\.title), ["专业教学计划表"])
        XCTAssertEqual(
            document.sections[0].links[0]
                .resolvedURL(relativeTo: URL(string: "http://jwc.bjfu.edu.cn")!)?
                .absoluteString,
            "http://jwc.bjfu.edu.cn/jsxsd/pyfa/detail?id=1"
        )

        XCTAssertEqual(document.sections[1].body, "详细要求见 学校附件。")
        XCTAssertEqual(document.sections[1].links.map(\.title), ["学校附件", "无效附件"])
        XCTAssertEqual(
            document.sections[1].links[0]
                .resolvedURL(relativeTo: URL(string: "http://jwc.bjfu.edu.cn")!)?
                .absoluteString,
            "https://jwc.bjfu.edu.cn/document.pdf"
        )
        XCTAssertNil(
            document.sections[1].links[1]
                .resolvedURL(relativeTo: URL(string: "http://jwc.bjfu.edu.cn")!)
        )
    }

    func testTrainingProgramSectionDecodesLegacyCacheWithoutLinks() throws {
        let data = Data(
            #"{"id":"goal","title":"培养目标","body":"掌握专业基础知识。"}"#.utf8
        )

        let section = try JSONDecoder().decode(TrainingProgramSection.self, from: data)

        XCTAssertEqual(section.id, "goal")
        XCTAssertEqual(section.body, "掌握专业基础知识。")
        XCTAssertTrue(section.links.isEmpty)
    }

    @MainActor
    func testTermSummaryUsesEffectiveCoursesAndKeepsTextGrade() throws {
        let grades = [
            Grade(term: "2025-2026-1", courseName: "线性代数 A", credit: "3", score: "48", type: "必修"),
            Grade(term: "2025-2026-1", courseName: "线性代数A", credit: "3", score: "82", type: "必修"),
            Grade(term: "2025-2026-1", courseName: "劳动教育", credit: "1", score: "合格", type: "必修")
        ]

        let summary = GradeTermPresentationSummary.make(grades: grades)
        let analytics = GradeAnalytics.calculate(from: grades)

        XCTAssertEqual(summary.effectiveCourseCount, 2)
        XCTAssertEqual(try XCTUnwrap(summary.weightedAverage), 82, accuracy: 0.001)
        XCTAssertEqual(analytics.rawRecordCount, 3)
        XCTAssertEqual(analytics.courses.first { $0.name.contains("线性代数") }?.attemptCount, 2)
        XCTAssertEqual(analytics.courses.first { $0.name == "劳动教育" }?.rawScore, "合格")
    }

    @MainActor
    func testLowScoreAndImpactSortingUseDocumentedLocalMeaning() {
        let grades = [
            Grade(term: "2025-2026-1", courseName: "低分高学分", credit: "4", score: "55", type: "必修"),
            Grade(term: "2025-2026-1", courseName: "低于均分", credit: "1", score: "70", type: "必修"),
            Grade(term: "2025-2026-1", courseName: "高分高学分", credit: "3", score: "95", type: "必修"),
            Grade(term: "2025-2026-1", courseName: "文字等级", credit: "2", score: "良好", type: "必修"),
            Grade(term: "2025-2026-1", courseName: "文字不及格", credit: "1", score: "不合格", type: "必修")
        ]

        let analytics = GradeAnalytics.calculate(from: grades)

        XCTAssertEqual(
            analytics.lowScoreFirstCourses.prefix(3).map(\.name),
            ["低分高学分", "文字不及格", "低于均分"]
        )
        XCTAssertEqual(
            analytics.highImpactCourses.prefix(3).map(\.name),
            ["低分高学分", "高分高学分", "文字等级"]
        )

        let impacts = analytics.highImpactCourses.compactMap {
            analytics.impactMagnitude(for: $0)
        }
        XCTAssertEqual(impacts, impacts.sorted(by: >))
    }
}
