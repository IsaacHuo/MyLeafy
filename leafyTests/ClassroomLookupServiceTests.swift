import XCTest
@testable import Leafy

final class ClassroomLookupServiceTests: XCTestCase {
    func testClassroomIdentityNormalizesSecondTeachingBuildingAliases() {
        let selected = ClassroomIdentity(building: "二教", room: "205")
        let official = ClassroomIdentity(building: "第二教学楼", room: " 205 ")
        let buildingSuffix = ClassroomIdentity(building: "二教楼", room: "205")

        XCTAssertTrue(ClassroomIdentity.matches(selected, official))
        XCTAssertTrue(ClassroomIdentity.matches(selected, buildingSuffix))
        XCTAssertFalse(ClassroomIdentity.matches(selected, ClassroomIdentity(building: "三教", room: "205")))
    }

    func testEmptyClassroomParserAcceptsSecondTeachingBuildingAliases() throws {
        let html = """
        <table id="dataList">
          <tr><th>教室</th><th>1</th></tr>
          <tr><th>教室</th><th>2</th></tr>
          <tr><td>第二教学楼205（80/80）</td><td></td></tr>
          <tr><td>二教楼510a(60/60)</td><td></td></tr>
          <tr><td>页脚</td></tr>
          <tr><td>页脚</td></tr>
        </table>
        """

        let rooms = try HTMLParser.parseEmptyClassrooms(html: html)

        XCTAssertEqual(rooms.map(\.identity), [
            ClassroomIdentity(building: "二教", room: "205"),
            ClassroomIdentity(building: "二教", room: "510A")
        ])
    }

    func testEmptyClassroomParserAcceptsReferenceProjectSamples() throws {
        let html = """
        <table id="dataList">
          <tr><th>教室</th><th>0102</th></tr>
          <tr><th>教室</th><th>0304</th></tr>
          <tr><td>A0304(20/10)</td><td></td></tr>
          <tr><td>B0405(20 / 15)</td><td></td></tr>
          <tr><td>二教608(40/13)</td><td></td></tr>
          <tr><td>页脚</td></tr>
          <tr><td>页脚</td></tr>
        </table>
        """

        let rooms = try HTMLParser.parseEmptyClassrooms(html: html)

        XCTAssertEqual(rooms.map(\.identity), [
            ClassroomIdentity(building: "学研A座", room: "0304"),
            ClassroomIdentity(building: "学研B座", room: "0405"),
            ClassroomIdentity(building: "二教", room: "608")
        ])
    }

    func testEmptyClassroomParserSkipsRowsWithOccupiedCells() throws {
        let html = """
        <table id="dataList">
          <tr><th>教室</th><th>0102</th></tr>
          <tr><th>教室</th><th>0304</th></tr>
          <tr><td>二教205(80/80)</td><td></td></tr>
          <tr><td>二教206(80/80)</td><td>*</td></tr>
          <tr><td>页脚</td></tr>
          <tr><td>页脚</td></tr>
        </table>
        """

        let rooms = try HTMLParser.parseEmptyClassrooms(html: html)

        XCTAssertEqual(rooms.map(\.identity), [
            ClassroomIdentity(building: "二教", room: "205")
        ])
    }

    func testDemoModeReturnsSeededRoomsWithoutNetwork() async {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let rooms = [
            EmptyClassroom(building: "二教", room: "205"),
            EmptyClassroom(building: "主楼", room: "112")
        ]
        let calls = ClassroomLookupCallRecorder()
        let service = LiveClassroomLookupService(
            fetchEmptyClassroomsHTML: { _, _, _ in
                await calls.recordRemoteEmptyClassroomFetch()
                return ""
            },
            isDemoModeEnabled: { true },
            demoEmptyClassrooms: { _, _, _ in rooms },
            cache: InMemoryClassroomLookupCache()
        )

        let outcome = await service.lookup(
            ClassroomLookupRequest(date: date, startPeriod: 1, endPeriod: 2),
            userInitiated: true
        )

        XCTAssertEqual(outcome.data.rooms, rooms)
        XCTAssertNil(outcome.errorMessage)
        XCTAssertFalse(outcome.requiresReauthentication)
        let remoteFetchCount = await calls.remoteEmptyClassroomFetches()
        XCTAssertEqual(remoteFetchCount, 0)
    }

