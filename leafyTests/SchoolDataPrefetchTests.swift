import SwiftData
import XCTest
@testable import Leafy

final class SchoolDataPrefetchTests: XCTestCase {
    @MainActor
    func testForegroundPrefetchStartsAndThenUsesSuccessCooldown() async throws {
        defer { cleanupSchoolSession() }
        activateBJFUIdentity()
        let defaults = try makeDefaults()
        var now = Date(timeIntervalSince1970: 1_000)
        let coordinator = SchoolDataPrefetchCoordinator(userDefaults: defaults, now: { now })
        let context = try makeModelContainer().mainContext
        var syncCount = 0

        let result = coordinator.prefetchIfNeeded(
            modelContext: context,
            language: .zhHans,
            trigger: .foreground
        ) { _, _ in
            syncCount += 1
            return .success("ok")
        }

        XCTAssertEqual(result, .started)
        await waitUntil { syncCount == 1 }

        now = now.addingTimeInterval(60)
        XCTAssertEqual(
            coordinator.prefetchIfNeeded(
                modelContext: context,
                language: .zhHans,
                trigger: .foreground
            ) { _, _ in
                syncCount += 1
                return .success("should not run")
            },
            .skipped(.successCooldown)
        )
        XCTAssertEqual(syncCount, 1)
    }

    @MainActor
    func testLoginPrefetchBypassesSuccessCooldown() async throws {
        defer { cleanupSchoolSession() }
        activateBJFUIdentity()
        let defaults = try makeDefaults()
        var now = Date(timeIntervalSince1970: 2_000)
        let coordinator = SchoolDataPrefetchCoordinator(userDefaults: defaults, now: { now })
        let context = try makeModelContainer().mainContext
        var syncCount = 0

        XCTAssertEqual(
            coordinator.prefetchIfNeeded(
                modelContext: context,
                language: .zhHans,
                trigger: .foreground
            ) { _, _ in
                syncCount += 1
                return .success("ok")
            },
            .started
        )
        await waitUntil { syncCount == 1 }

        now = now.addingTimeInterval(60)
        XCTAssertEqual(
            coordinator.prefetchIfNeeded(
                modelContext: context,
                language: .zhHans,
                trigger: .login
            ) { _, _ in
                syncCount += 1
                return .success("login ok")
            },
            .started
        )
        await waitUntil { syncCount == 2 }
    }

    @MainActor
    func testSemesterChangePrefetchBypassesSuccessCooldown() async throws {
        defer { cleanupSchoolSession() }
        activateBJFUIdentity()
        let defaults = try makeDefaults()
        var now = Date(timeIntervalSince1970: 2_500)
        let coordinator = SchoolDataPrefetchCoordinator(userDefaults: defaults, now: { now })
        let context = try makeModelContainer().mainContext
        var syncCount = 0

        XCTAssertEqual(
            coordinator.prefetchIfNeeded(
                modelContext: context,
                language: .zhHans,
                trigger: .foreground
            ) { _, _ in
                syncCount += 1
                return .success("current semester")
            },
            .started
        )
        await waitUntil { syncCount == 1 }

        now = now.addingTimeInterval(60)
        XCTAssertEqual(
            coordinator.prefetchIfNeeded(
                modelContext: context,
                language: .zhHans,
                trigger: .semesterChanged
            ) { _, _ in
                syncCount += 1
                return .success("next semester")
            },
            .started
        )
        await waitUntil { syncCount == 2 }
    }

    @MainActor
    func testGraduateForegroundPrefetchStartsTimetableSync() async throws {
        defer { cleanupSchoolSession() }
        activateBJFUIdentity(portal: .graduate)
        let coordinator = SchoolDataPrefetchCoordinator(userDefaults: try makeDefaults())
        let context = try makeModelContainer().mainContext
        var syncCount = 0

        XCTAssertEqual(
            coordinator.prefetchIfNeeded(
                modelContext: context,
                language: .zhHans,
                trigger: .foreground
            ) { _, _ in
                syncCount += 1
                return .success("graduate timetable")
            },
            .started
        )
        await waitUntil { syncCount == 1 }
    }

