import Foundation

nonisolated struct LiveCampusHeatmapService: CampusHeatmapServicing {
    private let fetchEmptyClassroomsHTML: @Sendable (Date, Int, Int) async throws -> String
    private let parseEmptyClassrooms: @Sendable (String) throws -> [EmptyClassroom]
    private let isDemoModeEnabled: @Sendable () async -> Bool
    private let demoEmptyClassrooms: @Sendable (Date, Int, Int) async -> [EmptyClassroom]
    private let requiresReauthentication: @Sendable (Error) -> Bool
    private let now: @Sendable () -> Date
    private let cache: any CampusHeatmapCaching

    init(
        fetchEmptyClassroomsHTML: @escaping @Sendable (Date, Int, Int) async throws -> String = { date, start, end in
            try await ActiveCampusContext.networkManager.fetchEmptyClassrooms(date: date, start: start, end: end)
        },
        parseEmptyClassrooms: @escaping @Sendable (String) throws -> [EmptyClassroom] = { html in
            try HTMLParser.parseEmptyClassrooms(html: html)
        },
        isDemoModeEnabled: @escaping @Sendable () async -> Bool = {
            await MainActor.run { ReviewDemoMode.isEnabled }
        },
        demoEmptyClassrooms: @escaping @Sendable (Date, Int, Int) async -> [EmptyClassroom] = { date, start, end in
            await MainActor.run {
                ReviewDemoDataSeeder.emptyClassrooms(for: date, start: start, end: end)
            }
        },
        requiresReauthentication: @escaping @Sendable (Error) -> Bool = { error in
            ClassroomLookupReauthentication.requiresReauthentication(error)
        },
        now: @escaping @Sendable () -> Date = Date.init,
        cache: any CampusHeatmapCaching = SchoolDataCampusHeatmapCache()
    ) {
        self.fetchEmptyClassroomsHTML = fetchEmptyClassroomsHTML
        self.parseEmptyClassrooms = parseEmptyClassrooms
        self.isDemoModeEnabled = isDemoModeEnabled
        self.demoEmptyClassrooms = demoEmptyClassrooms
        self.requiresReauthentication = requiresReauthentication
        self.now = now
        self.cache = cache
    }

    func loadStoredData() async -> CampusHeatmapOutcome {
        do {
            return .success(try await cache.load())
        } catch {
            return .fallback(
                storedData: nil,
                errorMessage: "上次更新的数据无法读取：\(error.localizedDescription)",
                requiresReauthentication: false
            )
        }
    }

    func update(_ request: CampusHeatmapRequest) async -> CampusHeatmapOutcome {
        do {
            let rooms: [EmptyClassroom]
            if await isDemoModeEnabled() {
                rooms = await demoEmptyClassrooms(request.date, request.startPeriod, request.endPeriod)
            } else {
                let html = try await fetchEmptyClassroomsHTML(
                    request.date,
                    request.startPeriod,
                    request.endPeriod
                )
                rooms = try parseEmptyClassrooms(html)
            }

            let updatedData = CachedCampusHeatmapData(
                date: request.date,
                startPeriod: request.startPeriod,
                endPeriod: request.endPeriod,
                updatedAt: now(),
                availableRooms: rooms
            )

            do {
                try await cache.save(updatedData)
                return .success(updatedData)
            } catch {
                return .fallback(
                    storedData: updatedData,
                    errorMessage: "本次数据已更新，但未能保存到本机：\(error.localizedDescription)",
                    requiresReauthentication: false
                )
            }
        } catch {
            let needsLogin = requiresReauthentication(error)
            let requestMessage = needsLogin
                ? "教务登录状态已失效，请重新点击“更新数据”并登录。"
                : "更新失败：\(error.localizedDescription)"

            do {
                return .fallback(
                    storedData: try await cache.load(),
                    errorMessage: requestMessage,
                    requiresReauthentication: needsLogin
                )
            } catch let cacheError {
                return .fallback(
                    storedData: nil,
                    errorMessage: "\(requestMessage) 上次更新的数据也无法读取：\(cacheError.localizedDescription)",
                    requiresReauthentication: needsLogin
                )
            }
        }
    }
}

nonisolated struct SchoolDataCampusHeatmapCache: CampusHeatmapCaching {
    func load() async throws -> CachedCampusHeatmapData? {
        try await MainActor.run {
            try SchoolDataCache.loadCampusHeatmapData()
        }
    }

    func save(_ data: CachedCampusHeatmapData) async throws {
        try await MainActor.run {
            try SchoolDataCache.saveCampusHeatmapData(data)
        }
    }
}
