import PDFKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct HonorRecordsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Query(sort: \HonorRecord.awardedAt, order: .reverse) private var records: [HonorRecord]

    @State private var isImporterPresented = false
    @State private var editorRecord: HonorRecord?
    @State private var previewRecord: HonorRecord?
    @State private var shareItem: HonorRecordShareItem?
    @State private var recordPendingDeletion: HonorRecord?
    @State private var alertMessage: String?

    var body: some View {
        AcademicDetailScrollContainer {
            AcademicDetailCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label("本地安全保存", systemImage: "lock.shield.fill")
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)

                    Text("为确保数据安全，PDF 和图片只在本地保存文件路径和记录信息，不会传输到外界。")
                        .leafyBody()
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .padding(.vertical, 4)
            }

            if records.isEmpty {
                AcademicDetailCard {
                    ContentUnavailableView {
                        Label("还没有荣誉记录", systemImage: "rosette")
                    } description: {
                        Text("导入奖状、证书 PDF 或图片后，可补充标题、备注和日期。")
                    }
                    .tint(AppTheme.accent)
                    .padding(.vertical, AppSpacing.page)
                }
            } else {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    AcademicDetailSectionHeader(title: "荣誉记录")
                    AcademicDetailCard {
                        VStack(spacing: 0) {
                            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                                if index > 0 {
                                    AcademicDetailDivider()
                                }
                                HonorRecordRow(record: record) {
                                    previewRecord = record
                                } editAction: {
                                    editorRecord = record
                                } shareAction: {
                                    shareRecord(record)
                                } deleteAction: {
                                    recordPendingDeletion = record
                                }
                            }
                        }
                    }
                    AcademicDetailFooterText(text: "删除会同时移除本地文件。")
                }
            }
        }
        .navigationTitle("荣誉记录")
        .leafyInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .leafyTrailing) {
                Button {
                    isImporterPresented = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加荣誉记录")
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: true,
            onCompletion: handleImport
        )
        .sheet(item: $editorRecord) { record in
            HonorRecordEditorSheet(record: record)
        }
        .sheet(item: $previewRecord) { record in
            HonorRecordPreviewSheet(record: record)
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: [item.url])
        }
        .alert("删除这条荣誉记录？", isPresented: Binding(
            get: { recordPendingDeletion != nil },
            set: { if !$0 { recordPendingDeletion = nil } }
        )) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let record = recordPendingDeletion {
                    deleteRecord(record)
                }
                recordPendingDeletion = nil
            }
        } message: {
            Text("删除后会同时移除本地文件，无法恢复。")
        }
        .alert("荣誉记录操作失败", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            for url in urls {
                let stored = try HonorRecordFileStore.importFile(from: url)
                let title = url.deletingPathExtension().lastPathComponent
                let record = HonorRecord(
                    title: title.isEmpty ? L10n.text("新的荣誉记录", language: leafyLanguage) : title,
                    originalFilename: url.lastPathComponent,
                    localFilename: stored.localFilename,
                    contentTypeIdentifier: stored.contentTypeIdentifier
                )
                modelContext.insert(record)
                editorRecord = record
            }
            try modelContext.save()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func shareRecord(_ record: HonorRecord) {
        guard let url = HonorRecordFileStore.fileURL(for: record) else {
            alertMessage = L10n.text("无法找到本地荣誉文件。", language: leafyLanguage)
            return
        }
        shareItem = HonorRecordShareItem(url: url)
    }

    private func deleteRecord(_ record: HonorRecord) {
        try? HonorRecordFileStore.deleteFile(named: record.localFilename)
        modelContext.delete(record)
        try? modelContext.save()
    }
}

private struct HonorRecordRow: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let record: HonorRecord
    let previewAction: () -> Void
    let editAction: () -> Void
    let shareAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: previewAction) {
                HStack(alignment: .center, spacing: 10) {
                    HonorRecordThumbnail(record: record)
                        .frame(width: 40, height: 46)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.title)
                            .leafyHeadline()
                            .foregroundStyle(AppTheme.primaryText)
                            .lineLimit(1)

                        Text(record.awardedAt, format: .dateTime.year().month().day())
                            .microCaption()
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(1)

                        if !record.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(record.note)
                                .microCaption()
                                .foregroundStyle(AppTheme.tertiaryText)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button(action: editAction) {
                    Label("编辑", systemImage: "pencil")
                }
                Button(action: shareAction) {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive, action: deleteAction) {
                    Label("删除", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(width: 30, height: 30)
                    .background(AppTheme.softFill, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text("更多荣誉记录操作", language: leafyLanguage))
        }
        .padding(.vertical, 6)
    }
}

