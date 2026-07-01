import Foundation
import CoreLocation
import Supabase
import WeatherKit

nonisolated struct CampusWeather: Equatable, Sendable {
    let temperature: Double
    let condition: String
}

protocol WeatherServicing: Sendable {
    func fetchCurrentWeather() async throws -> CampusWeather
}

nonisolated struct WeatherKitWeatherService: WeatherServicing {
    private let locationProvider: @Sendable () -> CLLocation
    private let fetchLiveWeather: @Sendable (CLLocation) async throws -> CampusWeather
    private let cache: CampusWeatherCaching

    nonisolated init(
        locationProvider: @escaping @Sendable () -> CLLocation = {
            let coordinate = ActiveCampusContext.descriptor.weatherCoordinate
            return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        },
        fetchLiveWeather: @escaping @Sendable (CLLocation) async throws -> CampusWeather = { location in
            let current = try await WeatherService.shared.weather(for: location, including: .current)
            return CampusWeather(
                temperature: current.temperature.converted(to: .celsius).value,
                condition: WeatherKitWeatherService.localizedCondition(
                    rawValue: current.condition.rawValue,
                    symbolName: current.symbolName
                )
            )
        },
        cache: CampusWeatherCaching = UserDefaultsCampusWeatherCache()
    ) {
        self.locationProvider = locationProvider
        self.fetchLiveWeather = fetchLiveWeather
        self.cache = cache
    }

    func fetchCurrentWeather() async throws -> CampusWeather {
        do {
            let weather = try await fetchLiveWeather(locationProvider())
            cache.save(weather)
            return weather
        } catch {
            if let cachedWeather = cache.currentWeather(maxAge: Self.cacheMaxAge) {
                return cachedWeather
            }
            throw error
        }
    }

    private static let cacheMaxAge: TimeInterval = 6 * 60 * 60

    private static func localizedCondition(rawValue: String, symbolName: String) -> String {
        let key = "\(rawValue) \(symbolName)".lowercased()

        if key.contains("thunder") || key.contains("storm") {
            return "雷雨"
        }
        if key.contains("snow") || key.contains("sleet") || key.contains("flurr") || key.contains("wintry") {
            return "雪"
        }
        if key.contains("rain") || key.contains("showers") || key.contains("drizzle") {
            return key.contains("drizzle") ? "毛毛雨" : "雨"
        }
        if key.contains("fog") || key.contains("haze") || key.contains("smoky") || key.contains("dust") {
            return "雾"
        }
        if key.contains("cloud") {
            return "多云"
        }
        if key.contains("clear") || key.contains("sun") || key.contains("hot") {
            return "晴"
        }

        return "天气"
    }
}

nonisolated struct SupabaseWeatherService: WeatherServicing {
    private let configProvider: @Sendable () throws -> SupabaseConfig
    private let fetchRemoteWeather: @Sendable (SupabaseConfig) async throws -> CampusWeatherFunctionResponse
    private let cache: CampusWeatherCaching

    nonisolated init(
        configProvider: @escaping @Sendable () throws -> SupabaseConfig = { try LeafySupabase.shared.requireConfig() },
        fetchRemoteWeather: @escaping @Sendable (SupabaseConfig) async throws -> CampusWeatherFunctionResponse = { config in
            let client = try LeafySupabase.shared.requireClient()
            return try await client.functions.invoke(
                config.weatherFunctionName,
                options: FunctionInvokeOptions(
                    method: .get,
                    region: config.edgeRegion
                )
            )
        },
        cache: CampusWeatherCaching = UserDefaultsCampusWeatherCache()
    ) {
        self.configProvider = configProvider
        self.fetchRemoteWeather = fetchRemoteWeather
        self.cache = cache
    }

    func fetchCurrentWeather() async throws -> CampusWeather {
        do {
            let config = try configProvider()
            let response = try await fetchRemoteWeather(config)
            let weather = response.campusWeather
            cache.save(weather)
            return weather
        } catch {
            if let cachedWeather = cache.currentWeather(maxAge: Self.cacheMaxAge) {
                return cachedWeather
            }
            throw error
        }
    }

    private static let cacheMaxAge: TimeInterval = 6 * 60 * 60
}

nonisolated struct CampusWeatherFunctionResponse: Decodable, Sendable {
    let temperature: Double
    let conditionKey: String
    let observedAt: String?
    let source: String?
    let isStale: Bool?

    var campusWeather: CampusWeather {
        CampusWeather(
            temperature: temperature,
            condition: CampusWeatherCondition.localizedText(for: conditionKey)
        )
    }

    enum CodingKeys: String, CodingKey {
        case temperature
        case conditionKey = "condition_key"
        case observedAt = "observed_at"
        case source
        case isStale = "is_stale"
    }
}

nonisolated protocol CampusWeatherCaching: Sendable {
    func save(_ weather: CampusWeather)
    func currentWeather(maxAge: TimeInterval) -> CampusWeather?
}

nonisolated struct UserDefaultsCampusWeatherCache: CampusWeatherCaching {
    private nonisolated(unsafe) let userDefaults: UserDefaults
    private let key: String

    nonisolated init(
        userDefaults: UserDefaults = .standard,
        key: String = "campusWeather.cache.v1"
    ) {
        self.userDefaults = userDefaults
        self.key = CampusScopedDefaults.key(key, defaults: userDefaults)
    }

    func save(_ weather: CampusWeather) {
        let cached = CachedCampusWeather(
            temperature: weather.temperature,
            condition: weather.condition,
            savedAt: Date()
        )

        guard let data = try? JSONEncoder().encode(cached) else {
            return
        }

        userDefaults.set(data, forKey: key)
    }

    func currentWeather(maxAge: TimeInterval) -> CampusWeather? {
        guard let data = userDefaults.data(forKey: key),
              let cached = try? JSONDecoder().decode(CachedCampusWeather.self, from: data),
              Date().timeIntervalSince(cached.savedAt) <= maxAge else {
            return nil
        }

        return CampusWeather(
            temperature: cached.temperature,
            condition: cached.condition
        )
    }
}

private nonisolated struct CachedCampusWeather: Codable {
    let temperature: Double
    let condition: String
    let savedAt: Date
}

nonisolated enum CampusWeatherCondition {
    static func localizedText(for key: String) -> String {
        switch key {
        case "晴", "多云", "阴", "雾", "毛毛雨", "雨", "雪", "雷雨", "天气":
            return L10n.text(key)
        default:
            return L10n.text("天气")
        }
    }
}
