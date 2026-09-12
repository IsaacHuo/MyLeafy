import XCTest
@testable import Leafy

final class GradeSummaryAndPagingTests: XCTestCase {
    func testAnnotatedGPAUsesVisibleSummaryAndIgnoresOldHTMLComment() throws {
        let summary = try HTMLParser.parseGradeCreditSummary(html: """
        <html><body><div>
        <!-- 平均学分绩点<span>2.41。</span> -->
        <table><tr><th>学分积</th><th>班级排名</th></tr><tr><td>99</td><td>1</td></tr></table>
        在本查询时间段，该生的学分积为76.92。
        <br/>平均学分绩点（GPA）为2.62，算术平均分79.42
        </div></body></html>
        """)
        XCTAssertEqual(summary.officialGPA, 2.62)
        XCTAssertEqual(summary.officialCreditPoint, 76.92)
        XCTAssertNil(summary.officialWeightedAverage)
    }

    func testInlineMarkupAndParenthesisVariantsKeepOfficialGPA() throws {
        for label in ["平均学分绩点（GPA）", "平均学分绩点 ( GPA )", "平均学分绩点(gpa)"] {
            let summary = try HTMLParser.parseGradeCreditSummary(html: """
            <div><span>\(label)</span>为<span>3.17</span>，算术平均分：82.5</div>
            """)
            XCTAssertEqual(summary.officialGPA, 3.17, label)
            XCTAssertNil(summary.officialWeightedAverage)
        }
    }

    func testCommentAndRankingAloneDoNotInventOfficialGPA() {
        XCTAssertThrowsError(try HTMLParser.parseGradeCreditSummary(html: """
        <!-- 平均学分绩点（GPA）为2.41 -->
        <table><tr><th>学年</th><th>学分积</th></tr><tr><td>2025</td><td>3.9</td></tr></table>
        """))
    }

    func testGPAInExactTableLabelValuePair() throws {
        let summary = try HTMLParser.parseGradeCreditSummary(html: """
        <table><tr><td>平均学分绩点（GPA）</td><td>3.42</td></tr></table>
        """)
        XCTAssertEqual(summary.officialGPA, 3.42)
    }

    func testLocallySuppliedGradeDocument() throws {
        guard let path = ProcessInfo.processInfo.environment["LEAFY_GRADE_HTML_PATH"] else {
            throw XCTSkip("Supply a local grade document for attachment verification.")
        }
        let html = try String(contentsOfFile: path, encoding: .utf8)
        let summary = try HTMLParser.parseGradeCreditSummary(html: html)
        XCTAssertEqual(summary.officialGPA, 2.62)
        XCTAssertEqual(summary.officialCreditPoint, 76.92)
        XCTAssertNil(summary.officialWeightedAverage)
    }

    @MainActor
    func testNewDragBeforeHalfwayTakesOffsetOwnershipFromOldAnimation() {
        let controller = makeController()
        controller.beginPaging(viewportWidth: 390)
        controller.updatePaging(translation: -70)
        controller.endPaging(predictedTranslation: -300, velocity: 0, viewportWidth: 390, reducesMotion: false)
        XCTAssertEqual(controller.phase, .pageSettling)
        let revision = controller.windowRevision
        XCTAssertTrue(controller.beginPaging(viewportWidth: 390))
        controller.updatePaging(translation: -40)
        XCTAssertEqual(controller.horizontalOffset, -110, accuracy: 0.001)
        controller.advanceAnimation(by: 1.0 / 60)
        XCTAssertEqual(controller.horizontalOffset, -110, accuracy: 0.001, "The interrupted display link cannot move the new drag")
        XCTAssertEqual(controller.windowRevision, revision)
        controller.endPaging(predictedTranslation: -320, velocity: 0, viewportWidth: 390, reducesMotion: true)
        XCTAssertEqual(controller.weekStartDate, date(14))
        XCTAssertEqual(controller.phase, .idle)
    }

    @MainActor
    func testConsecutiveForwardSwipesPastHalfwayAdvanceTwoWeeks() {
        let controller = makeController()
        controller.beginPaging(viewportWidth: 390)
        controller.updatePaging(translation: -250)
        controller.endPaging(predictedTranslation: -390, velocity: 0, viewportWidth: 390, reducesMotion: false)
        XCTAssertTrue(controller.beginPaging(viewportWidth: 390))
        XCTAssertEqual(controller.weekStartDate, date(14))
        XCTAssertEqual(controller.horizontalOffset, 140, accuracy: 0.001, "Rebasing preserves the visible content position")
        controller.updatePaging(translation: -350)
        controller.endPaging(predictedTranslation: -550, velocity: 0, viewportWidth: 390, reducesMotion: true)
        XCTAssertEqual(controller.weekStartDate, date(21))
        XCTAssertEqual(controller.windowRevision, 2)
    }

    @MainActor
    func testReversingAnUnfinishedSwipeReturnsToThePreviousWeek() {
        let controller = makeController()
        controller.beginPaging(viewportWidth: 390)
        controller.updatePaging(translation: -250)
        controller.endPaging(predictedTranslation: -390, velocity: 0, viewportWidth: 390, reducesMotion: false)
        controller.beginPaging(viewportWidth: 390)
        controller.updatePaging(translation: 160)
        controller.endPaging(predictedTranslation: 350, velocity: 0, viewportWidth: 390, reducesMotion: true)
        XCTAssertEqual(controller.weekStartDate, date(7))
        XCTAssertEqual(controller.horizontalOffset, 0)
    }