    func testRemoteEmptyClassroomSuccessReturnsRoomsAndSavesCache() async {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let rooms = [EmptyClassroom(building: "三教", room: "301")]
        let cache = InMemoryClassroomLookupCache()
        let service = LiveClassroomLookupService(
            fetchEmptyClassroomsHTML: { _, _, _ in "<html></html>" },
            parseEmptyClassrooms: { _ in rooms },
            isDemoModeEnabled: { false },
            cache: cache
        )

        let outcome = await service.lookup(
            ClassroomLookupRequest(date: date, startPeriod: 3, endPeriod: 4),
            userInitiated: true
        )

        XCTAssertEqual(outcome.data.rooms, rooms)
        XCTAssertNil(outcome.errorMessage)
        let cachedRooms = await cache.emptyRooms(date: date, start: 3, end: 4)
        XCTAssertEqual(cachedRooms, rooms)
    }

    func testClassroomLookupCatalogOnlyExposesSupportedBuildings() {
        let rooms = [
            EmptyClassroom(building: "二教", room: "205"),
            EmptyClassroom(building: "一教", room: "101"),
            EmptyClassroom(building: "学研A座", room: "0304"),
            EmptyClassroom(building: "三教", room: "102"),
            EmptyClassroom(building: "基础楼", room: "103")
        ]

        XCTAssertEqual(ClassroomLookupCatalog.buildingOptions.map(\.title), ["二教", "一教", "学研"])
        XCTAssertEqual(ClassroomLookupCatalog.filteredRooms(rooms).map(\.identity), [
            ClassroomIdentity(building: "二教", room: "205"),
            ClassroomIdentity(building: "一教", room: "101"),
            ClassroomIdentity(building: "学研A座", room: "0304")
        ])
        XCTAssertFalse(ClassroomLookupCatalog.contains(building: "三教"))
    }

    func testEmptyClassroomBuildingGroupsSortBuildingsAndRooms() {
        let rooms = [
            EmptyClassroom(building: "三教", room: "302"),
            EmptyClassroom(building: "二教", room: "205"),
            EmptyClassroom(building: "三教", room: "102")
        ]

        let groups = EmptyClassroomBuildingGroup.groups(from: rooms)

        XCTAssertEqual(groups.map(\.building), ["二教", "三教"])
        XCTAssertEqual(groups[0].rooms.map(\.room), ["205"])
        XCTAssertEqual(groups[1].rooms.map(\.room), ["102", "302"])
        XCTAssertEqual(groups[1].countText, "2 间")
    }

    func testEmptyClassroomBuildingGroupsMergeDisplayedBuildings() {
        let rooms = [
            EmptyClassroom(building: "学研B座", room: "0204"),
            EmptyClassroom(building: "二教", room: "205"),
            EmptyClassroom(building: "学研A座", room: "0304")
        ]

        let groups = EmptyClassroomBuildingGroup.groups(
            from: rooms,
            displayBuilding: ClassroomLookupCatalog.displayBuilding(for:)
        )

        XCTAssertEqual(groups.map(\.building), ["二教", "学研"])
        XCTAssertEqual(groups[1].rooms.map(\.identity), [
            ClassroomIdentity(building: "学研A座", room: "0304"),
            ClassroomIdentity(building: "学研B座", room: "0204")
        ])
        XCTAssertEqual(groups[1].countText, "2 间")
    }

