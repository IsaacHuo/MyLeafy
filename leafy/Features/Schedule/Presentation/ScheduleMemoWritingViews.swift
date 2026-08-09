import QuickLook
import SwiftUI
import UIKit

struct ScheduleMemoMarkdownView: View {
    let source: String

    private var blocks: [ScheduleMemoMarkdownBlock] {
        ScheduleMemoMarkdownParser.blocks(in: source)
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: ScheduleMemoMarkdownBlock) -> some View {
        switch block.kind {
        case .heading(let level):
            Text(inlineMarkdown(block.text))
                .font(headingFont(level))
                .foregroundStyle(AppTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .paragraph:
            Text(inlineMarkdown(block.text))
                .leafyBody()
                .foregroundStyle(AppTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .quote:
            HStack(alignment: .top, spacing: 10) {
                Capsule()
                    .fill(AppTheme.accent)
                    .frame(width: 3)
                Text(inlineMarkdown(block.text))
                    .leafyBody()
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .padding(.vertical, 2)
        case .unorderedList:
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("•")
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.accent)
                Text(inlineMarkdown(block.text))
                    .leafyBody()
                    .foregroundStyle(AppTheme.primaryText)
            }
        case .orderedList(let number):
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("\(number).")
                    .font(.body.monospacedDigit().weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                Text(inlineMarkdown(block.text))
                    .leafyBody()
                    .foregroundStyle(AppTheme.primaryText)
            }
        case .code:
            ScrollView(.horizontal, showsIndicators: false) {
                Text(block.text)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(AppTheme.primaryText)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.softFill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title.bold()
        case 2: return .title2.bold()
        default: return .title3.weight(.semibold)
        }
    }

    private func inlineMarkdown(_ source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
    }
}

struct ScheduleMemoWritingEditor: View {
    enum Mode: String, CaseIterable, Identifiable {
        case edit
        case preview

        var id: String { rawValue }
        var title: String { self == .edit ? "编辑" : "预览" }
    }

    @Environment(\.dismiss) private var dismiss
    let navigationTitle: String
    let onSave: (String, String) -> Void
    @State private var title: String
    @State private var source: String
    @State private var mode: Mode = .edit

    init(
        navigationTitle: String = "写文",
        title: String = "",
        source: String = "",
        onSave: @escaping (String, String) -> Void
    ) {
        self.navigationTitle = navigationTitle
        self.onSave = onSave
        _title = State(initialValue: title)
        _source = State(initialValue: source)
    }

    private var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("写文模式", selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, AppSpacing.page)
                .padding(.vertical, AppSpacing.compact)

                if mode == .edit {
                    VStack(spacing: AppSpacing.compact) {
                        TextField("标题", text: $title)
                            .font(.title2.bold())
                            .textInputAutocapitalization(.sentences)
                        Divider()
                        TextEditor(text: $source)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .overlay(alignment: .topLeading) {
                                if source.isEmpty {
                                    Text("使用 Markdown 写下正文…")
                                        .foregroundStyle(AppTheme.tertiaryText)
                                        .allowsHitTesting(false)
                                        .padding(.top, 8)
                                        .padding(.leading, 5)
                                }
                            }
                    }
                    .padding(.horizontal, AppSpacing.page)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: AppSpacing.card) {
                            Text(normalizedTitle.isEmpty ? "未命名文章" : normalizedTitle)
                                .font(.largeTitle.bold())
                                .foregroundStyle(AppTheme.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ScheduleMemoMarkdownView(source: source)
                        }
                        .padding(AppSpacing.page)
                    }
                }
            }
            .background(LeafyPageBackground())
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(normalizedTitle, source)
                        dismiss()
                    }
                    .disabled(normalizedTitle.isEmpty)
                }
            }
        }
    }
}

fileprivate struct ScheduleMemoMarkdownBlock: Identifiable {
    enum Kind {
        case heading(Int)
        case paragraph
        case quote
        case unorderedList
        case orderedList(Int)
        case code
    }

    let id = UUID()
    let kind: Kind
    let text: String
}

enum ScheduleMemoMarkdownParser {
    fileprivate static func blocks(in source: String) -> [ScheduleMemoMarkdownBlock] {
        let lines = source.components(separatedBy: .newlines)
        var result: [ScheduleMemoMarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String] = []
        var isInCodeBlock = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            result.append(.init(kind: .paragraph, text: paragraph.joined(separator: "\n")))
            paragraph.removeAll()
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if isInCodeBlock {
                    result.append(.init(kind: .code, text: code.joined(separator: "\n")))
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

            if let heading = heading(in: trimmed) {
                flushParagraph()
                result.append(.init(kind: .heading(heading.level), text: heading.text))
            } else if trimmed.hasPrefix(">") {
                flushParagraph()
                result.append(.init(kind: .quote, text: String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                flushParagraph()
                result.append(.init(kind: .unorderedList, text: String(trimmed.dropFirst(2))))
            } else if let ordered = orderedListItem(in: trimmed) {
                flushParagraph()
                result.append(.init(kind: .orderedList(ordered.number), text: ordered.text))
            } else {
                paragraph.append(line)
            }
        }

        if isInCodeBlock, !code.isEmpty {
            result.append(.init(kind: .code, text: code.joined(separator: "\n")))
        }
        flushParagraph()
        return result
    }

    static func plainText(from source: String) -> String {
        blocks(in: source).map(\.text).joined(separator: " ")
            .replacingOccurrences(of: #"[*_`]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]+\)"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
}

struct ScheduleMemoCameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void = {}) {
        self.onCapture = onCapture
        self.onCancel = onCancel
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onCapture: (UIImage) -> Void
        private let onCancel: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
            picker.dismiss(animated: true)
        }
    }
}

struct ScheduleMemoDocumentPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
