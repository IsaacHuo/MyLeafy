import XCTest
import CoreLocation
@testable import Leafy

final class WeatherServicingTests: XCTestCase {
    func testWeatherKitWeatherServiceReturnsLiveWeather() async throws {
        let service = WeatherKitWeatherService(
            locationProvider: { CLLocation(latitude: 40.006, longitude: 116.352) },
            fetchLiveWeather: { location in
                _ = location
                return CampusWeather(temperature: 21.5, condition: "晴朗")
            },
            cache: InMemoryCampusWeatherCache()
        )

        let weather = try await service.fetchCurrentWeather()

        XCTAssertEqual(weather, CampusWeather(temperature: 21.5, condition: "晴朗"))
    }

    func testWeatherKitWeatherServiceFallsBackToFreshCache() async throws {
        let cache = InMemoryCampusWeatherCache(
            weather: CampusWeather(temperature: 18, condition: "晴"),
            savedAt: Date()
        )
        let service = WeatherKitWeatherService(
            fetchLiveWeather: { _ in throw URLError(.badServerResponse) },
            cache: cache
        )

        let weather = try await service.fetchCurrentWeather()

        XCTAssertEqual(weather, CampusWeather(temperature: 18, condition: "晴"))
    }

    func testCampusWeatherFunctionResponseDecodesWeather() throws {
        let data = Data("""
        {
          "temperature": 25.4,
          "condition_key": "多云",
          "observed_at": "2026-05-26T14:30:00.000Z",
          "source": "amap-live",
          "is_stale": false
        }
        """.utf8)

        let response = try JSONDecoder().decode(CampusWeatherFunctionResponse.self, from: data)
        let weather = response.campusWeather

        XCTAssertEqual(weather.temperature, 25.4)
        XCTAssertEqual(weather.condition, L10n.text("多云"))
    }



    func testWeatherKitWeatherServiceThrowsWhenCacheExpired() async {
        let cache = InMemoryCampusWeatherCache(
            weather: CampusWeather(temperature: 18, condition: "晴"),
            savedAt: Date(timeIntervalSinceNow: -(7 * 60 * 60))
        )
        let service = WeatherKitWeatherService(
            fetchLiveWeather: { _ in throw URLError(.badServerResponse) },
            cache: cache
        )

        do {
            _ = try await service.fetchCurrentWeather()
            XCTFail("Expected expired cache to rethrow the remote error.")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .badServerResponse)
        }
    }

    func testCachedTemperatureSnapshotPreservesObservationTimeAndExpires() throws {
        let suite = "WeatherSnapshot-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cache = UserDefaultsCampusWeatherCache(userDefaults: defaults)
        cache.save(.init(temperature: 18, condition: "晴"))
        let initial = try XCTUnwrap(cache.currentTemperatureSnapshot(maxAge: 60))
        let later = try XCTUnwrap(cache.currentTemperatureSnapshot(maxAge: 60, now: initial.observedAt.addingTimeInterval(30)))
        XCTAssertEqual(later.observedAt, initial.observedAt)
        XCTAssertEqual(later.temperature, 18)
        XCTAssertNil(cache.currentTemperatureSnapshot(maxAge: 60, now: initial.observedAt.addingTimeInterval(61)))
    }

    @MainActor
    func testReusedDefaultWeatherServiceWritesOnlyCurrentIdentityCache() async throws {
        let manager = ActiveCampusContext.networkManager
        let service = WeatherKitWeatherService(fetchLiveWeather: { _ in .init(temperature: 21, condition: "晴") })
        var keys: [String] = []
        defer {
            for key in keys { UserDefaults.standard.removeObject(forKey: key) }
            manager.clearSession()
        }
        for id in ["weather-scope-a", "weather-scope-b"] {
            manager.persistAuthenticatedIdentity(eduID: id, displayName: id)
            let key = CampusScopedDefaults.key("campusWeather.cache.v1")
            keys.append(key)
            _ = try await service.fetchCurrentWeather()
            XCTAssertNotNil(UserDefaults.standard.data(forKey: key))
        }
        XCTAssertNotEqual(keys[0], keys[1])
    }

    @MainActor
    func testOldWeatherResponseCannotWriteAfterIdentityChanges() async {
        let manager = ActiveCampusContext.networkManager
        manager.persistAuthenticatedIdentity(eduID: "weather-old", displayName: "Old")
        let oldKey = CampusScopedDefaults.key("campusWeather.cache.v1")
        defer { UserDefaults.standard.removeObject(forKey: oldKey); manager.clearSession() }
        let service = WeatherKitWeatherService(fetchLiveWeather: { _ in
            await MainActor.run { ActiveCampusContext.networkManager.persistAuthenticatedIdentity(eduID: "weather-new", displayName: "New") }
            return .init(temperature: 21, condition: "晴")
        })
        do { _ = try await service.fetchCurrentWeather(); XCTFail("Old response must cancel") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(UserDefaults.standard.data(forKey: oldKey))
    }


}

private nonisolated final class InMemoryCampusWeatherCache: CampusWeatherCaching, @unchecked Sendable {
    private let weather: CampusWeather?
    private let savedAt: Date?

    init(weather: CampusWeather? = nil, savedAt: Date? = nil) {
        self.weather = weather
        self.savedAt = savedAt
    }

    func save(_ weather: CampusWeather) {}

    func currentWeather(maxAge: TimeInterval) -> CampusWeather? {
        guard let weather, let savedAt, Date().timeIntervalSince(savedAt) <= maxAge else {
            return nil
        }

        return weather
    }
}
