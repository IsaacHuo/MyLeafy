import Foundation

protocol CampusHeatmapServicing: Sendable {
    func loadStoredData() async -> CampusHeatmapOutcome
    func update(_ request: CampusHeatmapRequest) async -> CampusHeatmapOutcome
}

protocol CampusHeatmapCaching: Sendable {
    func load() async throws -> CachedCampusHeatmapData?
    func save(_ data: CachedCampusHeatmapData) async throws
}