    @MainActor
    func testFailureCooldownAfterLoginRequiredOutcome() async throws {
        defer { cleanupSchoolSession() }
        activateBJFUIdentity()
        let defaults = try makeDefaults()
        var now = Date(timeIntervalSince1970: 3_000)
        let coordinator = SchoolDataPrefetchCoordinator(userDefaults: defaults, now: { now })
        let context = try makeModelContainer().mainContext
        var syncCount = 0

        XCTAssertEqual(
            coordinator.prefetchIfNeeded(
                modelContext: context,
                language: .zhHans,
                trigger: .foreground
            ) { _, _ in
                syncCount += 1
                return .needsLogin
            },
            .started
        )
        await waitUntil { syncCount == 1 }

        now = now.addingTimeInterval(60)
        XCTAssertEqual(
            coordinator.prefetchIfNeeded(
                modelContext: context,
                language: .zhHans,
                trigger: .foreground
            ) { _, _ in
                syncCount += 1
                return .success("should not run")
            },
            .skipped(.failureCooldown)
        )
        XCTAssertEqual(syncCount, 1)
    }

    @MainActor
    func testCustomCampusSkipsSchoolSystemPrefetch() throws {
        defer { cleanupSchoolSession() }
        activateCustomIdentity()
        let coordinator = SchoolDataPrefetchCoordinator(userDefaults: try makeDefaults())
        let context = try makeModelContainer().mainContext

        XCTAssertEqual(
            coordinator.prefetchIfNeeded(
                modelContext: context,
                language: .zhHans,
                trigger: .foreground
            ) { _, _ in
                XCTFail("Custom campus should not run school sync.")
                return .success("unexpected")
            },
            .skipped(.customCampus)
        )
    }

    @MainActor
    func testAlreadyRunningSkipsSecondPrefetch() async throws {
        defer { cleanupSchoolSession() }
        activateBJFUIdentity()
        let coordinator = SchoolDataPrefetchCoordinator(userDefaults: try makeDefaults())
        let context = try makeModelContainer().mainContext
        var syncStarted = false
        var continuation: CheckedContinuation<SchoolDataSyncOutcome, Never>?

        XCTAssertEqual(
            coordinator.prefetchIfNeeded(
                modelContext: context,
                language: .zhHans,
                trigger: .foreground
            ) { _, _ in
                syncStarted = true
                return await withCheckedContinuation { continuation = $0 }
            },
            .started
        )
        await waitUntil { syncStarted }

        XCTAssertEqual(
            coordinator.prefetchIfNeeded(
                modelContext: context,
                language: .zhHans,
                trigger: .foreground
            ) { _, _ in
                XCTFail("Second prefetch should not start while first is active.")
                return .success("unexpected")
            },
            .skipped(.alreadyRunning)
        )

        continuation?.resume(returning: .success("ok"))
        await waitUntil { continuation != nil }
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "SchoolDataPrefetchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeModelContainer() throws -> ModelContainer {
        let schema = Schema([Course.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @MainActor
    private func activateBJFUIdentity(portal: SchoolPortal = .undergraduate) {
        let manager = ActiveCampusContext.networkManager
        manager.currentPortal = portal
        manager.persistAuthenticatedIdentity(
            eduID: "prefetch-test-\(UUID().uuidString)",
            displayName: "Prefetch Test"
        )
        manager.isLoggedIn = true
    }

    @MainActor
    private func activateCustomIdentity() {
        CampusIdentityStore.activate(
            CampusIdentity(
                campusID: .custom,
                eduID: "custom-\(UUID().uuidString)",
                displayName: "Custom Test",
                portal: .undergraduate,
                kind: .customSupabase
            )
        )
    }

    @MainActor
    private func cleanupSchoolSession() {
        SchoolDataPrefetchCoordinator.shared.cancel()
        ActiveCampusContext.networkManager.clearSession()
    }

    @MainActor
    private func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async {
        for _ in 0..<20 {
            if predicate() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
