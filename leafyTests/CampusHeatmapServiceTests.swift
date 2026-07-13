import XCTest
@testable import Leafy

final class CampusHeatmapServiceTests: XCTestCase {
    func testHeatmapDataCalculatesOccupancyFromAvailableClassrooms() {
        let roomsByBuilding = [
            "二教": ["101", "102", "103"],
            "三教": ["201", "202"]
        ]
        let data = CampusHeatmapData.make(
            availableRooms: [
                EmptyClassroom(building: "二教", room: "101"),
                EmptyClassroom(building: "二教", room: "102"),
                EmptyClassroom(building: "三教", room: "201")
            ],
            roomsByBuilding: roomsByBuilding
        )

        let second = data.buildings.first { $0.building == "二教" }
        XCTAssertEqual(second?.totalRooms, 3)
        XCTAssertEqual(second?.availableRooms, 2)
        XCTAssertEqual(second?.occupiedRooms, 1)
        XCTAssertEqual(second?.occupancyRatio ?? -1, 1.0 / 3.0, accuracy: 0.0001)

        let third = data.buildings.first { $0.building == "三教" }
        XCTAssertEqual(third?.totalRooms, 2)
        XCTAssertEqual(third?.availableRooms, 1)
        XCTAssertEqual(third?.occupiedRooms, 1)
        XCTAssertEqual(third?.occupancyRatio ?? -1, 0.5, accuracy: 0.0001)
    }

    func testHeatmapDataNormalizesBuildingAliases() {
        let data = CampusHeatmapData.make(
            availableRooms: [
                EmptyClassroom(building: "第二教学楼", room: "205"),
                EmptyClassroom(building: "二教楼", room: "510a")
            ],
            roomsByBuilding: [
                "二教": ["205", "510A", "601"]
            ]
        )

        let second = data.buildings.first { $0.building == "二教" }
        XCTAssertEqual(second?.availableRooms, 2)
        XCTAssertEqual(second?.occupiedRooms, 1)
        XCTAssertEqual(data.unmatchedAvailableRoomCount, 0)
    }

    func testHeatmapDataKeepsUnknownRoomsOutOfMappedCounts() {
        let data = CampusHeatmapData.make(
            availableRooms: [
                EmptyClassroom(building: "二教", room: "999"),
                EmptyClassroom(building: "校外楼", room: "101")
            ],
            roomsByBuilding: [
                "二教": ["101", "102"]
            ]
        )

        let second = data.buildings.first { $0.building == "二教" }
        XCTAssertEqual(second?.availableRooms, 0)
        XCTAssertEqual(second?.occupiedRooms, 2)
        XCTAssertEqual(data.unmatchedAvailableRoomCount, 2)
    }

    func testHeatmapDataSummarizesFloors() {
        let data = CampusHeatmapData.make(
            availableRooms: [
                EmptyClassroom(building: "二教", room: "101"),
                EmptyClassroom(building: "二教", room: "201")
            ],
            roomsByBuilding: [
                "二教": ["101", "102", "201", "202"]
            ]
        )

        let floors = data.buildings.first { $0.building == "二教" }?.floors
        XCTAssertEqual(floors?.first { $0.floor == 1 }?.availableRooms, 1)
        XCTAssertEqual(floors?.first { $0.floor == 1 }?.occupiedRooms, 1)
        XCTAssertEqual(floors?.first { $0.floor == 2 }?.availableRooms, 1)
        XCTAssertEqual(floors?.first { $0.floor == 2 }?.occupiedRooms, 1)
    }

    func testCachedDataMatchesOnlyTheStoredDayAndPeriods() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let storedData = CachedCampusHeatmapData(
            date: date,
            startPeriod: 3,
            endPeriod: 4,
            updatedAt: date,
            availableRooms: []
        )

