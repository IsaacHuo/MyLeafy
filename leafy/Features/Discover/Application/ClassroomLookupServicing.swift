import Foundation

protocol ClassroomLookupServicing: Sendable {
    func lookup(_ request: ClassroomLookupRequest, userInitiated: Bool) async -> ClassroomLookupOutcome
}

protocol ClassroomLookupCaching: Sendable {
    func loadEmptyClassrooms(date: Date, start: Int, end: Int) async -> [EmptyClassroom]
    func saveEmptyClassrooms(_ rooms: [EmptyClassroom], date: Date, start: Int, end: Int) async
    func loadClassroomUsage(date: Date, building: String, room: String) async -> [ClassroomUsageSlot]
    func saveClassroomUsage(_ usage: [ClassroomUsageSlot], date: Date, building: String, room: String) async
}
