import BackgroundTasks
import OSLog
import SwiftData

@MainActor
final class ScheduleReportBackgroundRefreshCoordinator {
    static let shared = ScheduleReportBackgroundRefreshCoordinator()
    static let identifier = "com.isaachuo.leafy.schedule-refresh"

    private let logger = Logger(
        subsystem: "com.isaachuo.leafy",
        category: "ScheduleReportBackgroundRefresh"
    )
    private var isRegistered = false

    private init() {}

    func register() {
        guard !isRegistered, !AppRuntimeEnvironment.isRunningUnitTests else { return }
        isRegistered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.identifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                self.handle(refreshTask)
            }
        }
    }

    func schedule() {
        guard ScheduleReportSettingsStore.load().isEnabled,
              !AppRuntimeEnvironment.isRunningUnitTests else { return }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.identifier)
        let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            logger.error("Unable to schedule report refresh: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handle(_ backgroundTask: BGAppRefreshTask) {
        schedule()
        let work = Task { @MainActor in
            let setup = AppModelContainerFactory.make()
            let service = LeafyDependencies.live.timetableWeatherService
            let weather: TimetableWeatherSnapshot?
            if let cached = service.cachedWeather(maxAge: 30 * 60) {
                weather = cached
            } else if service.authorizationState() == .authorized {
                weather = try? await service.fetchCurrentWeather(requestsPermissionIfNeeded: false)
            } else {
                weather = nil
            }

            do {
                try await ScheduleReportNotificationManager.refreshIfEnabled(
                    modelContext: setup.container.mainContext,
                    weather: weather
                )
                backgroundTask.setTaskCompleted(success: true)
            } catch is CancellationError {
                backgroundTask.setTaskCompleted(success: false)
            } catch {
                logger.error("Background report refresh failed: \(error.localizedDescription, privacy: .public)")
                backgroundTask.setTaskCompleted(success: false)
            }
        }

        backgroundTask.expirationHandler = {
            work.cancel()
        }
    }
}
