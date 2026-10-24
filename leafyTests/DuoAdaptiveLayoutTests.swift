import SwiftUI
import XCTest
@testable import Leafy

final class DuoAdaptiveLayoutTests: XCTestCase {
    func testMasonryKeepsTwoReadableColumnsAndCollapsesNarrowCampusPane() {
        XCTAssertEqual(CommunityMasonrySizing.columnCount(width: 250, spacing: 10, controlScale: 1), 1)
        XCTAssertEqual(CommunityMasonrySizing.columnCount(width: 266, spacing: 10, controlScale: 1), 2)
        XCTAssertEqual(CommunityMasonrySizing.columnCount(width: 760, spacing: 10, controlScale: 1), 2)
        XCTAssertEqual(CommunityMasonrySizing.columnCount(width: 280, spacing: 10, controlScale: 1.1), 1)
    }

    func testComposerReservesItsOuterInsetsInShortWindows() {
        for height: CGFloat in [0, 16, 120, 240, 320, 700] {
            let result = ScheduleMemoComposerSizing.fullscreenHeight(availableHeight: height)
            XCTAssertGreaterThanOrEqual(result, 0)
            XCTAssertLessThanOrEqual(result + 16, max(height, 16))
        }
        XCTAssertFalse(ScheduleMemoComposerSizing.fitsCompactControls(width: 220))
        XCTAssertTrue(ScheduleMemoComposerSizing.fitsCompactControls(width: 280))
    }

    func testScrollResizePreservesVisiblePeriodAndRejectsInvalidGeometry() {
        XCTAssertEqual(TimetableScrollGeometry.rebasedVerticalOffset(120, previousPitch: 30, newPitch: 50), 200)
        XCTAssertEqual(TimetableScrollGeometry.rebasedVerticalOffset(-10, previousPitch: 30, newPitch: 50), 0)
        XCTAssertEqual(TimetableScrollGeometry.rebasedVerticalOffset(120, previousPitch: 0, newPitch: 50), 0)
        XCTAssertEqual(TimetableScrollGeometry.rebasedVerticalOffset(.nan, previousPitch: 30, newPitch: 50), 0)
    }

    @MainActor
    func testResizeDuringDragKeepsNearestWeekAndRejectsOldGestureUpdates() {
        let controller = makeController()
        controller.verticalOffset = 130
        XCTAssertTrue(controller.beginPaging(viewportWidth: 390))
        controller.updatePaging(translation: -240)
        controller.resizeViewport()
        XCTAssertEqual(controller.weekStartDate, date(14))
        XCTAssertEqual(controller.verticalOffset, 130)
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertEqual(controller.horizontalOffset, 0)
        XCTAssertFalse(controller.beginPaging(viewportWidth: 760))
        controller.updatePaging(translation: -300)
        XCTAssertEqual(controller.horizontalOffset, 0)
        controller.endPaging(predictedTranslation: -390, velocity: 0, viewportWidth: 760, reducesMotion: true)
        XCTAssertTrue(controller.beginPaging(viewportWidth: 760))
        controller.cancelPaging(reducesMotion: true)
    }

    @MainActor
    func testResizeDuringSettlementStopsOldDisplayLinkAndKeepsClosestPage() {
        let controller = makeController()
        controller.beginPaging(viewportWidth: 390)
        controller.updatePaging(translation: -100)
        controller.endPaging(predictedTranslation: -390, velocity: 0, viewportWidth: 390, reducesMotion: false)
        controller.resizeViewport()
        let revision = controller.windowRevision
        controller.advanceAnimation(by: 1.0 / 30)
        XCTAssertEqual(controller.weekStartDate, date(7))
        XCTAssertEqual(controller.horizontalOffset, 0)
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertEqual(controller.windowRevision, revision)
    }

    @MainActor
    func testResizePreservesPendingZoomTargetAndCenteredDate() {
        let controller = makeController()
        let center = controller.centerDate
        controller.setZoomTarget(1, centersToday: false, reducesMotion: false)
        controller.resizeViewport()
        controller.advanceAnimation(by: 1.0 / 30)
        XCTAssertEqual(controller.zoomProgress, 1)
        XCTAssertEqual(controller.centerDate, center)
        XCTAssertEqual(controller.phase, .idle)
    }

    @MainActor
    func testResizeDuringPinchIgnoresOldMagnificationUntilCancellation() {
        let controller = makeController()
        controller.beginMagnification(centersToday: false)
        controller.updateMagnification(1.7)
        controller.resizeViewport()
        controller.beginMagnification(centersToday: false)
        controller.updateMagnification(1)
        XCTAssertEqual(controller.zoomProgress, 1)
        controller.cancelMagnification()
        controller.beginMagnification(centersToday: false)
        controller.updateMagnification(0.5)
        XCTAssertEqual(controller.zoomProgress, 0)
        controller.cancelMagnification()
    }

    @MainActor
    func testIdleResizeKeepsWeekCenterZoomAndPayloadRevision() {
        let controller = makeController()
        controller.setZoomTarget(1, centersToday: false, reducesMotion: true)
        let center = controller.centerDate
        let revision = controller.windowRevision
        for _ in 0 ..< 5 { controller.resizeViewport() }
        XCTAssertEqual(controller.centerDate, center)
        XCTAssertEqual(controller.weekStartDate, date(7))
        XCTAssertEqual(controller.zoomProgress, 1)
        XCTAssertEqual(controller.windowRevision, revision)
    }

    @MainActor private func makeController() -> TimetableContinuousViewportController {
        TimetableContinuousViewportController(
            weekStartDate: date(7), centerDate: date(8),
            rangeStart: date(1), rangeEnd: date(30), calendar: calendar
        )
    }

    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day))!
    }
}
