import XCTest
@testable import Leafy

final class WidgetWeatherSnapshotTests: XCTestCase {
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
}
