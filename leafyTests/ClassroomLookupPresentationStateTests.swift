import XCTest
@testable import Leafy

@MainActor
final class ClassroomLookupPresentationStateTests: XCTestCase {
    private let date = ISO8601DateFormatter().date(from: "2026-09-19T00:00:00Z")!

    func testQueryKeyIgnoresRequestIDAndTimeWithinShanghaiDay() {
        let first = ClassroomLookupRequest(date: date, building: "第二教学楼", room: " 205 ")
        let sameDay = ClassroomLookupRequest(date: date.addingTimeInterval(3600), building: "二教", room: "205")
        XCTAssertNotEqual(first.id, sameDay.id)
        XCTAssertEqual(first.queryKey, sameDay.queryKey)
        let nextShanghaiDay = ClassroomLookupRequest(date: date.addingTimeInterval(16 * 3600), building: "二教", room: "205")
        XCTAssertNotEqual(first.queryKey, nextShanghaiDay.queryKey)
    }

    func testSwitchingFromRoomToPeriodDoesNotReportAnUnqueriedEmptyResult() {
        let room = ClassroomLookupRequest(date: date, building: "二教", room: "205")
        let period = ClassroomLookupRequest(date: date, startPeriod: 1, endPeriod: 2)
        var state = ClassroomLookupPresentationState()
        state.begin(room)
        XCTAssertTrue(state.accept(.success(.init(usage: [.init(period: 1, status: .available)])), for: room, matching: room.queryKey))
        state.finish(room)
        XCTAssertNotNil(state.outcome(for: room.queryKey))
        // Rendering must hide old data even before SwiftUI's onChange runs.
        XCTAssertNil(state.outcome(for: period.queryKey))
        state.updateQuery(to: period.queryKey)
        XCTAssertNil(state.outcome(for: period.queryKey))
        XCTAssertFalse(state.isLoading)
        state.begin(period)
        XCTAssertTrue(state.accept(.success(.init()), for: period, matching: period.queryKey))
        state.finish(period)
        // A successfully queried empty list remains distinguishable from not queried.
        XCTAssertNotNil(state.outcome(for: period.queryKey))
    }

    func testChangingEachRelevantConditionClearsResultsAndErrors() {
        let room = ClassroomLookupRequest(date: date, building: "二教", room: "205")
        let period = ClassroomLookupRequest(date: date, startPeriod: 1, endPeriod: 2)
        let changes: [(ClassroomLookupRequest, ClassroomLookupRequest)] = [
            (room, .init(date: date.addingTimeInterval(86400), building: "二教", room: "205")),
            (room, .init(date: date, building: "一教", room: "205")),
            (room, .init(date: date, building: "二教", room: "206")),
            (period, .init(date: date, startPeriod: 2, endPeriod: 2)),
            (period, .init(date: date, startPeriod: 1, endPeriod: 3)),
            (period, .init(date: date.addingTimeInterval(86400), startPeriod: 1, endPeriod: 2))
        ]
        for (original, changed) in changes {
            var state = ClassroomLookupPresentationState()
            state.begin(original)
            let failed = ClassroomLookupOutcome.fallback(
                data: .init(rooms: [.init(building: "二教", room: "205")]),
                errorMessage: "查询失败", requiresReauthentication: true
            )
            XCTAssertTrue(state.accept(failed, for: original, matching: original.queryKey))
            state.finish(original)
            state.updateQuery(to: changed.queryKey)
            XCTAssertNil(state.outcome(for: changed.queryKey))
            XCTAssertNil(state.outcome(for: original.queryKey))
        }
    }

    func testLateSuccessAndReauthenticationCannotReplaceNewQuery() {
        let old = ClassroomLookupRequest(date: date, startPeriod: 1, endPeriod: 2)
        let new = ClassroomLookupRequest(date: date, startPeriod: 3, endPeriod: 4)
        var state = ClassroomLookupPresentationState()
        state.begin(old)
        state.updateQuery(to: new.queryKey)
        state.begin(new)
        let staleError = ClassroomLookupOutcome.fallback(data: .init(), errorMessage: "登录失效", requiresReauthentication: true)
        XCTAssertFalse(state.accept(staleError, for: old, matching: new.queryKey))
        XCTAssertFalse(state.accept(.success(.init()), for: old, matching: new.queryKey))
        state.finish(old)
        XCTAssertTrue(state.isLoading)
        XCTAssertTrue(state.accept(.success(.init()), for: new, matching: new.queryKey))
        state.finish(new)
        XCTAssertFalse(state.isLoading)
        XCTAssertFalse(state.outcome(for: new.queryKey)!.requiresReauthentication)
    }

    func testReturningToSameConditionsStillRejectsOldRequestAndCleanup() {
        let old = ClassroomLookupRequest(date: date, startPeriod: 1, endPeriod: 2)
        let other = ClassroomLookupRequest(date: date, startPeriod: 3, endPeriod: 4)
        let retry = ClassroomLookupRequest(date: date, startPeriod: 1, endPeriod: 2)
        var state = ClassroomLookupPresentationState()
        state.begin(old)
        state.updateQuery(to: other.queryKey)
        state.updateQuery(to: retry.queryKey)
        state.begin(retry)
        XCTAssertFalse(state.accept(.success(.init()), for: old, matching: retry.queryKey))
        state.finish(old)
        XCTAssertTrue(state.isCurrent(retry, matching: retry.queryKey))
        XCTAssertFalse(state.updateQuery(to: retry.queryKey))
        XCTAssertTrue(state.isLoading)
    }

    func testChangedConditionsBeforeOnChangeAndDismissedViewRejectCompletion() {
        let request = ClassroomLookupRequest(date: date, startPeriod: 1, endPeriod: 2)
        let changed = ClassroomLookupRequest(date: date, startPeriod: 3, endPeriod: 4)
        var state = ClassroomLookupPresentationState()
        state.begin(request)
        XCTAssertFalse(state.accept(.success(.init()), for: request, matching: changed.queryKey))
        state.invalidate()
        XCTAssertFalse(state.accept(.success(.init()), for: request, matching: request.queryKey))
        XCTAssertNil(state.outcome(for: request.queryKey))
    }
}
