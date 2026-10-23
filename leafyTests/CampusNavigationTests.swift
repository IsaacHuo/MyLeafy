import XCTest
@testable import Leafy

@MainActor
final class CampusNavigationTests: XCTestCase {
    func testInitialCampusSelectionAndUnavailableCommunity() {
        let enabled = AppNavigationCoordinator(isCommunityEnabled: true)
        XCTAssertEqual(enabled.selectedRootTab, .timetable)
        XCTAssertEqual(enabled.selectedCampusSection, .community)

        let disabled = AppNavigationCoordinator(isCommunityEnabled: false)
        XCTAssertEqual(disabled.selectedCampusSection, .schedule)
        enabled.openCampusCommunity()
        enabled.sanitizeCampusSection(isCommunityEnabled: false)
        XCTAssertEqual(enabled.selectedRootTab, .academics)
        XCTAssertEqual(enabled.selectedCampusSection, .schedule)
        XCTAssertFalse(enabled.isCampusCommunityActive)
    }

    func testSidebarOrderPreservesAcademicVisibilityAndFourCharacterLabels() {
        let items = CampusSidebarDestination.visibleCases(
            isCustomCampus: false, isCommunityEnabled: true, isMedicalEnabled: true, campusID: .bjfu
        )
        XCTAssertEqual(
            items,
            [.community, .schedule] + AcademicPrimaryTab.allCases.map(CampusSidebarDestination.academic)
        )
        XCTAssertEqual(items[0].title(language: .zhHans), "校园社区")
        XCTAssertEqual(items[1].title(language: .zhHans), "日迹记录")

        let guest = CampusSidebarDestination.visibleCases(
            isCustomCampus: true, isCommunityEnabled: false, isMedicalEnabled: false, campusID: .guest
        )
        XCTAssertEqual(guest, [.schedule, .academic(.cultivation), .academic(.learning),
                               .academic(.sports), .academic(.career), .academic(.postgraduate)])
    }

    func testCommunitySubscriptionEligibilityFollowsVisibleCampusPane() {
        let coordinator = AppNavigationCoordinator(isCommunityEnabled: true)
        XCTAssertFalse(coordinator.isCampusCommunityActive)
        coordinator.openCampusCommunity()
        XCTAssertTrue(coordinator.isCampusCommunityActive)
        coordinator.openScheduleDestination(.customSchedules)
        XCTAssertFalse(coordinator.isCampusCommunityActive)
        coordinator.openCampusCommunity()
        coordinator.selectedRootTab = .profile
        XCTAssertFalse(coordinator.isCampusCommunityActive)
        coordinator.selectedRootTab = .academics
        XCTAssertTrue(coordinator.isCampusCommunityActive)
    }

    func testWidgetJournalAndPostDeepLinksSelectTheirCampusPane() throws {
        let coordinator = AppNavigationCoordinator(isCommunityEnabled: true)
        coordinator.handle(url: try XCTUnwrap(URL(string: "leafy://schedules")))
        XCTAssertEqual(coordinator.selectedRootTab, .academics)
        XCTAssertEqual(coordinator.selectedCampusSection, .schedule)
        XCTAssertEqual(coordinator.requestedScheduleDestination, .customSchedules)
        coordinator.requestedScheduleDestination = nil
        coordinator.handle(url: try XCTUnwrap(URL(string: "leafy://schedule-reports")))
        XCTAssertEqual(coordinator.selectedCampusSection, .schedule)
        XCTAssertEqual(coordinator.requestedScheduleDestination, .scheduleReports)

        let postID = UUID()
        coordinator.handle(url: try XCTUnwrap(URL(string: "https://myleafy.space/share/community/post/\(postID)")))
        XCTAssertEqual(coordinator.selectedRootTab, .academics)
        XCTAssertEqual(coordinator.selectedCampusSection, .community)
        XCTAssertEqual(coordinator.requestedCommunityPostID, postID)
    }

    func testAcademicDeepLinkOverridesRetainedCommunitySelection() async {
        let coordinator = AppNavigationCoordinator(isCommunityEnabled: true)
        coordinator.openAcademicDetailRoute(.grades)
        XCTAssertEqual(coordinator.selectedCampusSection, .academics)
        XCTAssertEqual(coordinator.selectedRootTab, .academics)
        XCTAssertEqual(coordinator.selectedAcademicTab, .cultivation)
        for _ in 0 ..< 10 { await Task.yield() }
        XCTAssertEqual(coordinator.requestedAcademicDetailRoute, .grades)
    }

    func testRootTabRoundTripRetainsCampusAndJournalRequest() {
        let coordinator = AppNavigationCoordinator(isCommunityEnabled: true)
        coordinator.openScheduleDestination(.statistics)
        coordinator.selectedRootTab = .timetable
        coordinator.selectedRootTab = .academics
        XCTAssertEqual(coordinator.selectedCampusSection, .schedule)
        XCTAssertEqual(coordinator.requestedScheduleDestination, .statistics)
    }
}
