import SwiftUI

struct LeafyWidgetBackground: View {
    let palette: LeafyWidgetPalette

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    palette.surface,
                    palette.brand.opacity(0.10),
                    palette.brand.opacity(0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    palette.surface.opacity(0.58),
                    palette.brand.opacity(0.15)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

struct LeafyWidgetPalette {
    let surface: Color
    let brand: Color
    let primary: Color
    let secondary: Color
    let tertiary: Color
    let courseAccents: [Color]

    init(theme: LeafyWidgetThemeSnapshot, colorScheme: ColorScheme) {
        let base = LeafyWidgetThemePalette.baseColor(for: theme)
        let emphasis = LeafyWidgetThemePalette.emphasisColor(for: theme)
        let textBase = Self.mix(base, with: .black, amount: 0.76)
        let secondaryText = Self.mix(base, with: .black, amount: 0.58)
        let tertiaryText = Self.mix(base, with: .black, amount: 0.44)

        surface = colorScheme == .dark ? Color(white: 0.08) : .white
        brand = Self.color(colorScheme == .dark ? base : emphasis)
        primary = colorScheme == .dark ? .white : Self.color(textBase)
        secondary = colorScheme == .dark ? .white.opacity(0.78) : Self.color(secondaryText)
        tertiary = colorScheme == .dark ? .white.opacity(0.58) : Self.color(tertiaryText)
        courseAccents = LeafyWidgetThemePalette.courseAccentColors(for: theme).map(Self.color)
    }

    nonisolated private static func color(_ components: LeafyWidgetThemePalette.ColorComponents) -> Color {
        Color(
            red: components.normalizedRed,
            green: components.normalizedGreen,
            blue: components.normalizedBlue
        )
    }

    nonisolated private static func mix(
        _ base: LeafyWidgetThemePalette.ColorComponents,
        with target: LeafyWidgetThemePalette.ColorComponents,
        amount: Double
    ) -> LeafyWidgetThemePalette.ColorComponents {
        LeafyWidgetThemePalette.ColorComponents(
            red: base.red + (target.red - base.red) * amount,
            green: base.green + (target.green - base.green) * amount,
            blue: base.blue + (target.blue - base.blue) * amount
        )
    }
}

private extension LeafyWidgetThemePalette.ColorComponents {
    static let black = LeafyWidgetThemePalette.ColorComponents(red: 0, green: 0, blue: 0)
}

enum LeafyWidgetWeatherService {
    private static let cacheMaxAge: TimeInterval = 6 * 60 * 60

    static func currentTemperatureText() async -> String {
        do {
            let temperature = try await fetchCurrentTemperature()
            return "\(Int(temperature.rounded()))°"
        } catch {
            if let cached = cachedTemperature(maxAge: cacheMaxAge) {
                return "\(Int(cached.rounded()))°"
            }
            return "--°"
        }
    }

    private static func fetchCurrentTemperature() async throws -> Double {
        let config = try LeafyWidgetSupabaseWeatherConfig.load()
        var components = URLComponents(url: config.url.appending(path: "functions/v1/\(config.weatherFunctionName)"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "forceFunctionRegion", value: config.edgeRegion)]
        guard let url = components?.url else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, timeoutInterval: 6)
        request.httpMethod = "GET"
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.publishableKey)", forHTTPHeaderField: "Authorization")
        request.setValue(config.edgeRegion, forHTTPHeaderField: "x-region")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let temperature = try JSONDecoder().decode(LeafyWidgetWeatherResponse.self, from: data).temperature
        saveTemperature(temperature)
        return temperature
    }

    private static func saveTemperature(_ temperature: Double) {
        let cached = LeafyWidgetCachedWeather(temperature: temperature, savedAt: Date())
        guard let data = try? JSONEncoder().encode(cached) else { return }
        UserDefaults.standard.set(data, forKey: "leafyWidget.weather.cache.v1")
    }

    private static func cachedTemperature(maxAge: TimeInterval) -> Double? {
        guard let data = UserDefaults.standard.data(forKey: "leafyWidget.weather.cache.v1"),
              let cached = try? JSONDecoder().decode(LeafyWidgetCachedWeather.self, from: data),
              Date().timeIntervalSince(cached.savedAt) <= maxAge else {
            return nil
        }

        return cached.temperature
    }
}

private struct LeafyWidgetWeatherResponse: Decodable {
    let temperature: Double
}

private struct LeafyWidgetCachedWeather: Codable {
    let temperature: Double
    let savedAt: Date
}

private struct LeafyWidgetSupabaseWeatherConfig {
    let url: URL
    let publishableKey: String
    let weatherFunctionName: String
    let edgeRegion: String

    static func load(bundle: Bundle = .main) throws -> LeafyWidgetSupabaseWeatherConfig {
        let rawURL = sanitizedBuildSetting(bundle.object(forInfoDictionaryKey: "SUPABASE_URL"))
        let rawKey = sanitizedBuildSetting(bundle.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY"))
        let functionName = sanitizedBuildSetting(bundle.object(forInfoDictionaryKey: "SUPABASE_WEATHER_FUNCTION"))
        let edgeRegion = sanitizedBuildSetting(bundle.object(forInfoDictionaryKey: "SUPABASE_COMMUNITY_EDGE_REGION"))

        guard let url = URL(string: rawURL), !rawKey.isEmpty else {
            throw URLError(.badURL)
        }

        return LeafyWidgetSupabaseWeatherConfig(
            url: url,
            publishableKey: rawKey,
            weatherFunctionName: functionName.isEmpty ? "campus-weather" : functionName,
            edgeRegion: edgeRegion.isEmpty ? "ap-northeast-1" : edgeRegion
        )
    }

    private static func sanitizedBuildSetting(_ value: Any?) -> String {
        let raw = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let placeholders = [
            "https://your-project-ref.supabase.co",
            "sb_publishable_xxx"
        ]

        if raw.isEmpty || raw.hasPrefix("$(") || placeholders.contains(raw) {
            return ""
        }

        return raw
    }
}
