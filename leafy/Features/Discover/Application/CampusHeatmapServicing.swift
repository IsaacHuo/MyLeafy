import Foundation

protocol CampusHeatmapServicing: Sendable {
    func load(_ request: CampusHeatmapRequest) async -> CampusHeatmapOutcome
}
