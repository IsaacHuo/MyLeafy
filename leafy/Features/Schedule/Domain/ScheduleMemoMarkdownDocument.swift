import Foundation

nonisolated struct ScheduleMemoInlineResourceReference: Hashable, Sendable {
    enum Kind: String, Sendable {
        case image
        case attachment
    }

    let kind: Kind
    let id: UUID

    var marker: String {
        switch kind {
        case .image:
            return "![图片](leafy-memo://image/\(id.uuidString.lowercased()))"
        case .attachment:
            return "[附件](leafy-memo://attachment/\(id.uuidString.lowercased()))"
        }
    }
}

nonisolated struct ScheduleMemoMarkdownBlock: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case quote(String)
        case unorderedList(String)
        case orderedList(number: Int, text: String)
        case task(isCompleted: Bool, text: String)
        case code(String)
        case divider
        case resource(ScheduleMemoInlineResourceReference)
    }

    let id: Int
    let kind: Kind

    var plainText: String {
        switch kind {
        case .heading(_, let text), .paragraph(let text), .quote(let text),
             .unorderedList(let text), .orderedList(_, let text):
            return text
        case .task(let isCompleted, let text):
            return "\(isCompleted ? "已完成" : "待办") \(text)"
        case .code(let text):
            return text
        case .divider:
            return ""
        case .resource:
            return ""
        }
    }
}