        XCTAssertTrue(storedData.matches(CampusHeatmapRequest(date: date, startPeriod: 3, endPeriod: 4)))
        XCTAssertFalse(storedData.matches(CampusHeatmapRequest(date: date, startPeriod: 4, endPeriod: 4)))
        XCTAssertFalse(storedData.matches(CampusHeatmapRequest(date: date.addingTimeInterval(86_400), startPeriod: 3, endPeriod: 4)))
    }

    func testLoadStoredDataDoesNotFetchRemoteData() async {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let storedData = CachedCampusHeatmapData(
            date: date,
            startPeriod: 1,
            endPeriod: 2,
            updatedAt: date,
            availableRooms: [EmptyClassroom(building: "二教", room: "101")]
        )
        let cache = InMemoryCampusHeatmapCache(storedData: storedData)
        let recorder = CampusHeatmapFetchRecorder()
        let service = LiveCampusHeatmapService(
            fetchEmptyClassroomsHTML: { _, _, _ in
                await recorder.recordFetch()
                return ""
            },
            isDemoModeEnabled: { false },
            cache: cache
        )

        let outcome = await service.loadStoredData()
        let fetchCount = await recorder.fetchCount

        XCTAssertEqual(outcome.storedData, storedData)
        XCTAssertNil(outcome.errorMessage)
        XCTAssertEqual(fetchCount, 0)
    }

    func testUpdateFetchesOnceAndOverwritesStoredData() async {
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        let requestDate = Date(timeIntervalSince1970: 1_800_000_000)
        let updatedAt = Date(timeIntervalSince1970: 1_900_000_000)
        let cache = InMemoryCampusHeatmapCache(storedData: CachedCampusHeatmapData(
            date: oldDate,
            startPeriod: 1,
            endPeriod: 1,
            updatedAt: oldDate,
            availableRooms: []
        ))
        let recorder = CampusHeatmapFetchRecorder()
        let rooms = [EmptyClassroom(building: "二教", room: "101")]
        let service = LiveCampusHeatmapService(
            fetchEmptyClassroomsHTML: { date, start, end in
                await recorder.recordFetch(date: date, start: start, end: end)
                return "<html></html>"
            },
            parseEmptyClassrooms: { _ in rooms },
            isDemoModeEnabled: { false },
            now: { updatedAt },
            cache: cache
        )
        let request = CampusHeatmapRequest(date: requestDate, startPeriod: 3, endPeriod: 5)

        let outcome = await service.update(request)
        let fetchCount = await recorder.fetchCount
        let lastStartPeriod = await recorder.lastStartPeriod
        let lastEndPeriod = await recorder.lastEndPeriod
        let cachedData = await cache.storedData
        let saveCount = await cache.saveCount

        XCTAssertNil(outcome.errorMessage)
        XCTAssertEqual(outcome.storedData?.availableRooms, rooms)
        XCTAssertEqual(outcome.storedData?.updatedAt, updatedAt)
        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(lastStartPeriod, 3)
        XCTAssertEqual(lastEndPeriod, 5)
        XCTAssertEqual(cachedData, outcome.storedData)
        XCTAssertEqual(saveCount, 1)
    }

    func testUpdateFailureKeepsPreviouslyStoredData() async {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let storedData = CachedCampusHeatmapData(
            date: date,
            startPeriod: 1,
            endPeriod: 2,
            updatedAt: date,
            availableRooms: [EmptyClassroom(building: "二教", room: "101")]
        )
        let cache = InMemoryCampusHeatmapCache(storedData: storedData)
        let service = LiveCampusHeatmapService(
            fetchEmptyClassroomsHTML: { _, _, _ in throw CampusHeatmapTestError.remoteFailure },
            isDemoModeEnabled: { false },
            requiresReauthentication: { _ in false },
            cache: cache
        )

        let outcome = await service.update(CampusHeatmapRequest(date: date, startPeriod: 3, endPeriod: 4))
        let saveCount = await cache.saveCount

        XCTAssertEqual(outcome.storedData, storedData)
        XCTAssertEqual(outcome.errorMessage, "更新失败：远程请求失败")
        XCTAssertEqual(saveCount, 0)
    }

    func testDemoUpdateSkipsRemoteFetchAndPersistsData() async {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let rooms = [EmptyClassroom(building: "二教", room: "205")]
        let cache = InMemoryCampusHeatmapCache()
        let recorder = CampusHeatmapFetchRecorder()
        let service = LiveCampusHeatmapService(
            fetchEmptyClassroomsHTML: { _, _, _ in
                await recorder.recordFetch()
                return ""
            },
            isDemoModeEnabled: { true },
            demoEmptyClassrooms: { _, _, _ in rooms },
            cache: cache
        )

        let outcome = await service.update(CampusHeatmapRequest(date: date, startPeriod: 1, endPeriod: 2))
        let fetchCount = await recorder.fetchCount
        let saveCount = await cache.saveCount

        XCTAssertEqual(outcome.storedData?.availableRooms, rooms)
        XCTAssertEqual(fetchCount, 0)
        XCTAssertEqual(saveCount, 1)
    }

    func testOnlyBuildingsWithCoordinatesAreMapped() {
        let data = CampusHeatmapData.make(
            snapshot: CampusOccupancySnapshot(
                rooms: [
                    CampusRoomOccupancy(building: "二教", room: "205", isOccupied: true),
                    CampusRoomOccupancy(building: "未知楼", room: "101", isOccupied: true)
                ],
                unmatchedAvailableRoomCount: 0
            )
        )

        XCTAssertTrue(data.mappedBuildings.contains { $0.building == "二教" })
        XCTAssertFalse(data.mappedBuildings.contains { $0.building == "未知楼" })
        XCTAssertTrue(data.buildings.contains { $0.building == "未知楼" })
    }
}

private enum CampusHeatmapTestError: LocalizedError {
    case remoteFailure

    var errorDescription: String? {
        "远程请求失败"
    }
}

private actor CampusHeatmapFetchRecorder {
    private(set) var fetchCount = 0
    private(set) var lastDate: Date?
    private(set) var lastStartPeriod: Int?
    private(set) var lastEndPeriod: Int?

    func recordFetch(date: Date? = nil, start: Int? = nil, end: Int? = nil) {
        fetchCount += 1
        lastDate = date
        lastStartPeriod = start
        lastEndPeriod = end
    }
}

private actor InMemoryCampusHeatmapCache: CampusHeatmapCaching {
    private(set) var storedData: CachedCampusHeatmapData?
    private(set) var saveCount = 0

    init(storedData: CachedCampusHeatmapData? = nil) {
        self.storedData = storedData
    }

    func load() -> CachedCampusHeatmapData? {
        storedData
    }

    func save(_ data: CachedCampusHeatmapData) {
        storedData = data
        saveCount += 1
    }
}