    @MainActor
    func testShortDragAndCancelledDragReleasePagingState() {
        let controller = makeController()
        controller.beginPaging(viewportWidth: 390)
        controller.updatePaging(translation: -30)
        controller.endPaging(predictedTranslation: -40, velocity: 0, viewportWidth: 390, reducesMotion: true)
        XCTAssertEqual(controller.weekStartDate, date(7))
        controller.beginPaging(viewportWidth: 390)
        controller.updatePaging(translation: -160)
        controller.cancelPaging(reducesMotion: false)
        settle(controller)
        XCTAssertEqual(controller.weekStartDate, date(7))
        XCTAssertEqual(controller.phase, .idle)
    }

    @MainActor
    func testSettlementHasNoLongSubpixelTailAndCanPageAgain() {
        let controller = makeController()
        controller.beginPaging(viewportWidth: 390)
        controller.updatePaging(translation: -200)
        controller.endPaging(predictedTranslation: -390, velocity: 0, viewportWidth: 390, reducesMotion: false)
        var frames = 0
        while controller.phase == .pageSettling && frames < 120 {
            controller.advanceAnimation(by: 1.0 / 60)
            frames += 1
        }
        XCTAssertLessThan(frames, 60)
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertEqual(controller.weekStartDate, date(14))
        XCTAssertTrue(controller.beginPaging(viewportWidth: 390))
        controller.cancelPaging(reducesMotion: true)
    }

    @MainActor
    func testProgrammaticNavigationStopsOldPagingAndAllowsNewGesture() {
        let controller = makeController()
        controller.beginPaging(viewportWidth: 390)
        controller.updatePaging(translation: -200)
        controller.endPaging(predictedTranslation: -390, velocity: 0, viewportWidth: 390, reducesMotion: false)
        controller.positionOnWeek(date(21), centersToday: false)
        controller.advanceAnimation(by: 1.0 / 60)
        XCTAssertEqual(controller.weekStartDate, date(21))
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertTrue(controller.beginPaging(viewportWidth: 390))
        controller.cancelPaging(reducesMotion: true)
        controller.beginMagnification(centersToday: false)
        controller.updateMagnification(1.3)
        controller.returnToToday(date(9))
        XCTAssertTrue(controller.beginPaging(viewportWidth: 390))
        controller.cancelPaging(reducesMotion: true)
    }

    @MainActor
    func testUnchangedBoundsDoNotInterruptPagingOrRebuildWindow() {
        let controller = makeController()
        controller.beginPaging(viewportWidth: 390)
        controller.updatePaging(translation: -80)
        controller.updateBounds(rangeStart: date(1), rangeEnd: date(30))
        XCTAssertEqual(controller.phase, .paging)
        XCTAssertEqual(controller.horizontalOffset, -80)
        XCTAssertEqual(controller.windowRevision, 0)
        controller.cancelPaging(reducesMotion: true)
    }

    @MainActor
    func testPinchAfterPageRebaseDoesNotUseThePreviousWeeksTodayFlag() {
        let controller = makeController()
        controller.beginPaging(viewportWidth: 390)
        controller.updatePaging(translation: -250)
        controller.endPaging(predictedTranslation: -390, velocity: 0, viewportWidth: 390, reducesMotion: false)
        controller.beginMagnification(centersToday: true, today: date(9))
        XCTAssertEqual(controller.weekStartDate, date(14))
        XCTAssertEqual(controller.centerDate, date(15))
        XCTAssertEqual(controller.horizontalOffset, 0)
        controller.updateMagnification(1.8)
        controller.endMagnification(magnification: 1.8, velocity: 0, reducesMotion: true)
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertTrue(controller.isThreeDay)
    }

    @MainActor
    func testThreeDayInterruptionsAdvanceByThreeDaysAndRespectBounds() {
        let controller = makeController()
        controller.setZoomTarget(1, centersToday: false, reducesMotion: true)
        controller.beginPaging(viewportWidth: 390)
        controller.updatePaging(translation: -250)
        controller.endPaging(predictedTranslation: -390, velocity: 0, viewportWidth: 390, reducesMotion: false)
        controller.beginPaging(viewportWidth: 390)
        controller.updatePaging(translation: -350)
        controller.endPaging(predictedTranslation: -500, velocity: 0, viewportWidth: 390, reducesMotion: true)
        XCTAssertEqual(controller.centerDate, date(14))
        controller.returnToToday(date(30))
        controller.beginPaging(viewportWidth: 390)
        controller.updatePaging(translation: -350)
        controller.endPaging(predictedTranslation: -500, velocity: 0, viewportWidth: 390, reducesMotion: true)
        XCTAssertEqual(controller.centerDate, date(30))
        XCTAssertEqual(controller.phase, .idle)
    }

    @MainActor private func settle(_ controller: TimetableContinuousViewportController) {
        for _ in 0..<120 where controller.phase == .pageSettling { controller.advanceAnimation(by: 1.0 / 60) }
        XCTAssertEqual(controller.phase, .idle)
    }

    @MainActor private func makeController() -> TimetableContinuousViewportController {
        TimetableContinuousViewportController(weekStartDate: date(7), centerDate: date(8), rangeStart: date(1), rangeEnd: date(30), calendar: calendar)
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