private struct HonorRecordThumbnail: View {
    let record: HonorRecord

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                .fill(AppTheme.softFill)

            if record.isImage,
               let image = HonorRecordFileStore.image(for: record) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
            } else {
                Image(systemName: record.isPDF ? "doc.richtext.fill" : "photo.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(record.isPDF ? AppTheme.warning : AppTheme.accentEmphasis)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                .stroke(AppTheme.separator, lineWidth: 1)
        )
        .clipped()
    }
}

private struct HonorRecordEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyLanguage) private var leafyLanguage

    @Bindable var record: HonorRecord

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("标题", text: $record.title)
                    DatePicker("日期", selection: $record.awardedAt, displayedComponents: .date)
                    TextField("备注", text: $record.note, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    LabeledContent("文件", value: record.originalFilename)
                    LabeledContent("类型", value: record.isPDF ? "PDF" : L10n.text("图片", language: leafyLanguage))
                } footer: {
                    Text("文件本体保存在本机私有目录，仅当前 App 可访问。")
                }
            }
            .navigationTitle("编辑荣誉")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        record.updatedAt = Date()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct HonorRecordPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyLanguage) private var leafyLanguage

    let record: HonorRecord

    @State private var shareItem: HonorRecordShareItem?
    @State private var alertMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if record.isPDF,
                   let url = HonorRecordFileStore.fileURL(for: record) {
                    PDFPreview(url: url)
                        .ignoresSafeArea(edges: .bottom)
                } else if let image = HonorRecordFileStore.image(for: record) {
                    HonorRecordImagePreview(image: image)
                } else {
                    ContentUnavailableView("无法预览文件", systemImage: "exclamationmark.triangle")
                }
            }
            .navigationTitle(record.title)
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .leafyTrailing) {
                    Button("分享", action: share)
                        .fontWeight(.semibold)
                }
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(activityItems: [item.url])
            }
            .alert("荣誉记录操作失败", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private func share() {
        guard let url = HonorRecordFileStore.fileURL(for: record) else {
            alertMessage = L10n.text("无法找到本地荣誉文件。", language: leafyLanguage)
            return
        }
        shareItem = HonorRecordShareItem(url: url)
    }
}

private struct HonorRecordShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct HonorRecordImagePreview: View {
    let image: UIImage

    var body: some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        maxWidth: max(proxy.size.width - AppSpacing.page * 2, 0),
                        maxHeight: max(proxy.size.height - AppSpacing.page * 2, 0)
                    )
                    .frame(
                        minWidth: proxy.size.width,
                        minHeight: proxy.size.height,
                        alignment: .center
                    )
            }
            .scrollIndicators(.hidden)
        }
        .background(LeafyPageBackground())
    }
}

#if canImport(UIKit)
private struct PDFPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .clear
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}
#else
private struct PDFPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .clear
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}
#endif

private enum HonorRecordFileStore {
    struct StoredFile {
        let localFilename: String
        let contentTypeIdentifier: String
    }

    static func importFile(from sourceURL: URL) throws -> StoredFile {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let extensionText = sourceURL.pathExtension
        let localFilename = extensionText.isEmpty
            ? UUID().uuidString
            : "\(UUID().uuidString).\(extensionText)"
        let destinationURL = directoryURL.appendingPathComponent(localFilename)

        if fileManager.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        let contentType = UTType(filenameExtension: extensionText)
            ?? sourceURL.resourceContentType
            ?? .data
        return StoredFile(
            localFilename: localFilename,
            contentTypeIdentifier: contentType.identifier
        )
    }

    static func fileURL(for record: HonorRecord) -> URL? {
        let url = directoryURL.appendingPathComponent(record.localFilename)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    static func image(for record: HonorRecord) -> UIImage? {
        guard let url = fileURL(for: record) else { return nil }
        return UIImage(contentsOfFile: url.path(percentEncoded: false))
    }

    static func deleteFile(named filename: String) throws {
        let url = directoryURL.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("HonorRecords", isDirectory: true)
    }
}

private extension URL {
    var resourceContentType: UTType? {
        (try? resourceValues(forKeys: [.contentTypeKey]))?.contentType
    }
}

private extension HonorRecord {
    var contentType: UTType? {
        UTType(contentTypeIdentifier)
    }

    var isPDF: Bool {
        contentType?.conforms(to: .pdf) == true
    }

    var isImage: Bool {
        contentType?.conforms(to: .image) == true
    }
}

#Preview {
    NavigationStack {
        HonorRecordsView()
    }
}
