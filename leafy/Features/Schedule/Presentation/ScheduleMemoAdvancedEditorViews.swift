import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ScheduleMemoMarkdownResourceSet {
    var images: [UUID: UIImage] = [:]
    var imageOrder: [UUID] = []
    var attachmentNames: [UUID: String] = [:]
    var attachmentOrder: [UUID] = []

    init(
        images: [UUID: UIImage] = [:],
        imageOrder: [UUID] = [],
        attachmentNames: [UUID: String] = [:],
        attachmentOrder: [UUID] = []
    ) {
        self.images = images
        self.imageOrder = Self.orderedIDs(imageOrder, available: Set(images.keys))
        self.attachmentNames = attachmentNames
        self.attachmentOrder = Self.orderedIDs(attachmentOrder, available: Set(attachmentNames.keys))
    }

    private static func orderedIDs(_ preferred: [UUID], available: Set<UUID>) -> [UUID] {
        let preferredAvailable = preferred.filter(available.contains)
        let remaining = available.subtracting(preferredAvailable)
            .sorted { $0.uuidString < $1.uuidString }
        return preferredAvailable + remaining
    }
}

struct ScheduleMemoRichMarkdownView: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    enum Style {
        case screen
        case shareCard
    }

    let source: String
    var resources = ScheduleMemoMarkdownResourceSet()
    var showsUnreferencedResources = true
    var style: Style = .screen
    var onOpenAttachment: ((UUID) -> Void)?

    private var blocks: [ScheduleMemoMarkdownBlock] {
        ScheduleMemoMarkdownParser.blocks(in: source)
    }

    private var references: Set<ScheduleMemoInlineResourceReference> {
        ScheduleMemoMarkdownParser.referencedResources(in: source)
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: style == .shareCard ? 12 : 10) {
            ForEach(blocks) { block in
                blockView(block)
            }

            if showsUnreferencedResources {
                ForEach(unreferencedImageIDs, id: \.self) { id in
                    imageBlock(id)
                }
                ForEach(unreferencedAttachmentIDs, id: \.self) { id in
                    attachmentBlock(id)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(ScheduleMemoTextSelectionModifier(isEnabled: style == .screen))
    }

    @ViewBuilder
    private func blockView(_ block: ScheduleMemoMarkdownBlock) -> some View {
        switch block.kind {
        case .heading(let level, let text):
            Text(inlineMarkdown(text))
                .font(headingFont(level))
                .foregroundStyle(AppTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .paragraph(let text):
            Text(inlineMarkdown(text))
                .font(.body)
                .lineSpacing(style == .shareCard ? 3 : 2)
                .foregroundStyle(AppTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                Capsule()
                    .fill(AppTheme.accent)
                    .frame(width: 3)
                Text(inlineMarkdown(text))
                    .font(.body)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .padding(.vertical, 2)
        case .unorderedList(let text):
            listRow(marker: "•", text: text)
        case .orderedList(let number, let text):
            listRow(marker: "\(number).", text: text)
        case .task(let isCompleted, let text):
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Image(systemName: isCompleted ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isCompleted ? AppTheme.accent : AppTheme.secondaryText)
                Text(inlineMarkdown(text))
                    .font(.body)
                    .foregroundStyle(AppTheme.primaryText)
                    .strikethrough(isCompleted)
            }
        case .code(let text):
            Group {
                if style == .shareCard {
                    codeText(text)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        codeText(text)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.softFill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        case .divider:
            Divider()
        case .resource(let reference):
            switch reference.kind {
            case .image:
                imageBlock(reference.id)
            case .attachment:
                attachmentBlock(reference.id)
            }
        }
    }

    private func listRow(marker: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(marker)
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(AppTheme.accent)
            Text(inlineMarkdown(text))
                .font(.body)
                .foregroundStyle(AppTheme.primaryText)
        }
    }

    private func codeText(_ text: String) -> some View {
        Text(text)
            .font(.system(.callout, design: .monospaced))
            .foregroundStyle(AppTheme.primaryText)
            .padding(12)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func imageBlock(_ id: UUID) -> some View {
        if let image = resources.images[id] {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                .accessibilityLabel(L10n.text("随记图片", language: leafyLanguage))
        } else {
            missingResource(
                L10n.text("图片已无法读取", language: leafyLanguage),
                systemImage: "photo.badge.exclamationmark"
            )
        }
    }

    @ViewBuilder
    private func attachmentBlock(_ id: UUID) -> some View {
        if let name = resources.attachmentNames[id] {
            Button {
                onOpenAttachment?(id)
            } label: {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "paperclip")
                        .foregroundStyle(AppTheme.accent)
                    Text(name)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(AppTheme.primaryText)
                    Spacer(minLength: 8)
                    if onOpenAttachment != nil {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.tertiaryText)
                    }
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(AppTheme.softFill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(onOpenAttachment == nil)
            .accessibilityHint(
                onOpenAttachment == nil
                    ? ""
                    : L10n.text("预览附件", language: leafyLanguage)
            )
        } else {
            missingResource(
                L10n.text("附件已无法读取", language: leafyLanguage),
                systemImage: "doc.badge.ellipsis"
            )
        }
    }

    private func missingResource(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(AppTheme.secondaryText)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.softFill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }

    private var unreferencedImageIDs: [UUID] {
        resources.imageOrder
            .filter { !references.contains(.init(kind: .image, id: $0)) }
    }

    private var unreferencedAttachmentIDs: [UUID] {
        resources.attachmentOrder
            .filter { !references.contains(.init(kind: .attachment, id: $0)) }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return style == .shareCard ? .title2.bold() : .title.bold()
        case 2: return style == .shareCard ? .title3.bold() : .title2.bold()
        default: return .headline
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

private struct ScheduleMemoTextSelectionModifier: ViewModifier {
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.textSelection(.enabled)
        } else {
            content.textSelection(.disabled)
        }
    }
}

struct ScheduleMemoEditorDraftImage: Identifiable {
    let id: UUID
    let data: Data
    let image: UIImage
}

struct ScheduleMemoEditorDraftAttachment: Identifiable {
    let id: UUID
    let originalFilename: String
    let contentTypeIdentifier: String
    let data: Data
}

private struct ScheduleMemoSourceTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    let accessibilityLabel: String

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.alwaysBounceVertical = true
        view.keyboardDismissMode = .interactive
        view.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 24, right: 10)
        view.accessibilityLabel = accessibilityLabel
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        view.accessibilityLabel = accessibilityLabel
        if view.text != text {
            view.text = text
        }
        let safe = NSRange(
            location: min(selection.location, view.text.utf16.count),
            length: min(selection.length, max(view.text.utf16.count - min(selection.location, view.text.utf16.count), 0))
        )
        if view.selectedRange != safe {
            view.selectedRange = safe
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ScheduleMemoSourceTextView

        init(parent: ScheduleMemoSourceTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.selection = textView.selectedRange
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard parent.selection != textView.selectedRange else { return }
            parent.selection = textView.selectedRange
        }
    }
}

struct ScheduleMemoAdvancedEditorView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case edit
        case preview

        var id: String { rawValue }
        var title: String { self == .edit ? "编辑" : "预览" }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.modelContext) private var modelContext
    @Query private var allImages: [ScheduleMemoImage]
    @Query private var allAttachments: [ScheduleMemoAttachment]

    let memo: ScheduleMemo

    @State private var title: String
    @State private var source: String
    @State private var selection: NSRange
    @State private var mode: Mode = .edit
    @State private var draftImages: [ScheduleMemoEditorDraftImage] = []
    @State private var draftAttachments: [ScheduleMemoEditorDraftAttachment] = []
    @State private var deletedImageIDs: Set<UUID> = []
    @State private var deletedAttachmentIDs: Set<UUID> = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showsPhotoPicker = false
    @State private var showsCamera = false
    @State private var showsFileImporter = false
    @State private var showsResources = false
    @State private var confirmsDiscard = false
    @State private var errorMessage: String?
    @State private var dismissAfterError = false
    @State private var isSaving = false

    private let initialTitle: String
    private let initialSource: String

    init(memo: ScheduleMemo) {
        self.memo = memo
        let initialTitle = memo.title ?? ""
        self.initialTitle = initialTitle
        self.initialSource = memo.body
        _title = State(initialValue: initialTitle)
        _source = State(initialValue: memo.body)
        _selection = State(initialValue: NSRange(location: (memo.body as NSString).length, length: 0))
    }

    private var existingImages: [ScheduleMemoImage] {
        allImages.filter { $0.memoID == memo.id && !deletedImageIDs.contains($0.id) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var existingAttachments: [ScheduleMemoAttachment] {
        allAttachments.filter { $0.memoID == memo.id && !deletedAttachmentIDs.contains($0.id) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var hasChanges: Bool {
        title != initialTitle || source != initialSource || !draftImages.isEmpty ||
            !draftAttachments.isEmpty || !deletedImageIDs.isEmpty || !deletedAttachmentIDs.isEmpty
    }

    private var canSave: Bool {
        !isSaving && (memo.kind != .article || !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var resources: ScheduleMemoMarkdownResourceSet {
        var imageMap = Dictionary(uniqueKeysWithValues: draftImages.map { ($0.id, $0.image) })
        for image in existingImages {
            if let value = ScheduleMemoImageStore.image(named: image.localFilename) {
                imageMap[image.id] = value
            }
        }
        var names = Dictionary(uniqueKeysWithValues: draftAttachments.map { ($0.id, $0.originalFilename) })
        for attachment in existingAttachments {
            names[attachment.id] = attachment.originalFilename
        }
        return .init(
            images: imageMap,
            imageOrder: existingImages.map(\.id) + draftImages.map(\.id),
            attachmentNames: names,
            attachmentOrder: existingAttachments.map(\.id) + draftAttachments.map(\.id)
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker(L10n.text("编辑模式", language: leafyLanguage), selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(L10n.text(mode.title, language: leafyLanguage)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, AppSpacing.page)
                .padding(.vertical, AppSpacing.compact)

                if mode == .edit {
                    editor
                } else {
                    preview
                }
            }
            .background(LeafyPageBackground())
            .navigationTitle(L10n.text(
                memo.kind == .article ? "编辑写文" : "编辑随记",
                language: leafyLanguage
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("取消", language: leafyLanguage), action: requestDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text(isSaving ? "保存中…" : "保存", language: leafyLanguage)) { save() }
                        .disabled(!canSave)
                }
            }
        }
        .interactiveDismissDisabled(hasChanges)
        .photosPicker(
            isPresented: $showsPhotoPicker,
            selection: $photoItems,
            maxSelectionCount: max(ScheduleMemoImageStore.maximumImageCount - existingImages.count - draftImages.count, 1),
            matching: .images
        )
        .onChange(of: photoItems) { _, items in
            Task { await addPhotos(items) }
        }
        .sheet(isPresented: $showsCamera) {
            ScheduleMemoCameraView { image in
                guard existingImages.count + draftImages.count < ScheduleMemoImageStore.maximumImageCount,
                      let data = image.jpegData(compressionQuality: 0.9) else { return }
                let draft = ScheduleMemoEditorDraftImage(id: UUID(), data: data, image: image)
                draftImages.append(draft)
                insert(.init(kind: .image, id: draft.id))
            }
            .presentationDetents([.fraction(0.62)])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(36)
            .presentationBackground(.black)
        }
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: ScheduleMemoAttachmentStore.allowedContentTypes,
            allowsMultipleSelection: true,
            onCompletion: importAttachments
        )
        .sheet(isPresented: $showsResources) {
            resourceManager
        }
        .confirmationDialog(
            L10n.text("放弃未保存的更改？", language: leafyLanguage),
            isPresented: $confirmsDiscard,
            titleVisibility: .visible
        ) {
            Button(L10n.text("放弃更改", language: leafyLanguage), role: .destructive) { dismiss() }
            Button(L10n.text("继续编辑", language: leafyLanguage), role: .cancel) {}
        }
        .alert(L10n.text("无法保存随记", language: leafyLanguage), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(L10n.text("好", language: leafyLanguage)) {
                errorMessage = nil
                if dismissAfterError {
                    dismissAfterError = false
                    dismiss()
                }
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            if memo.kind == .article {
                TextField(L10n.text("标题", language: leafyLanguage), text: $title)
                    .font(.title2.bold())
                    .padding(.horizontal, AppSpacing.page)
                    .padding(.vertical, 10)
                Divider()
            }

            ZStack(alignment: .topLeading) {
                ScheduleMemoSourceTextView(
                    text: $source,
                    selection: $selection,
                    accessibilityLabel: L10n.text("Markdown 正文", language: leafyLanguage)
                )
                if source.isEmpty {
                    Text(L10n.text("使用 Markdown 写下正文…", language: leafyLanguage))
                        .foregroundStyle(AppTheme.tertiaryText)
                        .padding(.top, 19)
                        .padding(.leading, 26)
                        .allowsHitTesting(false)
                }
            }

            Divider()
            formattingToolbar
        }
    }

    private var preview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.card) {
                if memo.kind == .article {
                    Text(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? L10n.text("未命名文章", language: leafyLanguage)
                            : title
                    )
                        .font(.largeTitle.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ScheduleMemoRichMarkdownView(source: source, resources: resources)
            }
            .padding(AppSpacing.page)
        }
    }

    private var formattingToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                Menu {
                    Button(L10n.text("一级标题", language: leafyLanguage)) { apply(.heading(1)) }
                    Button(L10n.text("二级标题", language: leafyLanguage)) { apply(.heading(2)) }
                    Button(L10n.text("三级标题", language: leafyLanguage)) { apply(.heading(3)) }
                } label: {
                    editorTool("textformat.size", label: L10n.text("标题", language: leafyLanguage))
                }
                tool("bold", label: L10n.text("粗体", language: leafyLanguage), command: .bold)
                tool("italic", label: L10n.text("斜体", language: leafyLanguage), command: .italic)
                tool("strikethrough", label: L10n.text("删除线", language: leafyLanguage), command: .strikethrough)
                tool("text.quote", label: L10n.text("引用", language: leafyLanguage), command: .quote)
                Menu {
                    Button(L10n.text("项目列表", language: leafyLanguage), systemImage: "list.bullet") { apply(.unorderedList) }
                    Button(L10n.text("编号列表", language: leafyLanguage), systemImage: "list.number") { apply(.orderedList) }
                    Button(L10n.text("待办事项", language: leafyLanguage), systemImage: "checklist") { apply(.task) }
                } label: {
                    editorTool("list.bullet", label: L10n.text("列表", language: leafyLanguage))
                }
                Menu {
                    Button(L10n.text("行内代码", language: leafyLanguage), systemImage: "chevron.left.forwardslash.chevron.right") { apply(.inlineCode) }
                    Button(L10n.text("代码块", language: leafyLanguage), systemImage: "curlybraces.square") { apply(.codeBlock) }
                } label: {
                    editorTool("chevron.left.forwardslash.chevron.right", label: L10n.text("代码", language: leafyLanguage))
                }
                tool("link", label: L10n.text("链接", language: leafyLanguage), command: .link)
                tool("minus", label: L10n.text("分隔线", language: leafyLanguage), command: .divider)
                insertMenu
            }
            .padding(.horizontal, 8)
        }
        .frame(minHeight: 52)
        .leafyGlassSurface(
            in: RoundedRectangle(cornerRadius: 20, style: .continuous),
            fallbackFill: Color(uiColor: .secondarySystemBackground)
        )
        .padding(.horizontal, AppSpacing.compact)
        .padding(.vertical, 6)
    }

    private var insertMenu: some View {
        Menu {
            Button(L10n.text("照片图库", language: leafyLanguage), systemImage: "photo.on.rectangle") {
                guard existingImages.count + draftImages.count < ScheduleMemoImageStore.maximumImageCount else {
                    errorMessage = L10n.text(
                        "一条随记最多添加 %d 张图片。",
                        language: leafyLanguage,
                        ScheduleMemoImageStore.maximumImageCount
                    )
                    return
                }
                showsPhotoPicker = true
            }
            Button(L10n.text("拍照", language: leafyLanguage), systemImage: "camera") {
                guard existingImages.count + draftImages.count < ScheduleMemoImageStore.maximumImageCount else {
                    errorMessage = L10n.text(
                        "一条随记最多添加 %d 张图片。",
                        language: leafyLanguage,
                        ScheduleMemoImageStore.maximumImageCount
                    )
                    return
                }
                showsCamera = true
            }
            Button(L10n.text("文件", language: leafyLanguage), systemImage: "doc.badge.plus") {
                guard existingAttachments.count + draftAttachments.count < ScheduleMemoAttachmentStore.maximumAttachmentCount else {
                    errorMessage = L10n.text(
                        "一条随记最多添加 %d 个附件。",
                        language: leafyLanguage,
                        ScheduleMemoAttachmentStore.maximumAttachmentCount
                    )
                    return
                }
                showsFileImporter = true
            }
            if !existingImages.isEmpty || !existingAttachments.isEmpty || !draftImages.isEmpty || !draftAttachments.isEmpty {
                Divider()
                Button(L10n.text("插入已有内容", language: leafyLanguage), systemImage: "square.grid.2x2") { showsResources = true }
            }
        } label: {
            editorTool("plus", label: L10n.text("插入", language: leafyLanguage))
        }
    }

    private func tool(_ systemImage: String, label: String, command: ScheduleMemoEditorCommand) -> some View {
        Button { apply(command) } label: { editorTool(systemImage, label: label) }
            .buttonStyle(.plain)
    }

    private func editorTool(_ systemImage: String, label: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(AppTheme.primaryText)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(label)
    }

    private var resourceManager: some View {
        NavigationStack {
            List {
                if resources.images.isEmpty && resources.attachmentNames.isEmpty {
                    ContentUnavailableView(
                        L10n.text("还没有媒体", language: leafyLanguage),
                        systemImage: "photo.on.rectangle"
                    )
                }
                ForEach(resources.imageOrder, id: \.self) { id in
                    resourceRow(
                        title: L10n.text("图片", language: leafyLanguage),
                        systemImage: "photo",
                        reference: .init(kind: .image, id: id)
                    )
                }
                ForEach(resources.attachmentOrder, id: \.self) { id in
                    resourceRow(
                        title: resources.attachmentNames[id] ?? L10n.text("附件", language: leafyLanguage),
                        systemImage: "paperclip",
                        reference: .init(kind: .attachment, id: id)
                    )
                }
            }
            .navigationTitle(L10n.text("随记内容", language: leafyLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("完成", language: leafyLanguage)) { showsResources = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func resourceRow(
        title: String,
        systemImage: String,
        reference: ScheduleMemoInlineResourceReference
    ) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.compact) {
            Label(title, systemImage: systemImage)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: AppSpacing.compact)
            Menu {
                Button(L10n.text("插入", language: leafyLanguage), systemImage: "arrow.down.to.line") {
                    insert(reference)
                    showsResources = false
                }
                Button(
                    L10n.text("移除", language: leafyLanguage),
                    systemImage: "trash",
                    role: .destructive
                ) {
                    remove(reference)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(L10n.text("附件操作", language: leafyLanguage))
        }
        .padding(.vertical, 3)
    }

    private func apply(_ command: ScheduleMemoEditorCommand) {
        let result = ScheduleMemoEditorMutation.applying(command, to: source, selection: selection)
        source = result.text
        selection = result.selection
    }

    private func insert(_ reference: ScheduleMemoInlineResourceReference) {
        apply(.insert(reference.marker))
    }

    private func remove(_ reference: ScheduleMemoInlineResourceReference) {
        source = ScheduleMemoMarkdownParser.removingResource(reference, from: source)
        switch reference.kind {
        case .image:
            if draftImages.contains(where: { $0.id == reference.id }) {
                draftImages.removeAll { $0.id == reference.id }
            } else {
                deletedImageIDs.insert(reference.id)
            }
        case .attachment:
            if draftAttachments.contains(where: { $0.id == reference.id }) {
                draftAttachments.removeAll { $0.id == reference.id }
            } else {
                deletedAttachmentIDs.insert(reference.id)
            }
        }
    }

    @MainActor
    private func addPhotos(_ items: [PhotosPickerItem]) async {
        photoItems = []
        let remaining = max(ScheduleMemoImageStore.maximumImageCount - existingImages.count - draftImages.count, 0)
        for item in items.prefix(remaining) {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = ImageDataDecoder.decodedImage(from: data) else {
                    throw ScheduleMemoImageStoreError.invalidImage
                }
                let draft = ScheduleMemoEditorDraftImage(id: UUID(), data: data, image: image)
                draftImages.append(draft)
                insert(.init(kind: .image, id: draft.id))
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
    }

    private func importAttachments(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            let remaining = max(ScheduleMemoAttachmentStore.maximumAttachmentCount - existingAttachments.count - draftAttachments.count, 0)
            guard urls.count <= remaining else {
                throw ScheduleMemoAttachmentStoreError.tooManyAttachments(maximum: ScheduleMemoAttachmentStore.maximumAttachmentCount)
            }
            for url in urls {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                let contentType = try url.resourceValues(forKeys: [.contentTypeKey]).contentType?.identifier
                    ?? UTType.data.identifier
                let draft = ScheduleMemoEditorDraftAttachment(
                    id: UUID(),
                    originalFilename: url.lastPathComponent,
                    contentTypeIdentifier: contentType,
                    data: data
                )
                draftAttachments.append(draft)
                insert(.init(kind: .attachment, id: draft.id))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func requestDismiss() {
        if hasChanges {
            confirmsDiscard = true
        } else {
            dismiss()
        }
    }

    @MainActor
    private func save() {
        guard canSave else { return }
        isSaving = true
        var newImageFilenames: [String] = []
        var newAttachmentFiles: [ScheduleMemoAttachmentStore.StoredFile] = []
        var didSave = false

        do {
            let availableImageIDs = Set(existingImages.map(\.id) + draftImages.map(\.id))
            let availableAttachmentIDs = Set(existingAttachments.map(\.id) + draftAttachments.map(\.id))
            for reference in ScheduleMemoMarkdownParser.referencedResources(in: source) {
                let isAvailable = reference.kind == .image
                    ? availableImageIDs.contains(reference.id)
                    : availableAttachmentIDs.contains(reference.id)
                guard isAvailable else {
                    throw ScheduleMemoEditorSaveError.missingResource
                }
            }

            for draft in draftImages {
                let filename = try ScheduleMemoImageStore.importImage(data: draft.data)
                newImageFilenames.append(filename)
                modelContext.insert(ScheduleMemoImage(
                    id: draft.id,
                    memoID: memo.id,
                    sortOrder: existingImages.count + newImageFilenames.count - 1,
                    localFilename: filename
                ))
            }
            for draft in draftAttachments {
                let stored = try ScheduleMemoAttachmentStore.importData(
                    draft.data,
                    originalFilename: draft.originalFilename,
                    contentTypeIdentifier: draft.contentTypeIdentifier
                )
                newAttachmentFiles.append(stored)
                modelContext.insert(ScheduleMemoAttachment(
                    id: draft.id,
                    memoID: memo.id,
                    sortOrder: existingAttachments.count + newAttachmentFiles.count - 1,
                    originalFilename: stored.originalFilename,
                    localFilename: stored.localFilename,
                    contentTypeIdentifier: stored.contentTypeIdentifier
                ))
            }

            let removedImages = allImages.filter { deletedImageIDs.contains($0.id) }
            let removedAttachments = allAttachments.filter { deletedAttachmentIDs.contains($0.id) }
            removedImages.forEach(modelContext.delete)
            removedAttachments.forEach(modelContext.delete)

            memo.title = memo.kind == .article
                ? title.trimmingCharacters(in: .whitespacesAndNewlines)
                : memo.title
            memo.updateBody(source)
            try modelContext.save()
            didSave = true

            try ScheduleMemoImageStore.deleteFiles(named: removedImages.map(\.localFilename))
            try ScheduleMemoAttachmentStore.deleteFiles(named: removedAttachments.map(\.localFilename))
            dismiss()
        } catch {
            if !didSave {
                try? ScheduleMemoImageStore.deleteFiles(named: newImageFilenames)
                try? ScheduleMemoAttachmentStore.deleteFiles(named: newAttachmentFiles.map(\.localFilename))
                modelContext.rollback()
            } else {
                dismissAfterError = true
            }
            isSaving = false
            errorMessage = didSave
                ? L10n.text(
                    "随记已保存，但未能清理已移除的本地文件：%@",
                    language: leafyLanguage,
                    error.localizedDescription
                )
                : error.localizedDescription
        }
    }
}

private enum ScheduleMemoEditorSaveError: LocalizedError {
    case missingResource

    var errorDescription: String? {
        L10n.text("正文引用了已不存在的图片或附件，请移除该标记后重试。")
    }
}
