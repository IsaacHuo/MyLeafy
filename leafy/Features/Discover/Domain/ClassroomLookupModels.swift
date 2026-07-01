import Foundation

nonisolated struct ClassroomIdentity: Equatable, Hashable, Sendable {
    let building: String
    let room: String

    init(building: String, room: String) {
        self.building = Self.normalizedBuilding(building)
        self.room = Self.normalizedRoom(room)
    }

    var isEmpty: Bool {
        building.isEmpty || room.isEmpty
    }

    static func matches(_ lhs: ClassroomIdentity, _ rhs: ClassroomIdentity) -> Bool {
        !lhs.isEmpty && lhs == rhs
    }

    private static func normalizedBuilding(_ value: String) -> String {
        let compact = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")

        let aliases: [String: String] = [
            "第一教学楼": "一教",
            "一教学楼": "一教",
            "一教楼": "一教",
            "第1教学楼": "一教",
            "1教": "一教",
            "第二教学楼": "二教",
            "二教学楼": "二教",
            "二教楼": "二教",
            "第2教学楼": "二教",
            "2教": "二教",
            "第三教学楼": "三教",
            "三教学楼": "三教",
            "三教楼": "三教",
            "第3教学楼": "三教",
            "3教": "三教",
            "学研A": "学研A座",
            "学研楼A座": "学研A座",
            "学研B": "学研B座",
            "学研楼B座": "学研B座",
            "学研C": "学研C座",
            "学研楼C座": "学研C座"
        ]

        return aliases[compact] ?? compact
    }

    private static func normalizedRoom(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            .uppercased()
    }
}

struct ClassroomLookupRequest: Equatable, Identifiable, Sendable {
    enum Mode: Equatable, Sendable {
        case byPeriod
        case byRoom
    }

    let id: UUID
    let mode: Mode
    let date: Date
    let startPeriod: Int
    let endPeriod: Int
    let building: String
    let room: String

    init(
        id: UUID = UUID(),
        mode: Mode,
        date: Date,
        startPeriod: Int,
        endPeriod: Int,
        building: String,
        room: String
    ) {
        self.id = id
        self.mode = mode
        self.date = date
        self.startPeriod = startPeriod
        self.endPeriod = endPeriod
        self.building = building
        self.room = room
    }

    init(date: Date, startPeriod: Int, endPeriod: Int) {
        self.init(
            mode: .byPeriod,
            date: date,
            startPeriod: startPeriod,
            endPeriod: endPeriod,
            building: "",
            room: ""
        )
    }

    init(date: Date, building: String, room: String) {
        self.init(
            mode: .byRoom,
            date: date,
            startPeriod: 1,
            endPeriod: 12,
            building: building,
            room: room
        )
    }

    init(building: String, room: String) {
        self.init(date: Date(), building: building, room: room)
    }
}

struct ClassroomLookupData: Equatable, Sendable {
    var rooms: [EmptyClassroom] = []
    var usage: [ClassroomUsageSlot] = []
}

struct ClassroomLookupOutcome: Equatable, Sendable {
    let data: ClassroomLookupData
    let errorMessage: String?
    let requiresReauthentication: Bool

    static func success(_ data: ClassroomLookupData) -> ClassroomLookupOutcome {
        ClassroomLookupOutcome(data: data, errorMessage: nil, requiresReauthentication: false)
    }

    static func fallback(
        data: ClassroomLookupData,
        errorMessage: String,
        requiresReauthentication: Bool
    ) -> ClassroomLookupOutcome {
        ClassroomLookupOutcome(
            data: data,
            errorMessage: errorMessage,
            requiresReauthentication: requiresReauthentication
        )
    }
}

nonisolated extension EmptyClassroom {
    var identity: ClassroomIdentity {
        ClassroomIdentity(building: building, room: room)
    }
}

nonisolated enum ClassroomUsageStatusResolver {
    static func status(
        html _: String,
        parsedRooms rooms: [EmptyClassroom],
        target: ClassroomIdentity,
        rawBuilding _: String,
        rawRoom _: String
    ) -> ClassroomUsageStatus {
        if rooms.contains(where: { ClassroomIdentity.matches($0.identity, target) }) {
            return .available
        }
        return .occupied
    }
}

nonisolated struct ClassroomLookupBuildingOption: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let buildings: [String]

    var rooms: [ClassroomLookupRoomOption] {
        buildings.flatMap { building in
            (ClassroomCatalog.roomsByBuilding[building] ?? []).map { room in
                ClassroomLookupRoomOption(building: building, room: room)
            }
        }
    }
}

