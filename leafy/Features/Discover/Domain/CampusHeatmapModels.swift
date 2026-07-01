import Foundation

nonisolated struct CampusHeatmapRequest: Equatable, Identifiable, Sendable {
    let id: UUID
    let date: Date
    let startPeriod: Int
    let endPeriod: Int

    init(id: UUID = UUID(), date: Date, startPeriod: Int, endPeriod: Int) {
        self.id = id
        self.date = date
        self.startPeriod = min(max(startPeriod, 1), 12)
        self.endPeriod = min(max(endPeriod, min(max(startPeriod, 1), 12)), 12)
    }
}

nonisolated struct CampusHeatmapBuildingSummary: Identifiable, Hashable, Sendable {
    var id: String { building }

    let building: String
    let totalRooms: Int
    let availableRooms: Int
    let occupiedRooms: Int
    let floors: [CampusHeatmapFloorSummary]

    var occupancyRatio: Double {
        guard totalRooms > 0 else { return 0 }
        return Double(occupiedRooms) / Double(totalRooms)
    }

    var hasCoordinate: Bool {
        ClassroomCatalog.coordinate(for: building) != nil
    }
}

nonisolated struct CampusHeatmapFloorSummary: Identifiable, Hashable, Sendable {
    var id: Int { floor }

    let floor: Int
    let totalRooms: Int
    let availableRooms: Int
    let occupiedRooms: Int

    var occupancyRatio: Double {
        guard totalRooms > 0 else { return 0 }
        return Double(occupiedRooms) / Double(totalRooms)
    }

    var title: String {
        "\(floor) 层"
    }
}

nonisolated struct CampusRoomOccupancy: Codable, Hashable, Sendable {
    let building: String
    let room: String
    let isOccupied: Bool

    var identity: ClassroomIdentity {
        ClassroomIdentity(building: building, room: room)
    }

    var floor: Int? {
        ClassroomCatalog.floor(for: room)
    }
}

nonisolated struct CampusOccupancySnapshot: Codable, Equatable, Sendable {
    let rooms: [CampusRoomOccupancy]
    let unmatchedAvailableRoomCount: Int

    static func inferred(
        fromAvailableRooms availableRooms: [EmptyClassroom],
        roomsByBuilding: [String: [String]] = ClassroomCatalog.roomsByBuilding
    ) -> CampusOccupancySnapshot {
        var availableIDsByBuilding: [String: Set<ClassroomIdentity>] = [:]
        var unmatchedAvailableRoomCount = 0

        for room in availableRooms {
            let identity = room.identity
            guard let catalogBuilding = catalogBuilding(matching: identity.building, in: roomsByBuilding),
                  catalogContains(identity, in: catalogBuilding, roomsByBuilding: roomsByBuilding) else {
                unmatchedAvailableRoomCount += 1
                continue
            }
            availableIDsByBuilding[catalogBuilding, default: []].insert(identity)
        }

        let occupancies = roomsByBuilding.keys.sorted().flatMap { building in
            (roomsByBuilding[building] ?? []).map { room in
                let identity = ClassroomIdentity(building: building, room: room)
                return CampusRoomOccupancy(
                    building: building,
                    room: room,
                    isOccupied: !availableIDsByBuilding[building, default: []].contains(identity)
                )
            }
        }

        return CampusOccupancySnapshot(
            rooms: occupancies,
            unmatchedAvailableRoomCount: unmatchedAvailableRoomCount
        )
    }

    private static func catalogBuilding(
        matching building: String,
        in roomsByBuilding: [String: [String]]
    ) -> String? {
        let target = ClassroomIdentity(building: building, room: "placeholder")
        return roomsByBuilding.keys.first { candidate in
            ClassroomIdentity(building: candidate, room: "placeholder") == target
        }
    }

    private static func catalogContains(
        _ identity: ClassroomIdentity,
        in building: String,
        roomsByBuilding: [String: [String]]
    ) -> Bool {
        (roomsByBuilding[building] ?? []).contains { room in
            ClassroomIdentity(building: building, room: room) == identity
        }
    }
}

nonisolated struct CampusOccupiedRoomReference: Codable, Equatable, Sendable {
    let building: String
    let room: String

    var identity: ClassroomIdentity {
        ClassroomIdentity(building: building, room: room)
    }
}

nonisolated struct CampusOccupancyArchiveSlot: Codable, Equatable, Sendable {
    let week: Int
    let day: Int
    let period: Int
    let occupiedRooms: [CampusOccupiedRoomReference]
    let unmatchedAvailableRoomCount: Int

    var key: String {
        Self.key(week: week, day: day, period: period)
    }

    init(week: Int, day: Int, period: Int, snapshot: CampusOccupancySnapshot) {
        self.week = week
        self.day = day
        self.period = period
        self.occupiedRooms = snapshot.rooms
            .filter(\.isOccupied)
            .map { CampusOccupiedRoomReference(building: $0.building, room: $0.room) }
        self.unmatchedAvailableRoomCount = snapshot.unmatchedAvailableRoomCount
    }

    static func key(week: Int, day: Int, period: Int) -> String {
        "\(week)-\(day)-\(period)"
    }
}

