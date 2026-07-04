import XCTest
@testable import Leafy

final class GenericCampusLifecycleTests: XCTestCase {
    func testCustomCampusAcademicTabsHideBJFUSpecificSurfaces() {
        let tabs = AcademicPrimaryTab.visibleCases(isCustomCampus: true, isCommunityEnabled: false)

        XCTAssertEqual(tabs, [.cultivation, .schedule, .learning, .sports, .career, .postgraduate])
        XCTAssertFalse(tabs.contains(.classrooms))
        XCTAssertFalse(tabs.contains(.ratings))
        XCTAssertFalse(tabs.contains(.medical))
        XCTAssertFalse(tabs.contains(.weekendTravel))
    }

    func testAcademicTabsIncludeBJFUSpecificSurfacesWhenAvailable() {
        let bjfuWithoutCommunityTabs = AcademicPrimaryTab.visibleCases(
            isCustomCampus: false,
            isCommunityEnabled: false,
            isMedicalEnabled: true
        )
        let bjfuWithCommunityTabs = AcademicPrimaryTab.visibleCases(
            isCustomCampus: false,
            isCommunityEnabled: true,
            isMedicalEnabled: true
        )

        XCTAssertEqual(bjfuWithoutCommunityTabs.count, 9)

        XCTAssertEqual(bjfuWithCommunityTabs.count, 10)
        XCTAssertEqual(bjfuWithCommunityTabs.suffix(3), [.ratings, .medical, .weekendTravel])
    }

    func testCustomCampusRoutesHideBJFUSpecificToolsButKeepLocalLifecycleTools() {
        XCTAssertTrue(CampusAcademicVisibility.isRouteVisible(.grades, isCustomCampus: true, isCommunityEnabled: false))
        XCTAssertTrue(CampusAcademicVisibility.isRouteVisible(.examSchedule, isCustomCampus: true, isCommunityEnabled: false))
        XCTAssertTrue(CampusAcademicVisibility.isRouteVisible(.scheduleReports, isCustomCampus: true, isCommunityEnabled: false))
        XCTAssertTrue(CampusAcademicVisibility.isRouteVisible(.timetableProcessing, isCustomCampus: true, isCommunityEnabled: false))
        XCTAssertTrue(CampusAcademicVisibility.isRouteVisible(.countdowns, isCustomCampus: true, isCommunityEnabled: false))
        XCTAssertTrue(CampusAcademicVisibility.isRouteVisible(.sunshineRun, isCustomCampus: true, isCommunityEnabled: false))
        XCTAssertTrue(CampusAcademicVisibility.isRouteVisible(.fitnessTestRecords, isCustomCampus: true, isCommunityEnabled: false))

        XCTAssertFalse(CampusAcademicVisibility.isRouteVisible(.emptyClassroom, isCustomCampus: true, isCommunityEnabled: false))
        XCTAssertFalse(CampusAcademicVisibility.isRouteVisible(.campusHeatmap, isCustomCampus: true, isCommunityEnabled: false))
        XCTAssertFalse(CampusAcademicVisibility.isRouteVisible(.teachingPlan, isCustomCampus: true, isCommunityEnabled: false))
        XCTAssertFalse(CampusAcademicVisibility.isRouteVisible(.trainingProgram, isCustomCampus: true, isCommunityEnabled: false))
        XCTAssertFalse(CampusAcademicVisibility.isRouteVisible(.sportsVenues, isCustomCampus: true, isCommunityEnabled: false))
        XCTAssertFalse(CampusAcademicVisibility.isRouteVisible(.medicalPolicy, isCustomCampus: true, isCommunityEnabled: false, isMedicalEnabled: true))
        XCTAssertFalse(CampusAcademicVisibility.isRouteVisible(.medicalLedger, isCustomCampus: true, isCommunityEnabled: false, isMedicalEnabled: true))
    }

    func testBJFUWithoutCommunityOnlyHidesRatings() {
        let tabs = AcademicPrimaryTab.visibleCases(isCustomCampus: false, isCommunityEnabled: false, isMedicalEnabled: true)

        XCTAssertTrue(tabs.contains(.cultivation))
        XCTAssertTrue(tabs.contains(.schedule))
        XCTAssertTrue(tabs.contains(.classrooms))
        XCTAssertTrue(tabs.contains(.sports))
        XCTAssertTrue(tabs.contains(.medical))
        XCTAssertTrue(tabs.contains(.weekendTravel))
        XCTAssertFalse(tabs.contains(.ratings))
        XCTAssertFalse(CampusAcademicVisibility.isRouteVisible(.timetableProcessing, isCustomCampus: false, isCommunityEnabled: false))
        XCTAssertTrue(CampusAcademicVisibility.isRouteVisible(.medicalPolicy, isCustomCampus: false, isCommunityEnabled: false, isMedicalEnabled: true))
        XCTAssertTrue(CampusAcademicVisibility.isRouteVisible(.medicalLedger, isCustomCampus: false, isCommunityEnabled: false, isMedicalEnabled: true))
    }