    func testEmptyClassroomBuildingGroupsStartCollapsed() {
        let groups = EmptyClassroomBuildingGroup.groups(from: [
            EmptyClassroom(building: "三教", room: "102")
        ])
        let expandedBuildingIDs = Set<String>()

        XCTAssertEqual(groups.map(\.id), ["三教"])
        XCTAssertFalse(expandedBuildingIDs.contains(groups[0].id))
    }

    func testRemoteClassroomUsageSuccessReturnsUsageAndSavesCache() async {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let usage = [
            ClassroomUsageSlot(period: 1, status: .available),
            ClassroomUsageSlot(period: 2, status: .occupied)
        ]
        let cache = InMemoryClassroomLookupCache()
        let service = LiveClassroomLookupService(
            fetchClassroomUsage: { _, _, _ in usage },
            isDemoModeEnabled: { false },
            cache: cache
        )

        let outcome = await service.lookup(
            ClassroomLookupRequest(date: date, building: "二教", room: "205"),
            userInitiated: true
        )

        XCTAssertEqual(outcome.data.usage, usage)
        XCTAssertNil(outcome.errorMessage)
        let cachedUsage = await cache.usage(date: date, building: "二教", room: "205")
        XCTAssertEqual(cachedUsage, usage)
    }

    func testClassroomUsageSlotDecodesLegacyAvailableCache() throws {
        let data = """
        {"period":2,"available":false}
        """.data(using: .utf8)!

        let slot = try JSONDecoder().decode(ClassroomUsageSlot.self, from: data)

        XCTAssertEqual(slot.period, 2)
        XCTAssertEqual(slot.status, .occupied)
        XCTAssertFalse(slot.available)
    }

    func testClassroomUsageStatusResolvesAvailableWhenParsedRoomsContainTarget() {
        let status = ClassroomUsageStatusResolver.status(
            html: "<table id=\"dataList\"><tr><td>二教205(80/80)</td><td></td></tr></table>",
            parsedRooms: [EmptyClassroom(building: "二教", room: "205")],
            target: ClassroomIdentity(building: "二教", room: "205"),
            rawBuilding: "二教",
            rawRoom: "205"
        )

        XCTAssertEqual(status, .available)
    }

    func testClassroomUsageStatusResolvesOccupiedWhenTargetIsAbsent() {
        let status = ClassroomUsageStatusResolver.status(
            html: "<table id=\"dataList\"><tr><td>二教206(80/80)</td><td></td></tr></table>",
            parsedRooms: [EmptyClassroom(building: "二教", room: "206")],
            target: ClassroomIdentity(building: "二教", room: "205"),
            rawBuilding: "二教",
            rawRoom: "205"
        )

        XCTAssertEqual(status, .occupied)
    }

    func testClassroomUsageStatusResolvesOccupiedWhenParsedPageDoesNotListTargetAsEmpty() {
        let status = ClassroomUsageStatusResolver.status(
            html: "<table id=\"dataList\"><tr><td>二教205(80/80)</td><td>课程</td></tr></table>",
            parsedRooms: [],
            target: ClassroomIdentity(building: "二教", room: "205"),
            rawBuilding: "二教",
            rawRoom: "205"
        )

        XCTAssertEqual(status, .occupied)
    }

    func testRemoteFailureFallsBackToCachedDataAndUserFacingError() async {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let cachedRooms = [EmptyClassroom(building: "图书馆", room: "研讨间 3")]
        let cache = InMemoryClassroomLookupCache()
        await cache.saveEmptyClassrooms(cachedRooms, date: date, start: 5, end: 6)
        let service = LiveClassroomLookupService(
            fetchEmptyClassroomsHTML: { _, _, _ in throw ClassroomLookupTestError.remoteFailure },
            isDemoModeEnabled: { false },
            requiresReauthentication: { _ in false },
            cache: cache
        )

        let outcome = await service.lookup(
            ClassroomLookupRequest(date: date, startPeriod: 5, endPeriod: 6),
            userInitiated: true
        )

        XCTAssertEqual(outcome.data.rooms, cachedRooms)
        XCTAssertEqual(outcome.errorMessage, "查询失败：远程查询失败")
        XCTAssertFalse(outcome.requiresReauthentication)
    }