nonisolated struct ClassroomLookupRoomOption: Identifiable, Equatable, Sendable {
    let building: String
    let room: String

    var id: String { "\(building)-\(room)" }
    var title: String {
        if building.hasPrefix("学研") {
            return "\(building.replacingOccurrences(of: "学研", with: "")) \(room)"
        }
        return room
    }
}

nonisolated enum ClassroomLookupCatalog {
    static let buildingOptions: [ClassroomLookupBuildingOption] = [
        ClassroomLookupBuildingOption(id: "second", title: "二教", buildings: ["二教"]),
        ClassroomLookupBuildingOption(id: "first", title: "一教", buildings: ["一教"]),
        ClassroomLookupBuildingOption(id: "xueyan", title: "学研", buildings: ["学研A座", "学研B座"])
    ]

    static var defaultBuildingOption: ClassroomLookupBuildingOption {
        buildingOptions.first ?? ClassroomLookupBuildingOption(id: "second", title: "二教", buildings: ["二教"])
    }

    static func option(containing building: String?) -> ClassroomLookupBuildingOption {
        guard let building,
              let option = buildingOptions.first(where: { $0.buildings.contains(building) }) else {
            return defaultBuildingOption
        }
        return option
    }

    static func roomOption(preferredBuilding: String?, preferredRoom: String?, in option: ClassroomLookupBuildingOption) -> ClassroomLookupRoomOption {
        let rooms = option.rooms
        if let preferredBuilding,
           let preferredRoom,
           let matched = rooms.first(where: { $0.building == preferredBuilding && $0.room == preferredRoom }) {
            return matched
        }
        return rooms.first ?? ClassroomLookupRoomOption(building: option.buildings.first ?? "", room: "")
    }

    static func filteredRooms(_ rooms: [EmptyClassroom]) -> [EmptyClassroom] {
        let allowedBuildings = Set(buildingOptions.flatMap(\.buildings))
        return rooms.filter { allowedBuildings.contains($0.building) }
    }

    static func contains(building: String) -> Bool {
        buildingOptions.contains { $0.buildings.contains(building) }
    }

    static func displayBuilding(for building: String) -> String {
        buildingOptions.first { $0.buildings.contains(building) }?.title ?? building
    }
}

nonisolated struct EmptyClassroomBuildingGroup: Identifiable, Equatable, Sendable {
    let building: String
    let rooms: [EmptyClassroom]

    var id: String { building }
    var countText: String { "\(rooms.count) 间" }

    static func groups(
        from rooms: [EmptyClassroom],
        displayBuilding: (String) -> String = { $0 }
    ) -> [EmptyClassroomBuildingGroup] {
        let groupedRooms = Dictionary(grouping: rooms, by: { displayBuilding($0.building) })
        return groupedRooms.keys.sorted(by: compareBuildings).map { building in
            EmptyClassroomBuildingGroup(
                building: building,
                rooms: (groupedRooms[building] ?? []).sorted { lhs, rhs in
                    if lhs.building == rhs.building {
                        return lhs.room.localizedStandardCompare(rhs.room) == .orderedAscending
                    }
                    return compareBuildings(lhs.building, rhs.building)
                }
            )
        }
    }

    private static func compareBuildings(_ lhs: String, _ rhs: String) -> Bool {
        let lhsOrder = buildingOrder(lhs)
        let rhsOrder = buildingOrder(rhs)

        if lhsOrder.section != rhsOrder.section {
            return lhsOrder.section < rhsOrder.section
        }
        if lhsOrder.index != rhsOrder.index {
            return lhsOrder.index < rhsOrder.index
        }
        return lhs.localizedStandardCompare(rhs) == .orderedAscending
    }

    private static func buildingOrder(_ building: String) -> (section: Int, index: Int) {
        if let optionIndex = ClassroomLookupCatalog.buildingOptions.firstIndex(where: { $0.title == building }) {
            return (0, optionIndex * 100)
        }

        if let optionIndex = ClassroomLookupCatalog.buildingOptions.firstIndex(where: { $0.buildings.contains(building) }),
           let buildingIndex = ClassroomLookupCatalog.buildingOptions[optionIndex].buildings.firstIndex(of: building) {
            return (0, optionIndex * 100 + buildingIndex + 1)
        }

        if let catalogIndex = ClassroomCatalog.buildings.firstIndex(of: building) {
            return (1, catalogIndex)
        }

        return (2, 0)
    }
}
