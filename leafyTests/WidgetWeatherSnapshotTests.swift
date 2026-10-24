import XCTest
@testable import Leafy

final class WidgetWeatherSnapshotTests: XCTestCase {
    @MainActor
    func testWidgetUsesCurrentLocationCacheAndPreservesActualObservationTime() throws {
        let defaults = try weatherDefaults()
        let now = Date()
        let observedAt = now.addingTimeInterval(-2 * 3600)
        UserDefaultsCampusWeatherCache(userDefaults: defaults).save(.init(temperature: 5, condition: "晴"))
        UserDefaultsTimetableWeatherCache(userDefaults: defaults).save(weather(observedAt: observedAt))

        let snapshot = try XCTUnwrap(LeafyWidgetSnapshotBuilder.cachedWeatherSnapshot(userDefaults: defaults))
        XCTAssertEqual(snapshot.celsius, 22.6)
        XCTAssertEqual(snapshot.observedAt.timeIntervalSince1970, observedAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(snapshot.temperatureText(at: now), "23°")
        XCTAssertEqual(snapshot.temperatureText(at: observedAt.addingTimeInterval(6 * 3600)), "--°")
    }

    @MainActor
    func testWidgetDoesNotSubstituteShareImageWeatherForMissingLocationWeather() throws {
        let defaults = try weatherDefaults()
        UserDefaultsCampusWeatherCache(userDefaults: defaults).save(.init(temperature: 5, condition: "晴"))
        XCTAssertNil(LeafyWidgetSnapshotBuilder.cachedWeatherSnapshot(userDefaults: defaults))
    }

    @MainActor
    func testSavingOldObservationDoesNotExtendWidgetWeatherValidity() throws {
        let defaults = try weatherDefaults()
        let now = Date()
        UserDefaultsTimetableWeatherCache(userDefaults: defaults)
            .save(weather(observedAt: now.addingTimeInterval(-7 * 3600)))
        let snapshot = try XCTUnwrap(LeafyWidgetSnapshotBuilder.cachedWeatherSnapshot(userDefaults: defaults))
        XCTAssertEqual(snapshot.temperatureText(at: now), "--°")
    }

    @MainActor
    func testWidgetDoesNotReadPreviousIdentityWeather() throws {
        let defaults = try weatherDefaults()
        let first = CampusIdentity(campusID: .bjfu, eduID: "weather-a", displayName: nil, portal: .undergraduate)
        let second = CampusIdentity(campusID: .bjfu, eduID: "weather-b", displayName: nil, portal: .undergraduate)
        CampusIdentityStore.activate(first, defaults: defaults)
        UserDefaultsTimetableWeatherCache(userDefaults: defaults).save(weather(observedAt: Date()))
        XCTAssertNotNil(LeafyWidgetSnapshotBuilder.cachedWeatherSnapshot(userDefaults: defaults))
        CampusIdentityStore.activate(second, defaults: defaults)
        XCTAssertNil(LeafyWidgetSnapshotBuilder.cachedWeatherSnapshot(userDefaults: defaults))
    }

    func testArchiveWithoutWeatherStillDecodes() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(makeWidgetSignatureArchive())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "weather")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(
            LeafyWidgetSnapshotArchive.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertNil(archive.weather)
        XCTAssertEqual(archive.temperatureText(at: archive.generatedAt), "--°")
    }

    func testWeatherExpirationAndInvalidValuesNeverTrap() {
        let now = Date(timeIntervalSince1970: 100)
        let weather = LeafyWidgetWeatherSnapshot(celsius: 22.6, observedAt: now)
        XCTAssertEqual(weather.temperatureText(at: now), "23°")
        XCTAssertEqual(weather.temperatureText(at: now.addingTimeInterval(6 * 3600)), "--°")
        XCTAssertEqual(weather.temperatureText(at: now.addingTimeInterval(-1)), "--°")
        for value in [Double.nan, .infinity, -.infinity, Double.greatestFiniteMagnitude] {
            XCTAssertEqual(LeafyWidgetWeatherSnapshot(celsius: value, observedAt: now).temperatureText(at: now), "--°")
        }
    }

    func testUnauthenticatedArchiveDoesNotDisplayPreviousWeather() {
        let now = Date(timeIntervalSince1970: 100)
        var archive = makeWidgetSignatureArchive(generatedAt: now)
        archive.weather = .init(celsius: 20, observedAt: now)
        XCTAssertEqual(archive.temperatureText(at: now), "20°")
        archive.isAuthenticated = false
        XCTAssertEqual(archive.temperatureText(at: now), "--°")
    }

    func testTimelineIncludesWeatherExpirationBoundary() {
        let now = Date(timeIntervalSince1970: 100)
        var archive = makeWidgetSignatureArchive(generatedAt: now)
        let expiration = now.addingTimeInterval(6 * 3600)
        archive.weather = .init(celsius: 20, observedAt: now)
        XCTAssertTrue(archive.timelineDates(from: now).contains(expiration))
        XCTAssertEqual(archive.temperatureText(at: expiration), "--°")
    }

    private func weatherDefaults() throws -> UserDefaults {
        let suite = "WidgetWeather-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func weather(observedAt: Date) -> TimetableWeatherSnapshot {
        TimetableWeatherSnapshot(temperature: 22.6, apparentTemperature: 18, condition: "多云", symbolName: "cloud",
                                 observedAt: observedAt, hourlyForecast: [], attribution: .appleWeather)
    }
}