nonisolated enum ScheduleMemoMarkdownParser {
    static func blocks(in source: String) -> [ScheduleMemoMarkdownBlock] {
        var kinds: [ScheduleMemoMarkdownBlock.Kind] = []
        var paragraph: [String] = []
        var code: [String] = []
        var isInCodeBlock = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            kinds.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph.removeAll()
        }

        for line in source.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if isInCodeBlock {
                    kinds.append(.code(code.joined(separator: "\n")))
                    code.removeAll()
                } else {
                    flushParagraph()
                }
                isInCodeBlock.toggle()
                continue
            }

            if isInCodeBlock {
                code.append(line)
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if let reference = resourceReference(in: trimmed) {
                flushParagraph()
                kinds.append(.resource(reference))
            } else if isDivider(trimmed) {
                flushParagraph()
                kinds.append(.divider)
            } else if let task = taskItem(in: trimmed) {
                flushParagraph()
                kinds.append(.task(isCompleted: task.isCompleted, text: task.text))
            } else if let heading = heading(in: trimmed) {
                flushParagraph()
                kinds.append(.heading(level: heading.level, text: heading.text))
            } else if trimmed.hasPrefix(">") {
                flushParagraph()
                kinds.append(.quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                flushParagraph()
                kinds.append(.unorderedList(String(trimmed.dropFirst(2))))
            } else if let ordered = orderedListItem(in: trimmed) {
                flushParagraph()
                kinds.append(.orderedList(number: ordered.number, text: ordered.text))
            } else {
                paragraph.append(line)
            }
        }

        if isInCodeBlock, !code.isEmpty {
            kinds.append(.code(code.joined(separator: "\n")))
        }
        flushParagraph()

        return kinds.enumerated().map { index, kind in
            ScheduleMemoMarkdownBlock(id: index, kind: kind)
        }
    }

    static func plainText(from source: String) -> String {
        blocks(in: source)
            .map(\.plainText)
            .filter { !$0.isEmpty }
            .map(stripInlineMarkdown)
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func referencedResources(in source: String) -> Set<ScheduleMemoInlineResourceReference> {
        Set(blocks(in: source).compactMap { block in
            guard case .resource(let reference) = block.kind else { return nil }
            return reference
        })
    }

    static func removingResource(
        _ reference: ScheduleMemoInlineResourceReference,
        from source: String
    ) -> String {
        source.components(separatedBy: .newlines)
            .filter { $0.trimmingCharacters(in: .whitespaces) != reference.marker }
            .joined(separator: "\n")
    }

    static func submissionText(
        from source: String,
        attachmentNames: [UUID: String]
    ) -> String {
        blocks(in: source).map { block in
            switch block.kind {
            case .resource(let reference):
                switch reference.kind {
                case .image:
                    return "![图片](请在邮件中手动添加)"
                case .attachment:
                    let name = attachmentNames[reference.id] ?? "附件"
                    return "[附件：\(name)]"
                }
            case .heading(let level, let text):
                return "\(String(repeating: "#", count: level)) \(text)"
            case .paragraph(let text):
                return text
            case .quote(let text):
                return "> \(text)"
            case .unorderedList(let text):
                return "- \(text)"
            case .orderedList(let number, let text):
                return "\(number). \(text)"
            case .task(let isCompleted, let text):
                return "- [\(isCompleted ? "x" : " ")] \(text)"
            case .code(let text):
                return "```\n\(text)\n```"
            case .divider:
                return "---"
            }
        }.joined(separator: "\n\n")
    }

    private static func resourceReference(in line: String) -> ScheduleMemoInlineResourceReference? {
        let candidates: [(prefix: String, kind: ScheduleMemoInlineResourceReference.Kind)] = [
            ("![图片](leafy-memo://image/", .image),
            ("[附件](leafy-memo://attachment/", .attachment)
        ]
        for candidate in candidates where line.hasPrefix(candidate.prefix) && line.hasSuffix(")") {
            let rawID = line.dropFirst(candidate.prefix.count).dropLast()
            guard let id = UUID(uuidString: String(rawID)) else { continue }
            return .init(kind: candidate.kind, id: id)
        }
        return nil
    }

    private static func heading(in line: String) -> (level: Int, text: String)? {
        let count = line.prefix(while: { $0 == "#" }).count
        guard (1...3).contains(count), line.dropFirst(count).first == " " else { return nil }
        return (count, String(line.dropFirst(count + 1)))
    }

    private static func orderedListItem(in line: String) -> (number: Int, text: String)? {
        guard let dot = line.firstIndex(of: "."),
              let number = Int(line[..<dot]),
              line.index(after: dot) < line.endIndex,
              line[line.index(after: dot)] == " " else { return nil }
        return (number, String(line[line.index(dot, offsetBy: 2)...]))
    }

    private static func taskItem(in line: String) -> (isCompleted: Bool, text: String)? {
        let prefixes = ["- [ ] ": false, "* [ ] ": false, "- [x] ": true, "- [X] ": true,
                        "* [x] ": true, "* [X] ": true]
        for (prefix, isCompleted) in prefixes where line.hasPrefix(prefix) {
            return (isCompleted, String(line.dropFirst(prefix.count)))
        }
        return nil
    }

    private static func isDivider(_ line: String) -> Bool {
        ["---", "***", "___"].contains(line)
    }

    private static func stripInlineMarkdown(_ source: String) -> String {
        source
            .replacingOccurrences(of: #"!\[([^\]]*)\]\([^\)]*\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]*\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"(\*\*|__|~~|`|\*|_)"#, with: "", options: .regularExpression)
    }
}

nonisolated enum ScheduleMemoEditorCommand: Equatable, Sendable {
    case heading(Int)
    case bold
    case italic
    case strikethrough
    case quote
    case unorderedList
    case orderedList
    case task
    case inlineCode
    case codeBlock
    case link
    case divider
    case insert(String)
}

nonisolated enum ScheduleMemoEditorMutation {
    struct Result: Equatable, Sendable {
        let text: String
        let selection: NSRange
    }

    static func applying(
        _ command: ScheduleMemoEditorCommand,
        to text: String,
        selection: NSRange
    ) -> Result {
        let nsText = text as NSString
        let safeSelection = clamped(selection, length: nsText.length)

        switch command {
        case .heading(let level):
            return prefixLines(String(repeating: "#", count: min(max(level, 1), 3)) + " ", text: text, selection: safeSelection)
        case .bold:
            return wrap("**", "**", text: text, selection: safeSelection, placeholder: "粗体")
        case .italic:
            return wrap("*", "*", text: text, selection: safeSelection, placeholder: "斜体")
        case .strikethrough:
            return wrap("~~", "~~", text: text, selection: safeSelection, placeholder: "删除线")
        case .quote:
            return prefixLines("> ", text: text, selection: safeSelection)
        case .unorderedList:
            return prefixLines("- ", text: text, selection: safeSelection)
        case .orderedList:
            return prefixLines("1. ", text: text, selection: safeSelection)
        case .task:
            return prefixLines("- [ ] ", text: text, selection: safeSelection)
        case .inlineCode:
            return wrap("`", "`", text: text, selection: safeSelection, placeholder: "代码")
        case .codeBlock:
            return wrap("```\n", "\n```", text: text, selection: safeSelection, placeholder: "代码")
        case .link:
            let selected = nsText.substring(with: safeSelection)
            let label = selected.isEmpty ? "链接文字" : selected
            let replacement = "[\(label)](https://)"
            let updated = nsText.replacingCharacters(in: safeSelection, with: replacement)
            let urlLocation = safeSelection.location + (label as NSString).length + 3
            return Result(text: updated, selection: NSRange(location: urlLocation, length: 0))
        case .divider:
            return insertBlock("---", text: text, selection: safeSelection)
        case .insert(let value):
            return insertBlock(value, text: text, selection: safeSelection)
        }
    }

    private static func wrap(
        _ prefix: String,
        _ suffix: String,
        text: String,
        selection: NSRange,
        placeholder: String
    ) -> Result {
        let nsText = text as NSString
        let selected = nsText.substring(with: selection)
        let content = selected.isEmpty ? placeholder : selected
        let replacement = prefix + content + suffix
        let updated = nsText.replacingCharacters(in: selection, with: replacement)
        let contentRange = NSRange(
            location: selection.location + (prefix as NSString).length,
            length: (content as NSString).length
        )
        return Result(text: updated, selection: contentRange)
    }

    private static func prefixLines(_ prefix: String, text: String, selection: NSRange) -> Result {
        let nsText = text as NSString
        let lineRange = nsText.lineRange(for: selection)
        let selectedLines = nsText.substring(with: lineRange)
        let hasTrailingNewline = selectedLines.hasSuffix("\n")
        let lines = selectedLines.split(separator: "\n", omittingEmptySubsequences: false)
        let prefixed = lines.enumerated().map { index, line in
            if hasTrailingNewline && index == lines.count - 1 && line.isEmpty { return "" }
            return prefix + line
        }.joined(separator: "\n")
        let updated = nsText.replacingCharacters(in: lineRange, with: prefixed)
        return Result(
            text: updated,
            selection: NSRange(location: lineRange.location, length: (prefixed as NSString).length)
        )
    }

    private static func insertBlock(_ block: String, text: String, selection: NSRange) -> Result {
        let nsText = text as NSString
        let needsLeadingBreak = selection.location > 0 && nsText.substring(with: NSRange(location: selection.location - 1, length: 1)) != "\n"
        let end = selection.location + selection.length
        let needsTrailingBreak = end < nsText.length && nsText.substring(with: NSRange(location: end, length: 1)) != "\n"
        let replacement = (needsLeadingBreak ? "\n" : "") + block + (needsTrailingBreak ? "\n" : "")
        let updated = nsText.replacingCharacters(in: selection, with: replacement)
        return Result(
            text: updated,
            selection: NSRange(location: selection.location + (replacement as NSString).length, length: 0)
        )
    }

    private static func clamped(_ range: NSRange, length: Int) -> NSRange {
        let location = min(max(range.location, 0), length)
        return NSRange(location: location, length: min(max(range.length, 0), length - location))
    }
}

nonisolated struct ScheduleMemoSubmissionDraft: Equatable, Sendable {
    static let recipient = "2210286979@qq.com"

    let subject: String
    let body: String

    var mailtoURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Self.recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }

    static func make(
        title: String?,
        source: String,
        tags: [String],
        createdAt: Date,
        updatedAt: Date,
        attachmentNames: [UUID: String]
    ) -> ScheduleMemoSubmissionDraft {
        let storedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let summary = storedTitle.isEmpty
            ? String(ScheduleMemoMarkdownParser.plainText(from: source).prefix(40))
            : storedTitle
        let resolvedSummary = summary.isEmpty ? "随记投稿" : summary
        var sections = [
            "创建时间：\(createdAt.formatted(date: .long, time: .shortened))",
            "更新时间：\(updatedAt.formatted(date: .long, time: .shortened))"
        ]
        if !tags.isEmpty {
            sections.append("标签：\(tags.map { "#\($0)" }.joined(separator: " "))")
        }
        if !attachmentNames.isEmpty {
            sections.append("本地附件：\(attachmentNames.values.sorted().joined(separator: "、"))")
        }
        sections.append("")
        sections.append(ScheduleMemoMarkdownParser.submissionText(from: source, attachmentNames: attachmentNames))
        sections.append("")
        sections.append("提示：随记中的本地图片和附件未自动附加，请在邮箱 App 中按需补充。")
        return ScheduleMemoSubmissionDraft(
            subject: "【MyLeafy 投稿】\(resolvedSummary)",
            body: sections.joined(separator: "\n")
        )
    }
}
