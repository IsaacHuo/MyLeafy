import SwiftData
import XCTest
@testable import Leafy

final class ComprehensiveQualityTests: XCTestCase {
    func testOfficialStandardScoreTakesPriorityOverRawScore() {
        let rule = ComprehensiveQualityComponentRule(
            kind: .volunteerService,
            weightPercent: 2,
            detail: ""
        )

        let result = ComprehensiveQualityCalculator.result(
            for: rule,
            input: ComprehensiveQualityComponentInput(
                kind: .volunteerService,
                rawScore: 10,
                peerMaxScore: 100,
                officialStandardScore: 80
            )
        )

        XCTAssertEqual(result.standardScore, 80)
        XCTAssertEqual(result.contribution, 1.6)
        XCTAssertTrue(result.isOfficialStandard)
    }

    func testRawScoreUsesPeerMaxAndBoundsStandardScore() {
        let rule = ComprehensiveQualityComponentRule(
            kind: .researchAchievement,
            weightPercent: 1,
            detail: ""
        )

        let half = ComprehensiveQualityCalculator.result(
            for: rule,
            input: ComprehensiveQualityComponentInput(
                kind: .researchAchievement,
                rawScore: 20,
                peerMaxScore: 40
            )
        )
        let bounded = ComprehensiveQualityCalculator.result(
            for: rule,
            input: ComprehensiveQualityComponentInput(
                kind: .researchAchievement,
                rawScore: 80,
                peerMaxScore: 40
            )
        )

        XCTAssertEqual(half.standardScore, 50)
        XCTAssertEqual(half.contribution, 0.5)
        XCTAssertEqual(bounded.standardScore, 100)
        XCTAssertEqual(bounded.contribution, 1)
    }

    func testEngineeringRuleCalculatesCompositeScoreWhenInputsAreComplete() {
        let rule = ComprehensiveQualityRuleCatalog.rule(for: "工学院")
        let result = ComprehensiveQualityCalculator.calculate(
            rule: rule,
            academicStandardScore: 90,
            inputs: ComprehensiveQualityComponentKind.allCases.map {
                ComprehensiveQualityComponentInput(kind: $0, officialStandardScore: 100)
            }
        )

        XCTAssertEqual(rule.status, .ready)
        XCTAssertEqual(result.qualityContribution, 5)
        XCTAssertEqual(result.compositeScore, 90.5)
        XCTAssertTrue(result.isComplete)
    }

    func testMissingComponentPreventsFinalQualityContribution() {
        let rule = ComprehensiveQualityRuleCatalog.rule(for: "工学院")
        let result = ComprehensiveQualityCalculator.calculate(
            rule: rule,
            academicStandardScore: 90,
            inputs: [
                ComprehensiveQualityComponentInput(kind: .volunteerService, officialStandardScore: 100)
            ]
        )

        XCTAssertNil(result.qualityContribution)
        XCTAssertNil(result.compositeScore)
        XCTAssertFalse(result.isComplete)
    }

    func testAllCatalogRulesAutoCalculate() {
        for rule in ComprehensiveQualityRuleCatalog.allRules {
            let result = ComprehensiveQualityCalculator.calculate(
                rule: rule,
                academicStandardScore: 90,
                inputs: ComprehensiveQualityComponentKind.allCases.map {
                    ComprehensiveQualityComponentInput(kind: $0, officialStandardScore: 100)
                }
            )
            XCTAssertEqual(rule.status, .ready)
            XCTAssertEqual(result.qualityContribution, 5, rule.collegeName)
            XCTAssertEqual(result.compositeScore, 90.5, rule.collegeName)
            XCTAssertTrue(result.isComplete, rule.collegeName)
        }
    }

    func testZeroOfficialStandardScoreCountsAsCompleteInput() {
        let rule = ComprehensiveQualityRuleCatalog.rule(for: "园林学院")
        let result = ComprehensiveQualityCalculator.calculate(
            rule: rule,
            academicStandardScore: 90,
            inputs: ComprehensiveQualityComponentKind.allCases.map {
                ComprehensiveQualityComponentInput(kind: $0, officialStandardScore: 0)
            }
        )

        XCTAssertEqual(rule.status, .ready)
        XCTAssertEqual(result.qualityContribution, 0)
        XCTAssertEqual(result.compositeScore, 85.5)
        XCTAssertTrue(result.isComplete)
    }

