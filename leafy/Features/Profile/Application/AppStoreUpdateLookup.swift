import Foundation

enum AppStoreUpdateLookup {
    static func appStoreURL(bundleIdentifier: String) async throws -> URL? {
        var lastError: Error?
        var seenCountryCodes: Set<String> = []
        let countryCodes: [String?] = [
            Locale.current.region?.identifier.lowercased(),
            "cn",
            nil
        ]

        for countryCode in countryCodes {
            let countryKey = countryCode ?? ""
            guard seenCountryCodes.insert(countryKey).inserted else { continue }

            do {
                if let url = try await lookupAppStoreURL(
                    bundleIdentifier: bundleIdentifier,
                    countryCode: countryCode
                ) {
                    return url
                }
            } catch {
                lastError = error
            }
        }

        if let lastError {
            throw lastError
        }

        return nil
    }

    static func reviewURL(from appStoreURL: URL) -> URL {
        guard var components = URLComponents(url: appStoreURL, resolvingAgainstBaseURL: false) else {
            return appStoreURL
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "action" }
        queryItems.append(URLQueryItem(name: "action", value: "write-review"))
        components.queryItems = queryItems

        return components.url ?? appStoreURL
    }

    static func preferredURL(from data: Data) throws -> URL? {
        let response = try JSONDecoder().decode(AppStoreLookupResponse.self, from: data)
        return response.results.first { $0.kind == "software" }?.trackViewURL
    }

    private static func lookupAppStoreURL(
        bundleIdentifier: String,
        countryCode: String?
    ) async throws -> URL? {
        guard var components = URLComponents(string: "https://itunes.apple.com/lookup") else {
            return nil
        }

        var queryItems = [
            URLQueryItem(name: "bundleId", value: bundleIdentifier),
            URLQueryItem(name: "entity", value: "software")
        ]
        if let countryCode, !countryCode.isEmpty {
            queryItems.append(URLQueryItem(name: "country", value: countryCode))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            return nil
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        return try preferredURL(from: data)
    }
}

private struct AppStoreLookupResponse: Decodable {
    let results: [AppStoreLookupResult]
}

private struct AppStoreLookupResult: Decodable {
    let kind: String?
    let trackViewURL: URL?

    private enum CodingKeys: String, CodingKey {
        case kind
        case trackViewURL = "trackViewUrl"
    }
}
