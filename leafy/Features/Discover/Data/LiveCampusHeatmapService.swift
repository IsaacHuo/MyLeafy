import Foundation

nonisolated struct LiveCampusHeatmapService: CampusHeatmapServicing {
    private let loadArchive: @Sendable () async -> CampusOccupancyArchive?

    init(loadArchive: @escaping @Sendable () async -> CampusOccupancyArchive? = {
        CampusOccupancyBundleStore.load()
    }) {
        self.loadArchive = loadArchive
    }

    func load(_ request: CampusHeatmapRequest) async -> CampusHeatmapOutcome {
        guard let archive = await loadArchive() else {
            return .fallback(
                data: CampusHeatmapData(),
                errorMessage: "当前版本未内置校园热力快照。",
                requiresReauthentication: false
            )
        }

        guard let snapshot = archive.slice(for: request) else {
            return .fallback(
                data: CampusHeatmapData(),
                errorMessage: "当前日期或节次不在内置热力快照范围内。",
                requiresReauthentication: false
            )
        }

        return .success(CampusHeatmapData.make(snapshot: snapshot))
    }
}

nonisolated enum CampusOccupancyBundleStore {
    static let resourceName = "bjfu-campus-occupancy-2025-2026-2"

    static func load(bundle: Bundle = .main) -> CampusOccupancyArchive? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CampusOccupancyArchive.self, from: data)
    }
}
