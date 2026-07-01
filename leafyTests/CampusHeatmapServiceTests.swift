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

    func testArchiveSliceCombinesSelectedPeriods() {
        let calendar = Calendar(identifier: .gregorian)
        let config = SemesterRuntimeConfig(
            semesterID: "test-semester",
            semesterStartDateString: "2026-03-09",
            supportedWeeks: 2,
            graduateTimetableTermCode: "46",
            calendarEvents: [],
            updatedAt: nil,
            isActive: true
        )
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        let archive = CampusOccupancyArchive(
            semesterID: "test-semester",
            generatedAt: Date(timeIntervalSince1970: 0),
            slots: [
                CampusOccupancyArchiveSlot(
                    week: 1,
                    day: 2,
                    period: 3,
                    snapshot: CampusOccupancySnapshot(
                        rooms: [
                            CampusRoomOccupancy(building: "二教", room: "101", isOccupied: true)
                        ],
                        unmatchedAvailableRoomCount: 1
                    )
                ),
                CampusOccupancyArchiveSlot(
                    week: 1,
                    day: 2,
                    period: 4,
                    snapshot: CampusOccupancySnapshot(
                        rooms: [
                            CampusRoomOccupancy(building: "二教", room: "102", isOccupied: true)
                        ],
                        unmatchedAvailableRoomCount: 2
                    )
                )
            ]
        )

        let snapshot = archive.slice(
            for: CampusHeatmapRequest(date: date, startPeriod: 3, endPeriod: 4),
            config: config
        )
        let occupiedIDs = Set(snapshot?.rooms.filter(\.isOccupied).map(\.identity) ?? [])

        XCTAssertTrue(occupiedIDs.contains(ClassroomIdentity(building: "二教", room: "101")))
        XCTAssertTrue(occupiedIDs.contains(ClassroomIdentity(building: "二教", room: "102")))
        XCTAssertEqual(snapshot?.unmatchedAvailableRoomCount, 2)
    }

    func testArchiveSliceRejectsDatesOutsideSemester() {
        let config = SemesterRuntimeConfig(
            semesterID: "test-semester",
            semesterStartDateString: "2026-03-09",
            supportedWeeks: 1,
            graduateTimetableTermCode: "46",
            calendarEvents: [],
            updatedAt: nil,
            isActive: true
        )
        let archive = CampusOccupancyArchive(
            semesterID: "test-semester",
            generatedAt: Date(timeIntervalSince1970: 0),
            slots: []
        )
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 3, day: 30))!

        XCTAssertNil(archive.slice(for: CampusHeatmapRequest(date: date, startPeriod: 1, endPeriod: 1), config: config))
    }

    func testLiveServiceLoadsArchive() async {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 9))!
        let archive = CampusOccupancyArchive(
            semesterID: SemesterRuntimeConfig.builtIn.semesterID,
            generatedAt: Date(timeIntervalSince1970: 0),
            slots: [
                CampusOccupancyArchiveSlot(
                    week: 1,
                    day: 1,
                    period: 1,
                    snapshot: CampusOccupancySnapshot(
                        rooms: [
                            CampusRoomOccupancy(building: "二教", room: "101", isOccupied: true)
                        ],
                        unmatchedAvailableRoomCount: 0
                    )
                )
            ]
        )
        let service = LiveCampusHeatmapService(loadArchive: { archive })

        let outcome = await service.load(CampusHeatmapRequest(date: date, startPeriod: 1, endPeriod: 1))

        XCTAssertNil(outcome.errorMessage)
        XCTAssertEqual(outcome.data.buildings.first { $0.building == "二教" }?.occupiedRooms, 1)
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
