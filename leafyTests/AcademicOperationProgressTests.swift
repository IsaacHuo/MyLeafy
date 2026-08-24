import XCTest
@testable import Leafy

final class AcademicOperationProgressTests: XCTestCase {
    func testCampusNetworkFailureStopsMultiStepSync() {
        XCTAssertTrue(
            SchoolDataSyncContinuationPolicy.shouldStop(
                after: SchoolNetworkError.campusNetworkRequired
            )
        )
        XCTAssertFalse(
            SchoolDataSyncContinuationPolicy.shouldStop(
                after: SchoolNetworkError.featureUnavailable("页面结构异常")
            )
        )
        XCTAssertFalse(
            SchoolDataSyncContinuationPolicy.shouldStop(
                after: SchoolNetworkError.sessionExpired
            )
        )
    }

    @MainActor
    func testFastProgressUpdatesKeepCompletedHistory() {
        let controller = AcademicOperationProgressController()
        let reporter = controller.reporter(for: .timetable)

        reporter(.begin(.connectingAcademicSystem))
        reporter(.begin(.recognizingCaptcha))
        reporter(.begin(.authenticating))

        XCTAssertEqual(controller.progress?.steps.map(\.stage), [
            .connectingAcademicSystem,
            .recognizingCaptcha,
            .authenticating
        ])
        XCTAssertEqual(controller.progress?.steps[0].status, .completed)
        XCTAssertEqual(controller.progress?.steps[1].status, .completed)
        XCTAssertEqual(controller.progress?.steps[2].status, .running)
    }

    @MainActor
    func testFailureRemainsVisibleWhenLaterStepBegins() {
        let controller = AcademicOperationProgressController()
        let reporter = controller.reporter(for: .teachingAndCultivation)

        reporter(.begin(.fetchingTeachingPlan))
        reporter(.fail(.fetchingTeachingPlan, "页面结构异常"))
        reporter(.begin(.fetchingTrainingProgram))

        XCTAssertEqual(controller.progress?.steps[0].status, .failed("页面结构异常"))
        XCTAssertEqual(controller.progress?.steps[1].status, .running)
    }

    @MainActor
    func testOperationScopeRejectsUnrelatedStages() {
        let controller = AcademicOperationProgressController()
        let reporter = controller.reporter(for: .emptyClassrooms)

        reporter(.begin(.queryingEmptyClassrooms))
        reporter(.begin(.fetchingGrades))

        XCTAssertEqual(controller.progress?.steps.map(\.stage), [.queryingEmptyClassrooms])
        XCTAssertFalse(AcademicOperationKind.emptyClassrooms.allowedStages.contains(.fetchingGrades))
        XCTAssertFalse(AcademicOperationKind.timetable.allowedStages.contains(.fetchingGrades))
        XCTAssertTrue(AcademicOperationKind.allAcademicData.allowedStages.contains(.fetchingGrades))
    }

    @MainActor
    func testGradeRefreshSummaryIgnoresRecordIdentityAndOrder() {
        let existing = [
            Grade(term: "2025-2026-1", courseName: "大学英语", credit: "2.0", score: "88", type: "必修"),
            Grade(term: "2025-2026-1", courseName: "高等数学", credit: "4.0", score: "90", type: "必修")
        ]
        let incoming = [
            Grade(term: "2025-2026-1", courseName: "高等数学", credit: "4.0", score: "90", type: "必修"),
            Grade(term: "2025-2026-1", courseName: "大学英语", credit: "2.0", score: "88", type: "必修")
        ]

        let summary = GradeRefreshSummary.compare(existing: existing, incoming: incoming)

        XCTAssertEqual(summary.gradeCount, 2)
        XCTAssertFalse(summary.hasChanges)
    }

    @MainActor
    func testTeachingCultivationContinuesAfterNonAuthenticationFailure() async {
        let client = FakeTeachingCultivationClient()
        client.teachingPlanError = SchoolNetworkError.featureUnavailable("教学计划页面异常")
        let recorder = ProgressEventRecorder()

        let outcome = await TeachingCultivationRefreshUseCase(networkManager: client).refresh {
            recorder.events.append($0)
        }

        guard case .partial(let message) = outcome else {
            return XCTFail("Expected partial completion")
        }
        XCTAssertEqual(client.teachingPlanFetchCount, 1)
        XCTAssertEqual(client.trainingProgramFetchCount, 1)
        XCTAssertFalse(message.isEmpty)
        XCTAssertTrue(recorder.events.contains(.begin(.fetchingTrainingProgram)))
    }

    @MainActor
    func testTeachingCultivationStopsForReauthentication() async {
        let client = FakeTeachingCultivationClient()
        client.teachingPlanError = SchoolNetworkError.sessionExpired

        let outcome = await TeachingCultivationRefreshUseCase(networkManager: client).refresh()

        guard case .needsReauthentication = outcome else {
            return XCTFail("Expected reauthentication")
        }
        XCTAssertEqual(client.teachingPlanFetchCount, 1)
        XCTAssertEqual(client.trainingProgramFetchCount, 0)
    }

    @MainActor
    func testTeachingCultivationStopsAfterCampusNetworkFailure() async {
        let client = FakeTeachingCultivationClient()
        client.teachingPlanError = SchoolNetworkError.campusNetworkRequired

        let outcome = await TeachingCultivationRefreshUseCase(networkManager: client).refresh()

        guard case .failure(let message) = outcome else {
            return XCTFail("Expected network failure")
        }
        XCTAssertFalse(message.isEmpty)
        XCTAssertEqual(client.teachingPlanFetchCount, 1)
        XCTAssertEqual(client.trainingProgramFetchCount, 0)
    }
}

@MainActor
private final class ProgressEventRecorder {
    var events: [AcademicOperationProgressEvent] = []
}

@MainActor
private final class FakeTeachingCultivationClient: CampusAcademicProviding {
    var teachingPlanError: Error?
    var teachingPlanFetchCount = 0
    var trainingProgramFetchCount = 0

    func fetchExamSchedule() async throws -> String { "" }

    func fetchTeachingPlan() async throws -> String {
        teachingPlanFetchCount += 1
        if let teachingPlanError { throw teachingPlanError }
        return """
        <table id="dataList">
          <tr><th>序号</th><th>开课学期</th><th>课程编号</th><th>课程名称</th><th>开课单位</th><th>学分</th><th>学时</th><th>课程性质</th></tr>
          <tr><td>1</td><td>2026-2027-1</td><td>FOREST-001</td><td>森林生态学</td><td>林学院</td><td>2.0</td><td>32</td><td>专业必修</td></tr>
        </table>
        """
    }

    func fetchGraduationRequirements() async throws -> String {
        trainingProgramFetchCount += 1
        return """
        <html><body>
          <p>林学专业本科培养方案</p>
          <p>一、培养目标</p>
          <p>掌握专业基础知识。</p>
        </body></html>
        """
    }

    func fetchGradeRankings() async throws -> String { "" }
}