    func testReauthenticationFailureSetsFlagUsedByView() async {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let service = LiveClassroomLookupService(
            fetchClassroomUsage: { _, _, _ in throw ClassroomLookupTestError.remoteFailure },
            isDemoModeEnabled: { false },
            requiresReauthentication: { _ in true },
            cache: InMemoryClassroomLookupCache()
        )

        let outcome = await service.lookup(
            ClassroomLookupRequest(date: date, building: "二教", room: "205"),
            userInitiated: true
        )

        XCTAssertTrue(outcome.data.usage.isEmpty)
        XCTAssertEqual(outcome.errorMessage, "登录状态已失效，请连接校园网后重新登录并继续查询。")
        XCTAssertTrue(outcome.requiresReauthentication)
    }

    func testClassroomLoginPageFailureSetsReauthenticationFlag() async {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let service = LiveClassroomLookupService(
            fetchClassroomUsage: { _, _, _ in
                throw SchoolNetworkError.loginFailed("空教室页面返回了登录页。")
            },
            isDemoModeEnabled: { false },
            cache: InMemoryClassroomLookupCache()
        )

        let outcome = await service.lookup(
            ClassroomLookupRequest(date: date, building: "二教", room: "101"),
            userInitiated: true
        )

        XCTAssertTrue(outcome.data.usage.isEmpty)
        XCTAssertEqual(outcome.errorMessage, "登录状态已失效，请连接校园网后重新登录并继续查询。")
        XCTAssertTrue(outcome.requiresReauthentication)
    }
}

private enum ClassroomLookupTestError: LocalizedError {
    case remoteFailure

    var errorDescription: String? {
        "远程查询失败"
    }
}

private actor ClassroomLookupCallRecorder {
    private var remoteEmptyClassroomFetchCount = 0

    func recordRemoteEmptyClassroomFetch() {
        remoteEmptyClassroomFetchCount += 1
    }

    func remoteEmptyClassroomFetches() -> Int {
        remoteEmptyClassroomFetchCount
    }
}

private actor InMemoryClassroomLookupCache: ClassroomLookupCaching {
    private var roomsByKey: [String: [EmptyClassroom]] = [:]
    private var usageByKey: [String: [ClassroomUsageSlot]] = [:]

    func loadEmptyClassrooms(date: Date, start: Int, end: Int) -> [EmptyClassroom] {
        roomsByKey[emptyRoomsKey(date: date, start: start, end: end)] ?? []
    }

    func saveEmptyClassrooms(_ rooms: [EmptyClassroom], date: Date, start: Int, end: Int) {
        roomsByKey[emptyRoomsKey(date: date, start: start, end: end)] = rooms
    }

    func loadClassroomUsage(date: Date, building: String, room: String) -> [ClassroomUsageSlot] {
        usageByKey[usageKey(date: date, building: building, room: room)] ?? []
    }

    func saveClassroomUsage(_ usage: [ClassroomUsageSlot], date: Date, building: String, room: String) {
        usageByKey[usageKey(date: date, building: building, room: room)] = usage
    }

    func emptyRooms(date: Date, start: Int, end: Int) -> [EmptyClassroom] {
        roomsByKey[emptyRoomsKey(date: date, start: start, end: end)] ?? []
    }

    func usage(date: Date, building: String, room: String) -> [ClassroomUsageSlot] {
        usageByKey[usageKey(date: date, building: building, room: room)] ?? []
    }

    private func emptyRoomsKey(date: Date, start: Int, end: Int) -> String {
        "\(date.timeIntervalSince1970)-\(start)-\(end)"
    }

    private func usageKey(date: Date, building: String, room: String) -> String {
        "\(date.timeIntervalSince1970)-\(building)-\(room)"
    }
}
