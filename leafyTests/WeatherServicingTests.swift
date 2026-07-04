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

    func testSupabaseWeatherServiceFallsBackToFreshCache() async throws {
        let cache = InMemoryCampusWeatherCache(
            weather: CampusWeather(temperature: 18, condition: "晴"),
            savedAt: Date()
        )
        let service = SupabaseWeatherService(
            configProvider: { WeatherServicingTests.makeTestConfig() },
            fetchRemoteWeather: { _ in throw URLError(.badServerResponse) },
            cache: cache
        )

        let weather = try await service.fetchCurrentWeather()

        XCTAssertEqual(weather, CampusWeather(temperature: 18, condition: "晴"))
    }

    func testSupabaseWeatherServiceThrowsWhenCacheExpired() async {
        let cache = InMemoryCampusWeatherCache(
            weather: CampusWeather(temperature: 18, condition: "晴"),
            savedAt: Date(timeIntervalSinceNow: -(7 * 60 * 60))
        )
        let service = SupabaseWeatherService(
            configProvider: { WeatherServicingTests.makeTestConfig() },
            fetchRemoteWeather: { _ in throw URLError(.badServerResponse) },
            cache: cache
        )

        do {
            _ = try await service.fetchCurrentWeather()
            XCTFail("Expected expired cache to rethrow the remote error.")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .badServerResponse)
        }
    }

    nonisolated private static func makeTestConfig() -> SupabaseConfig {
        SupabaseConfig(
            url: URL(string: "https://example.supabase.co")!,
            publishableKey: "test-key",
            bootstrapFunctionName: "community-bootstrap-user",
            feedFunctionName: "community-feed",
            emailLookupFunctionName: "campus-email-lookup",
            weatherFunctionName: "campus-weather",
            campusAIFunctionName: "campus-ai-assistant",
            edgeRegion: "ap-northeast-1",
            communityAPIBaseURL: nil
        )
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
