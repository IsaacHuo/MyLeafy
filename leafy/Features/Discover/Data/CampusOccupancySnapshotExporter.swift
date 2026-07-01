import Foundation
import OSLog

#if DEBUG
enum CampusOccupancySnapshotExporter {
    static let launchArgument = "--export-campus-occupancy-snapshot"
    private static let logger = Logger(subsystem: "com.isaachuo.leafy", category: "CampusHeatmap")

    @MainActor
    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains(launchArgument) else { return }

        Task {
            do {
                let url = try await export()
                logger.info("Campus occupancy snapshot exported to \(url.path, privacy: .public)")
            } catch {
                logger.error("Campus occupancy snapshot export failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func export() async throws -> URL {
        let networkManager = ActiveCampusContext.networkManager
        guard await networkManager.verifyAuthenticatedSession(retryCount: 1) else {
            logger.error("Campus occupancy snapshot export skipped because the school session is not authenticated. Re-login in the simulator, then launch with \(launchArgument, privacy: .public).")
            throw SchoolNetworkError.sessionExpired
        }

        let config = await SemesterConfig.refreshRemoteIfAvailable(force: true)
        let totalSlots = config.supportedWeeks * 7 * 12
        var slots: [CampusOccupancyArchiveSlot] = []
        slots.reserveCapacity(totalSlots)

        logger.info("Campus occupancy snapshot export started for semester \(config.semesterID, privacy: .public), \(totalSlots) slots")

        for week in 1...config.supportedWeeks {
            for day in 1...7 {
                let date = dateFor(week: week, day: day, config: config)
                for period in 1...12 {
                    let html = try await networkManager.fetchEmptyClassrooms(
                        date: date,
                        start: period,
                        end: period
                    )
                    let rooms = try HTMLParser.parseEmptyClassrooms(html: html)
                    let snapshot = CampusOccupancySnapshot.inferred(fromAvailableRooms: rooms)
                    slots.append(CampusOccupancyArchiveSlot(
                        week: week,
                        day: day,
                        period: period,
                        snapshot: snapshot
                    ))
                    if slots.count % 24 == 0 || slots.count == totalSlots {
                        logger.info("Campus occupancy snapshot export progress \(slots.count, privacy: .public)/\(totalSlots, privacy: .public), week \(week, privacy: .public), day \(day, privacy: .public), period \(period, privacy: .public)")
                    }
                }
            }
        }

        let archive = CampusOccupancyArchive(
            semesterID: config.semesterID,
            generatedAt: Date(),
            slots: slots
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(archive)

        let filename = "\(CampusOccupancyBundleStore.resourceName).json"
        let documentsURL = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let outputURL = documentsURL.appendingPathComponent(filename)
        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }

    private static func dateFor(week: Int, day: Int, config: SemesterRuntimeConfig) -> Date {
        Calendar.current.date(
            byAdding: .day,
            value: (week - 1) * 7 + (day - 1),
            to: config.semesterStartDate
        ) ?? config.semesterStartDate
    }
}
#endif