    func testCatalogCoversBJFUCollegesAndExcludesNonParticipatingColleges() {
        XCTAssertEqual(ComprehensiveQualityRuleCatalog.participatingCollegeNames.count, 16)
        XCTAssertEqual(ComprehensiveQualityRuleCatalog.allRules.count, 16)
        XCTAssertTrue(ComprehensiveQualityRuleCatalog.participatingCollegeNames.contains("工学院"))
        XCTAssertTrue(ComprehensiveQualityRuleCatalog.participatingCollegeNames.contains("园林学院"))
        XCTAssertTrue(ComprehensiveQualityRuleCatalog.allRules.allSatisfy { $0.status != .needsRuleSource })
        XCTAssertFalse(ComprehensiveQualityRuleCatalog.isSelectableCollege("继续教育学院"))
        XCTAssertFalse(ComprehensiveQualityRuleCatalog.isSelectableCollege("国际学院"))
        XCTAssertEqual(ComprehensiveQualityRuleCatalog.rule(for: "工学院").totalWeightPercent, 5)
        XCTAssertEqual(ComprehensiveQualityRuleCatalog.rule(for: "林学院").status, .ready)
        XCTAssertEqual(ComprehensiveQualityRuleCatalog.rule(for: "经济管理学院").status, .ready)
        XCTAssertEqual(ComprehensiveQualityRuleCatalog.rule(for: "材料科学与技术学院").status, .ready)
        XCTAssertEqual(ComprehensiveQualityRuleCatalog.rule(for: "生态与自然保护学院").status, .ready)
        XCTAssertEqual(ComprehensiveQualityRuleCatalog.rule(for: "园林学院").status, .ready)
        XCTAssertTrue(ComprehensiveQualityRuleCatalog.allRules.allSatisfy { $0.status == .ready })
    }

    func testComprehensiveQualityCSVExportContainsCoreFields() throws {
        let rule = ComprehensiveQualityRuleCatalog.rule(for: "园林学院")
        let result = ComprehensiveQualityCalculator.calculate(
            rule: rule,
            academicStandardScore: 90,
            inputs: ComprehensiveQualityComponentKind.allCases.map {
                ComprehensiveQualityComponentInput(kind: $0, officialStandardScore: 100)
            }
        )
        let summary = ComprehensiveQualityExportSummary(
            collegeName: "园林学院",
            cohort: "2026届",
            rule: rule,
            academicStandardScore: 90,
            componentDrafts: rule.components.map { component in
                ComprehensiveQualityComponentExportSummary(
                    kind: component.kind,
                    weightPercent: component.weightPercent,
                    rawScore: nil,
                    peerMaxScore: nil,
                    officialStandardScore: 100,
                    standardScore: result.componentResults.first { $0.kind == component.kind }?.standardScore,
                    contribution: result.componentResults.first { $0.kind == component.kind }?.contribution,
                    materialReady: component.kind == .volunteerService,
                    evidenceCount: component.kind == .volunteerService ? 1 : 0,
                    note: component.kind == .volunteerService ? "志愿备注" : ""
                )
            },
            qualityContribution: result.qualityContribution,
            compositeScore: result.compositeScore,
            officialQualityScore: 4.8,
            officialCompositeScore: 90.1,
            note: "总备注"
        )

        let data = ComprehensiveQualityExportBuilder.makeCSVData(summary: summary)
        let csv = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(csv.contains("园林学院"))
        XCTAssertTrue(csv.contains("2026届"))
        XCTAssertTrue(csv.contains("学业标准分"))
        XCTAssertTrue(csv.contains("综素贡献"))
        XCTAssertTrue(csv.contains("综合成绩"))
        XCTAssertTrue(csv.contains("志愿服务"))
        XCTAssertTrue(csv.contains("科研成果"))
        XCTAssertTrue(csv.contains("90.50"))
        XCTAssertTrue(csv.contains("志愿备注"))
        XCTAssertTrue(csv.contains("总备注"))
    }

    @MainActor
    func testComprehensiveQualityModelsPersistLocally() throws {
        let schema = Schema([
            ComprehensiveQualityRecord.self,
            ComprehensiveQualityComponentEntry.self,
            ComprehensiveQualityEvidenceDocument.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        context.insert(ComprehensiveQualityRecord(
            collegeName: "工学院",
            academicStandardScore: 90,
            officialQualityScore: 4.5,
            officialCompositeScore: 90
        ))
        context.insert(ComprehensiveQualityComponentEntry(
            collegeName: "工学院",
            componentRawValue: ComprehensiveQualityComponentKind.volunteerService.rawValue,
            rawScore: 10,
            peerMaxScore: 20,
            officialStandardScore: nil,
            materialReady: true,
            note: "志愿服务"
        ))
        context.insert(ComprehensiveQualityEvidenceDocument(
            collegeName: "工学院",
            componentRawValue: ComprehensiveQualityComponentKind.volunteerService.rawValue,
            title: "志愿证明",
            originalFilename: "volunteer.pdf",
            localFilename: "local-volunteer.pdf",
            contentTypeIdentifier: "com.adobe.pdf"
        ))
        try context.save()

        let records = try context.fetch(FetchDescriptor<ComprehensiveQualityRecord>())
        let entries = try context.fetch(FetchDescriptor<ComprehensiveQualityComponentEntry>())
        let documents = try context.fetch(FetchDescriptor<ComprehensiveQualityEvidenceDocument>())

        XCTAssertEqual(records.first?.collegeName, "工学院")
        XCTAssertEqual(records.first?.academicStandardScore, 90)
        XCTAssertEqual(entries.first?.materialReady, true)
        XCTAssertEqual(documents.first?.localFilename, "local-volunteer.pdf")
    }
}
