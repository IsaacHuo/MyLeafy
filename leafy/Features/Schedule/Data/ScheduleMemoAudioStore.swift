import Foundation

enum ScheduleMemoAudioStoreError: LocalizedError {
    case unreadableRecording
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .unreadableRecording:
            return "无法读取这段录音，请重新录制。"
        case .saveFailed:
            return "录音保存失败，请重试。"
        }
    }
}

enum ScheduleMemoAudioStore {
    static let maximumDuration: TimeInterval = 10 * 60

    static func temporaryRecordingURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ScheduleMemoRecording-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
    }

    static func importRecording(
        from sourceURL: URL,
        identity: CampusIdentity? = CampusIdentityStore.currentIdentity()
    ) throws -> String {
        let fileManager = FileManager.default
        guard fileManager.isReadableFile(atPath: sourceURL.path(percentEncoded: false)) else {
            throw ScheduleMemoAudioStoreError.unreadableRecording
        }

        let directory = directoryURL(identity: identity)
        let filename = "\(UUID().uuidString).m4a"
        let destination = directory.appendingPathComponent(filename, isDirectory: false)
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
            try fileManager.copyItem(at: sourceURL, to: destination)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: destination.path(percentEncoded: false)
            )
            return filename
        } catch {
            try? fileManager.removeItem(at: destination)
            throw ScheduleMemoAudioStoreError.saveFailed
        }
    }

    static func fileURL(
        named filename: String,
        in directory: URL? = nil,
        identity: CampusIdentity? = CampusIdentityStore.currentIdentity()
    ) -> URL? {
        let url = (directory ?? directoryURL(identity: identity))
            .appendingPathComponent(filename, isDirectory: false)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    static func deleteFile(named filename: String, in directory: URL? = nil) throws {
        let url = (directory ?? directoryURL()).appendingPathComponent(filename, isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: url)
    }

    static func deleteFiles(named filenames: [String], in directory: URL? = nil) throws {
        for filename in filenames {
            try deleteFile(named: filename, in: directory)
        }
    }

    static func deleteAllFiles(in directory: URL? = nil) throws {
        let url = directory ?? directoryURL()
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: url)
    }

    static func directoryURL(identity: CampusIdentity? = CampusIdentityStore.currentIdentity()) -> URL {
        if let identity,
           let scopedStore = CampusStoreScope.scopedStoreURL(for: identity) {
            return scopedStore.deletingLastPathComponent()
                .appendingPathComponent("ScheduleMemoAudio", isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ScheduleMemoAudio", isDirectory: true)
    }
}