nonisolated struct CampusOccupancyArchive: Codable, Equatable, Sendable {
    let semesterID: String
    let generatedAt: Date
    let slots: [CampusOccupancyArchiveSlot]

    func slice(for request: CampusHeatmapRequest, config: SemesterRuntimeConfig = SemesterConfig.current) -> CampusOccupancySnapshot? {
        guard semesterID == config.semesterID else { return nil }
        guard Self.contains(request.date, in: config) else { return nil }

        let schedule = SemesterConfig.weekAndDay(for: request.date, config: config)
        let slotsByKey = Dictionary(slots.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let periodSlots = (request.startPeriod...request.endPeriod).compactMap { period in
            slotsByKey[CampusOccupancyArchiveSlot.key(week: schedule.week, day: schedule.day, period: period)]
        }

        guard periodSlots.count == request.endPeriod - request.startPeriod + 1 else {
            return nil
        }

        var occupiedIDs = Set<ClassroomIdentity>()
        for slot in periodSlots {
            for room in slot.occupiedRooms {
                occupiedIDs.insert(room.identity)
            }
        }

        let rooms = ClassroomCatalog.roomsByBuilding.keys.sorted().flatMap { building in
            (ClassroomCatalog.roomsByBuilding[building] ?? []).map { room in
                CampusRoomOccupancy(
                    building: building,
                    room: room,
                    isOccupied: occupiedIDs.contains(ClassroomIdentity(building: building, room: room))
                )
            }
        }

        return CampusOccupancySnapshot(
            rooms: rooms,
            unmatchedAvailableRoomCount: periodSlots.map(\.unmatchedAvailableRoomCount).max() ?? 0
        )
    }

    private static func contains(_ date: Date, in config: SemesterRuntimeConfig) -> Bool {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: config.semesterStartDate)
        guard let end = calendar.date(byAdding: .day, value: config.supportedWeeks * 7, to: start) else {
            return false
        }
        let day = calendar.startOfDay(for: date)
        return day >= start && day < end
    }
}

nonisolated struct CampusHeatmapData: Equatable, Sendable {
    var buildings: [CampusHeatmapBuildingSummary] = []
    var unmatchedAvailableRoomCount = 0

    var mappedBuildings: [CampusHeatmapBuildingSummary] {
        buildings.filter(\.hasCoordinate)
    }

    var hottestBuildings: [CampusHeatmapBuildingSummary] {
        buildings.sorted {
            if $0.occupancyRatio != $1.occupancyRatio {
                return $0.occupancyRatio > $1.occupancyRatio
            }
            if $0.occupiedRooms != $1.occupiedRooms {
                return $0.occupiedRooms > $1.occupiedRooms
            }
            return $0.building < $1.building
        }
    }

    static func make(
        availableRooms: [EmptyClassroom],
        roomsByBuilding: [String: [String]] = ClassroomCatalog.roomsByBuilding
    ) -> CampusHeatmapData {
        let snapshot = CampusOccupancySnapshot.inferred(
            fromAvailableRooms: availableRooms,
            roomsByBuilding: roomsByBuilding
        )
        return make(snapshot: snapshot)
    }

    static func make(snapshot: CampusOccupancySnapshot) -> CampusHeatmapData {
        let roomsByBuilding = Dictionary(grouping: snapshot.rooms, by: \.identity.building)
        let summaries = roomsByBuilding.keys.sorted().map { building in
            let rooms = roomsByBuilding[building] ?? []
            let totalRooms = rooms.count
            let occupiedRooms = rooms.filter(\.isOccupied).count
            let availableRooms = max(totalRooms - occupiedRooms, 0)
            return CampusHeatmapBuildingSummary(
                building: building,
                totalRooms: totalRooms,
                availableRooms: availableRooms,
                occupiedRooms: occupiedRooms,
                floors: Self.floorSummaries(from: rooms)
            )
        }

        return CampusHeatmapData(
            buildings: summaries,
            unmatchedAvailableRoomCount: snapshot.unmatchedAvailableRoomCount
        )
    }

    private static func floorSummaries(from rooms: [CampusRoomOccupancy]) -> [CampusHeatmapFloorSummary] {
        let roomsByFloor = Dictionary(grouping: rooms.compactMap { room -> (Int, CampusRoomOccupancy)? in
            guard let floor = room.floor else { return nil }
            return (floor, room)
        }, by: \.0)

        return roomsByFloor.keys.sorted().map { floor in
            let floorRooms = roomsByFloor[floor]?.map(\.1) ?? []
            let totalRooms = floorRooms.count
            let occupiedRooms = floorRooms.filter(\.isOccupied).count
            return CampusHeatmapFloorSummary(
                floor: floor,
                totalRooms: totalRooms,
                availableRooms: max(totalRooms - occupiedRooms, 0),
                occupiedRooms: occupiedRooms
            )
        }
    }
}

nonisolated struct CampusHeatmapOutcome: Equatable, Sendable {
    let data: CampusHeatmapData
    let errorMessage: String?
    let requiresReauthentication: Bool

    static func success(_ data: CampusHeatmapData) -> CampusHeatmapOutcome {
        CampusHeatmapOutcome(
            data: data,
            errorMessage: nil,
            requiresReauthentication: false
        )
    }

    static func fallback(
        data: CampusHeatmapData,
        errorMessage: String,
        requiresReauthentication: Bool
    ) -> CampusHeatmapOutcome {
        CampusHeatmapOutcome(
            data: data,
            errorMessage: errorMessage,
            requiresReauthentication: requiresReauthentication
        )
    }
}
