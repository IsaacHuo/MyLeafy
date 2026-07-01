import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct CommunityAvatarCache: Sendable {
    static let shared = CommunityAvatarCache()

    private let directory: URL

    init(directory: URL = CommunityAvatarCache.defaultDirectory()) {
        self.directory = directory
    }

    func data(for profile: CommunityProfile?) -> Data? {
        guard let url = cacheURL(for: profile) else { return nil }
        return try? Data(contentsOf: url)
    }

    func image(for profile: CommunityProfile?) -> UIImage? {
        guard let data = data(for: profile) else { return nil }
        return ImageDataDecoder.decodedImage(from: data)
    }

    func save(data: Data, for profile: CommunityProfile) throws {
        guard let url = cacheURL(for: profile) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try removeCachedAvatars(for: profile.id, keeping: profile.avatarPath)
        try data.write(to: url, options: [.atomic])
    }

    func removeCachedAvatars(for profileID: UUID, keeping avatarPath: String? = nil) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }

        let keepingName = avatarPath.flatMap { Self.cacheFileName(profileID: profileID, avatarPath: $0) }
        let prefix = profileID.uuidString.lowercased() + "-"
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )

        for url in urls where url.lastPathComponent.hasPrefix(prefix) && url.lastPathComponent != keepingName {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func cacheURL(for profile: CommunityProfile?) -> URL? {
        guard let profile,
              let avatarPath = profile.avatarPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !avatarPath.isEmpty,
              let fileName = Self.cacheFileName(profileID: profile.id, avatarPath: avatarPath) else {
            return nil
        }

        return directory.appendingPathComponent(fileName)
    }

    static func cacheFileName(profileID: UUID, avatarPath: String) -> String? {
        let trimmedPath = avatarPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return nil }

        let pathToken = Data(trimmedPath.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")

        return "\(profileID.uuidString.lowercased())-\(pathToken).jpg"
    }

    private static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("CommunityAvatars", isDirectory: true)
    }
}
