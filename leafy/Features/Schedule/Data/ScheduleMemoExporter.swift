import Foundation

enum ScheduleMemoExportError: LocalizedError {
    case noMemos
    case noImages

    var errorDescription: String? {
        switch self {
        case .noMemos:
            return "当前没有可以导出的随记。"
        case .noImages:
            return "当前随记中没有可以导出的图片。"
        }
    }
}

enum ScheduleMemoExporter {
    static func exportText(memos: [ScheduleMemo], now: Date = Date()) throws -> URL {
        let activeMemos = sortedActiveMemos(memos)
        guard !activeMemos.isEmpty else { throw ScheduleMemoExportError.noMemos }

        var sections = [
            "MyLeafy 随记导出",
            "导出时间：\(formattedDate(now))",
            "随记数量：\(activeMemos.count)"
        ]

        sections.append(contentsOf: activeMemos.map { memo in
            var lines = [
                "----------------------------------------",
                "创建时间：\(formattedDate(memo.createdAt))"
            ]
            if memo.kind == .article {
                lines.append("标题：\(memo.displayTitle)")
            }
            if !memo.tags.isEmpty {
                lines.append("标签：\(memo.tags.map { "#\($0)" }.joined(separator: " "))")
            }
            lines.append("")
            lines.append(memo.body)
            return lines.joined(separator: "\n")
        })

        let contents = "\u{feff}" + sections.joined(separator: "\n") + "\n"
        let url = exportURL(prefix: "MyLeafy-Memos", pathExtension: "txt", now: now)
        try Data(contents.utf8).write(to: url, options: .atomic)
        return url
    }

    static func exportImageArchive(
        memos: [ScheduleMemo],
        images: [ScheduleMemoImage],
        now: Date = Date()
    ) throws -> URL {
        let activeMemos = sortedActiveMemos(memos)
        guard !activeMemos.isEmpty else { throw ScheduleMemoExportError.noMemos }

        let memoOrder = Dictionary(uniqueKeysWithValues: activeMemos.enumerated().map { ($0.element.id, $0.offset) })
        let files = images
            .filter { memoOrder[$0.memoID] != nil }
            .sorted {
                let lhsMemoOrder = memoOrder[$0.memoID] ?? .max
                let rhsMemoOrder = memoOrder[$1.memoID] ?? .max
                if lhsMemoOrder != rhsMemoOrder { return lhsMemoOrder < rhsMemoOrder }
                return $0.sortOrder < $1.sortOrder
            }
            .compactMap { image -> (path: String, data: Data)? in
                guard let data = ScheduleMemoImageStore.data(named: image.localFilename) else { return nil }
                let index = String(format: "%02d", image.sortOrder + 1)
                return (
                    path: "images/\(image.memoID.uuidString)/\(index)-\(image.localFilename)",
                    data: data
                )
            }

        guard !files.isEmpty else { throw ScheduleMemoExportError.noImages }
        let archive = ZipArchiveWriter.makeArchive(files: files, date: now)
        let url = exportURL(prefix: "MyLeafy-Memo-Images", pathExtension: "zip", now: now)
        try archive.write(to: url, options: .atomic)
        return url
    }

    private static func sortedActiveMemos(_ memos: [ScheduleMemo]) -> [ScheduleMemo] {
        memos.filter { !$0.isTrashed }.sorted { $0.createdAt > $1.createdAt }
    }

    private static func formattedDate(_ date: Date) -> String {
        date.formatted(date: .numeric, time: .shortened)
    }

    private static func exportURL(prefix: String, pathExtension: String, now: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(formatter.string(from: now))")
            .appendingPathExtension(pathExtension)
    }
}