    func testWeekendTravelTabOnlyAppearsForBJFUCampus() {
        let bjfuTabs = AcademicPrimaryTab.visibleCases(
            isCustomCampus: false,
            isCommunityEnabled: true,
            isMedicalEnabled: true,
            campusID: .bjfu
        )
        let customTabs = AcademicPrimaryTab.visibleCases(
            isCustomCampus: true,
            isCommunityEnabled: false,
            campusID: .custom
        )
        let otherCampusTabs = AcademicPrimaryTab.visibleCases(
            isCustomCampus: false,
            isCommunityEnabled: true,
            isMedicalEnabled: true,
            campusID: CampusID(rawValue: "other")
        )

        XCTAssertTrue(bjfuTabs.contains(.weekendTravel))
        XCTAssertFalse(customTabs.contains(.weekendTravel))
        XCTAssertFalse(otherCampusTabs.contains(.weekendTravel))
    }

    func testWeekendDestinationCatalogMatchesSupportedCities() {
        let cityNames = Set(WeekendTravelRecommendationEngine.destinations.map(\.cityName))

        XCTAssertEqual(
            cityNames,
            Set([
                "天津", "沧州", "石家庄（正定）", "唐山", "保定", "张家口", "承德",
                "太原", "秦皇岛", "青岛", "大同", "济南", "平遥"
            ])
        )
    }

    func testWeekendRecommendationsReturnEveryDestination() {
        let summerTrips = WeekendTravelRecommendationEngine.recommend(currentMonth: 6)
        let catalogIDs = Set(WeekendTravelRecommendationEngine.destinations.map(\.id))
        let recommendationIDs = Set(summerTrips.map(\.id))

        XCTAssertEqual(summerTrips.count, WeekendTravelRecommendationEngine.destinations.count)
        XCTAssertEqual(recommendationIDs.count, summerTrips.count)
        XCTAssertEqual(recommendationIDs, catalogIDs)
        XCTAssertTrue(summerTrips.contains { $0.cityName == "青岛" })
    }

    func testQingdaoIsSouthernmostWeekendDestination() throws {
        let destinations = WeekendTravelRecommendationEngine.destinations
        let qingdao = try XCTUnwrap(destinations.first { $0.cityName == "青岛" })

        XCTAssertTrue(
            destinations.allSatisfy {
                $0.coordinate.latitude >= qingdao.coordinate.latitude
            }
        )
    }

    func testWeekendDestinationPresentationStringsStayCompact() {
        let shortDestination = WeekendDestination(
            id: "short",
            cityName: "天津",
            tagline: "测试",
            coordinate: CampusCoordinate(latitude: 39.0842, longitude: 117.2009),
            distanceKilometers: 120,
            travelTimeHours: 1.5,
            recommendedDays: 2...3,
            bestMonths: [1, 2, 6],
            estimatedBudgetYuan: 300...700,
            highlights: ["海河", "五大道", "古文化街", "津湾", "南市", "北安桥"],
        )

        let longDestination = WeekendDestination(
            id: "long",
            cityName: "张家口",
            tagline: "测试",
            coordinate: CampusCoordinate(latitude: 40.824, longitude: 114.885),
            distanceKilometers: 220,
            travelTimeHours: 2.5,
            recommendedDays: 2...3,
            bestMonths: [1, 2, 6],
            estimatedBudgetYuan: 450...900,
            highlights: ["草原天路东线", "崇礼奥林匹克公园", "大境门历史街区", "张北草原音乐节", "太舞滑雪小镇", "康保草原"],
        )

        XCTAssertEqual(shortDestination.seasonText, "1/2/6")
        XCTAssertEqual(shortDestination.highlightRail.count, 5)
        XCTAssertEqual(longDestination.highlightRail.count, 4)
    }

    func testAcademicRoutesMatchCultivationAndScheduleInformationArchitecture() {
        XCTAssertEqual(AcademicDetailRoute.grades.tab, .cultivation)
        XCTAssertEqual(AcademicDetailRoute.comprehensiveQuality.tab, .cultivation)
        XCTAssertEqual(AcademicDetailRoute.teachingPlan.tab, .cultivation)
        XCTAssertEqual(AcademicDetailRoute.trainingProgram.tab, .cultivation)
        XCTAssertEqual(AcademicDetailRoute.examSchedule.tab, .schedule)
        XCTAssertEqual(AcademicDetailRoute.scheduleReports.tab, .schedule)
        XCTAssertEqual(AcademicDetailRoute.timetableProcessing.tab, .schedule)
        XCTAssertEqual(AcademicDetailRoute.countdowns.tab, .schedule)
        XCTAssertEqual(AcademicDetailRoute.customCountdowns.tab, .schedule)
        XCTAssertEqual(AcademicDetailRoute.schoolCalendar.tab, .schedule)
        XCTAssertEqual(AcademicDetailRoute.medicalPolicy.tab, .medical)
        XCTAssertEqual(AcademicDetailRoute.medicalLedger.tab, .medical)
        XCTAssertEqual(
            AcademicPrimaryTab.allCases,
            [.cultivation, .schedule, .classrooms, .learning, .sports, .career, .postgraduate, .ratings, .medical, .weekendTravel]
        )
    }

    func testManualExamCanProjectIntoTimetableSchedule() throws {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let examDate = Calendar.current.date(byAdding: .day, value: 7, to: SemesterConfig.startOfSemesterDate) ?? Date()
        let exam = ExamArrangement(
            id: 42,
            courseID: "",
            name: "线性代数期末",
            date: formatter.string(from: examDate),
            start: "08:00",
            end: "10:00",
            location: "A101"
        )

        let projection = try XCTUnwrap(exam.timetableProjection)
        XCTAssertEqual(projection.name, "线性代数期末")
        XCTAssertEqual(projection.location, "A101")
    }
}
