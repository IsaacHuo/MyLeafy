import XCTest
@testable import Leafy

final class SchoolDataRefreshTests: XCTestCase {
    override func tearDown() {
        SchoolDataCache.clearDiscoverCaches()
        CampusIdentityStore.clear()
        super.tearDown()
    }

    func testRefreshEventMatchesExplicitAndAllScopes() {
        let event = SchoolDataRefreshEvent([.grades, .exams])

        XCTAssertTrue(event.contains(.grades))
        XCTAssertTrue(event.contains(.exams))
        XCTAssertFalse(event.contains(.teachingPlan))
        XCTAssertTrue(SchoolDataRefreshEvent(.all).contains(.trainingProgram))
    }

    @MainActor
    func testRefreshNotifierIgnoresEmptyScopes() {
        activateTemporaryIdentity()
        let events = observeSchoolDataRefreshEvents {
            SchoolDataRefreshNotifier.post([])
        }

        XCTAssertTrue(events.isEmpty)
    }

    @MainActor
    func testCacheSavesPublishUnifiedRefreshEventsAndUpdateCaches() throws {
        activateTemporaryIdentity()
        let events = observeSchoolDataRefreshEvents {
            SchoolDataCache.saveExamSchedule([sampleExam()])
            SchoolDataCache.saveTeachingPlan([sampleTeachingPlan()])
            SchoolDataCache.saveGradeRankings([sampleGradeRanking()])
            SchoolDataCache.saveGradeCreditSummary(sampleCreditSummary())
            SchoolDataCache.saveTrainingProgram(sampleTrainingProgram())
        }

        XCTAssertEqual(events.count, 5)
        XCTAssertTrue(events[0].contains(.exams))
        XCTAssertTrue(events[1].contains(.teachingPlan))
        XCTAssertTrue(events[2].contains(.gradeSupplemental))
        XCTAssertTrue(events[3].contains(.gradeSupplemental))
        XCTAssertTrue(events[4].contains(.trainingProgram))
        XCTAssertEqual(SchoolDataCache.loadExamSchedule().map(\.name), ["高等数学期末"])
        XCTAssertEqual(SchoolDataCache.loadTeachingPlan().map(\.term), ["2025-2026-2"])
        XCTAssertEqual(SchoolDataCache.loadGradeRankings().map(\.term), ["全部学期"])
        XCTAssertEqual(SchoolDataCache.loadGradeCreditSummary()?.totalCredits, 42)
        XCTAssertEqual(SchoolDataCache.loadTrainingProgram()?.title, "培养方案")
        XCTAssertEqual(SchoolDataCache.loadGraduationRequirements().map(\.category), ["总学分"])
    }

    @MainActor
    func testSilentCacheSavesUpdateCachesWithoutPublishingRefreshEvents() {
        activateTemporaryIdentity()
        let events = observeSchoolDataRefreshEvents {
            SchoolDataCache.saveExamSchedule([sampleExam()], notifies: false)
            SchoolDataCache.saveTeachingPlan([sampleTeachingPlan()], notifies: false)
            SchoolDataCache.saveGradeRankings([sampleGradeRanking()], notifies: false)
            SchoolDataCache.saveGradeCreditSummary(sampleCreditSummary(), notifies: false)
            SchoolDataCache.saveTrainingProgram(sampleTrainingProgram(), notifies: false)
            SchoolDataCache.markGradeDetailsSynced(at: Date(timeIntervalSince1970: 42))
        }

        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(SchoolDataCache.loadExamSchedule().count, 1)
        XCTAssertEqual(SchoolDataCache.loadTeachingPlan().count, 1)
        XCTAssertEqual(SchoolDataCache.loadGradeRankings().count, 1)
        XCTAssertNotNil(SchoolDataCache.loadGradeCreditSummary())
        XCTAssertNotNil(SchoolDataCache.loadTrainingProgram())
        XCTAssertEqual(SchoolDataCache.lastSyncDate(for: .gradeDetails), Date(timeIntervalSince1970: 42))
    }

    @MainActor
    func testLiveTimetableRepositoryResolvesActiveCampusContextManager() {
        activateTemporaryIdentity()
        XCTAssertTrue(LiveSchoolTimetableRepository.activeManagerForRefresh() === ActiveCampusContext.networkManager)
    }

    private func observeSchoolDataRefreshEvents(_ action: () -> Void) -> [SchoolDataRefreshEvent] {
        var events: [SchoolDataRefreshEvent] = []
        let observer = NotificationCenter.default.addObserver(
            forName: .schoolDataDidRefresh,
            object: nil,
            queue: nil
        ) { notification in
            guard let event = notification.object as? SchoolDataRefreshEvent else { return }
            events.append(event)
        }
        action()
        NotificationCenter.default.removeObserver(observer)
        return events
    }

    private func activateTemporaryIdentity() {
        CampusIdentityStore.activate(
            CampusIdentity(
                campusID: .bjfu,
                eduID: "refresh-test-\(UUID().uuidString)",
                displayName: "Refresh Test",
                portal: .undergraduate
            )
        )
    }

    private func sampleExam() -> ExamArrangement {
        ExamArrangement(
            id: 1001,
            courseID: "MATH101",
            name: "高等数学期末",
            date: futureDateString(),
            start: "08:00",
            end: "10:00",
            location: "二教 101"
        )
    }

    private func sampleTeachingPlan() -> TeachingPlanSection {
        TeachingPlanSection(
            term: "2025-2026-2",
            courses: [
                TeachingPlanCourse(
                    id: 1,
                    period: "2025-2026-2",
                    name: "高等数学",
                    unit: "理学院",
                    credit: 4,
                    duration: "64",
                    type: "必修",
                    exam: "考试"
                )
            ]
        )
    }

    private func sampleGradeRanking() -> GradeRankingRecord {
        GradeRankingRecord(
            term: "全部学期",
            rankingRange: "专业",
            rank: 3,
            totalCount: 120,
            percentile: 0.025,
            metricText: "平均学分绩点",
            rawFields: ["记录类型": "总排名"]
        )
    }

    private func sampleCreditSummary() -> GradeCreditSummary {
        GradeCreditSummary(
            totalCredits: 42,
            requiredCredits: 36,
            professionalElectiveCredits: 4,
            professionalMajorElectiveCredits: 4,
            professionalCrossMajorElectiveCredits: 0,
            publicElectiveCredits: 2,
            officialGPA: 3.8,
            officialWeightedAverage: 91,
            officialCreditPoint: 159.6,
            publicElectiveBuckets: [GradeCreditBucket(name: "艺术审美", credits: 2)],
            rawFields: ["来源": "测试"]
        )
    }

    private func sampleTrainingProgram() -> TrainingProgramDocument {
        TrainingProgramDocument(
            title: "培养方案",
            sections: [
                TrainingProgramSection(
                    id: "overview",
                    title: "培养目标",
                    body: "测试培养目标"
                )
            ],
            creditRequirements: [
                GraduationCreditRequirement(
                    id: "total",
                    category: "总学分",
                    courseName: "",
                    requiredCredits: 160,
                    plannedCredits: 160,
                    isAggregate: true
                )
            ]
        )
    }

    private func futureDateString() -> String {
        let date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        return DateFormatters.queryDate.string(from: date)
    }
}
