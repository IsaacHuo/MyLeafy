import XCTest
@testable import Leafy

final class ScrollHeaderVisibilityTests: XCTestCase {
    private func sample(_ offset: CGFloat, user: Bool = true, maximum: CGFloat = 200) -> LeafyVerticalScrollSample {
        .init(offset: offset, maximumOffset: maximum, isUserDriven: user)
    }

    func testThresholdAndReverseDirection() {
        var state = LeafyScrollHeaderState()
        state.update(sample(0))
        state.update(sample(8))
        XCTAssertTrue(state.isVisible)
        state.update(sample(12))
        XCTAssertFalse(state.isVisible)
        state.update(sample(30))
        state.update(sample(24))
        XCTAssertFalse(state.isVisible)
        state.update(sample(18))
        XCTAssertTrue(state.isVisible)
    }

    func testSmallReversalsDoNotAccumulateIntoFalseDirection() {
        var state = LeafyScrollHeaderState()
        state.update(sample(0))
        for offset in [8, 5, 11, 8, 14, 11] { state.update(sample(CGFloat(offset))) }
        XCTAssertTrue(state.isVisible)
    }

    func testProgrammaticChangesReseedWithoutHiding() {
        var state = LeafyScrollHeaderState()
        state.update(sample(0))
        state.update(sample(80, user: false))
        XCTAssertTrue(state.isVisible)
        state.update(sample(88))
        XCTAssertTrue(state.isVisible)
        state.update(sample(92))
        XCTAssertFalse(state.isVisible)
    }

    func testLayoutChangesDoNotActAsUserDirection() {
        var state = LeafyScrollHeaderState()
        state.update(sample(20, user: false))
        state.update(sample(80, maximum: 400))
        XCTAssertTrue(state.isVisible)
        state.update(sample(92, maximum: 400))
        XCTAssertFalse(state.isVisible)
    }

    func testBounceTopAndUnscrollableContent() {
        var state = LeafyScrollHeaderState()
        state.update(sample(0))
        state.update(sample(200))
        XCTAssertFalse(state.isVisible)
        state.update(sample(230))
        state.update(sample(206))
        state.update(sample(200))
        XCTAssertFalse(state.isVisible)
        state.update(sample(-8))
        XCTAssertTrue(state.isVisible)
        state.update(sample(40))
        state.update(sample(60))
        XCTAssertFalse(state.isVisible)
        state.update(sample(0, maximum: 0))
        XCTAssertTrue(state.isVisible)
        state.reset()
        XCTAssertTrue(state.isVisible)
    }
}
