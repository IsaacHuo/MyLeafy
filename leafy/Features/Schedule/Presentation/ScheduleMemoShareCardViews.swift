import OSLog
import SwiftUI
import UIKit

nonisolated enum ScheduleMemoShareCardError: LocalizedError, Sendable {
    case invalidImage(Int)
    case missingInlineResource
    case contentTooLong
    case renderFailed
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage(let index):
            return "第 \(index) 张随记图片无法读取。"
        case .missingInlineResource:
            return "正文引用的图片或附件已不存在，请先编辑随记后再生成卡片。"
        case .contentTooLong:
            return "图文卡片内容过长，无法生成清晰的单张长图。请精简正文或图片后重试。"
        case .renderFailed:
            return "图文卡片生成失败，请稍后重试。"
        case .writeFailed(let message):
            return "图文卡片写入失败：\(message)"
        }
    }
}

struct ScheduleMemoShareCardSnapshot {
    let authorName: String
    let avatarData: Data?
    let avatarFallbackText: String
    let dateText: String
    let category: String
    let title: String
    let source: String
    let imageData: [UUID: Data]
    let imageOrder: [UUID]
    let attachmentNames: [UUID: String]
    let attachmentOrder: [UUID]
    let theme: CommunityPostCardTheme

    @MainActor
    static func make(
        memo: ScheduleMemo,
        images: [ScheduleMemoImage],
        attachments: [ScheduleMemoAttachment]
    ) throws -> ScheduleMemoShareCardSnapshot {
        var imageData: [UUID: Data] = [:]
        for (index, image) in images.enumerated() {
            guard let data = ScheduleMemoImageStore.data(named: image.localFilename),
                  UIImage(data: data) != nil else {
                throw ScheduleMemoShareCardError.invalidImage(index + 1)
            }
            imageData[image.id] = data
        }
        let attachmentNames = Dictionary(uniqueKeysWithValues: attachments.map { ($0.id, $0.originalFilename) })
        for reference in ScheduleMemoMarkdownParser.referencedResources(in: memo.body) {
            let exists = reference.kind == .image
                ? imageData[reference.id] != nil
                : attachmentNames[reference.id] != nil
            guard exists else {
                throw ScheduleMemoShareCardError.missingInlineResource
            }
        }
        let profile = CommunitySessionManager.shared.profile
        let authorName = profile?.resolvedDisplayName ?? AppBrand.displayName
        let fallback = profile?.shortName ?? String(authorName.prefix(1))
        let plainText = ScheduleMemoMarkdownParser.plainText(from: memo.body)
        let resolvedTitle: String
        if memo.kind == .article {
            resolvedTitle = memo.displayTitle
        } else {
            resolvedTitle = String(plainText.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ScheduleMemoShareCardSnapshot(
            authorName: authorName,
            avatarData: CommunityAvatarCache.shared.data(for: profile),
            avatarFallbackText: fallback.isEmpty ? "我" : fallback,
            dateText: DateFormatters.headerWithTime.string(from: memo.createdAt),
            category: memo.kind == .article ? "写文" : "随记",
            title: resolvedTitle.isEmpty ? "图片随记" : resolvedTitle,
            source: memo.body,
            imageData: imageData,
            imageOrder: images.map(\.id),
            attachmentNames: attachmentNames,
            attachmentOrder: attachments.map(\.id),
            theme: .current
        )
    }
}

struct ScheduleMemoShareCardPreviewSource: Identifiable {
    let id = UUID()
    let snapshot: ScheduleMemoShareCardSnapshot
}

@MainActor
enum ScheduleMemoShareCardGenerator {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "MyLeafy",
        category: "ScheduleMemoShareCards"
    )
    private static let canvasWidth: CGFloat = 360
    private static let renderScale: CGFloat = 3
    private static let maxPixelHeight = 16_384
    private static let temporaryRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScheduleMemoShareCards", isDirectory: true)

    static func render(_ snapshot: ScheduleMemoShareCardSnapshot) throws -> URL {
        let images = try snapshot.imageData.mapValues { data -> UIImage in
            guard let image = UIImage(data: data) else {
                throw ScheduleMemoShareCardError.renderFailed
            }
            return image
        }
        guard estimatedHeight(snapshot: snapshot, images: images) * renderScale <= CGFloat(maxPixelHeight) else {
            throw ScheduleMemoShareCardError.contentTooLong
        }

        let view = ScheduleMemoShareCardContentView(snapshot: snapshot, images: images)
            .frame(width: canvasWidth)
            .fixedSize(horizontal: false, vertical: true)
        let renderer = ImageRenderer(content: view)
        renderer.scale = renderScale
        guard let image = renderer.uiImage,
              let cgImage = image.cgImage,
              cgImage.height <= maxPixelHeight,
              let data = image.jpegData(compressionQuality: 0.92) else {
            throw ScheduleMemoShareCardError.renderFailed
        }

        let directory = temporaryRoot
            .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        let url = directory.appendingPathComponent("MyLeafy-memo-card.jpg")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw ScheduleMemoShareCardError.writeFailed(error.localizedDescription)
        }
    }

    static func deleteRenderedFile(_ url: URL?) {
        guard let directory = url?.deletingLastPathComponent() else { return }
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            logger.error("Delete memo share card failed error=\(error.localizedDescription, privacy: .private)")
        }
    }

    private static func estimatedHeight(
        snapshot: ScheduleMemoShareCardSnapshot,
        images: [UUID: UIImage]
    ) -> CGFloat {
        let textLines = max(snapshot.source.count / 18, 1)
        let textHeight = CGFloat(textLines) * 24
        let imageHeight = images.values.reduce(CGFloat.zero) { total, image in
            guard image.size.width > 0 else { return total }
            return total + min(320, 284 * image.size.height / image.size.width) + 12
        }
        let attachmentsHeight = CGFloat(snapshot.attachmentNames.count) * 56
        return 190 + textHeight + imageHeight + attachmentsHeight
    }
}

private struct ScheduleMemoShareCardContentView: View {
    let snapshot: ScheduleMemoShareCardSnapshot
    let images: [UUID: UIImage]

    private var accent: Color {
        AppThemeColorPreference.color(fromHex: snapshot.theme.accentHex)
    }

    private var background: Color {
        AppThemeColorPreference.color(fromHex: snapshot.theme.backgroundHex)
    }

    private var resources: ScheduleMemoMarkdownResourceSet {
        .init(
            images: images,
            imageOrder: snapshot.imageOrder,
            attachmentNames: snapshot.attachmentNames,
            attachmentOrder: snapshot.attachmentOrder
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            identityHeader
            Text(snapshot.title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            ScheduleMemoRichMarkdownView(
                source: snapshot.source,
                resources: resources,
                style: .shareCard
            )

            Text(AppBrand.displayName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent)
        }
        .frame(maxWidth: .infinity, minHeight: 164, alignment: .topLeading)
        .padding(20)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 18, y: 9)
        .padding(18)
        .frame(width: 360)
        .background(background)
        .environment(\.colorScheme, .light)
    }

    private var identityHeader: some View {
        HStack(spacing: 10) {
            Group {
                if let avatarData = snapshot.avatarData,
                   let avatar = UIImage(data: avatarData) {
                    Image(uiImage: avatar)
                        .resizable()
                        .scaledToFill()
                } else {
                    Text(String(snapshot.avatarFallbackText.prefix(1)))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(background)
                }
            }
            .frame(width: 42, height: 42)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.authorName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                Text("\(snapshot.dateText) · \(snapshot.category)")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }
}

struct ScheduleMemoShareCardPreviewSheet: View {
    let source: ScheduleMemoShareCardPreviewSource

    @Environment(\.dismiss) private var dismiss
    @State private var cardURL: URL?
    @State private var isGenerating = false
    @State private var isSharing = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isGenerating {
                    ProgressView("正在生成图文卡片…")
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("生成失败", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("重试") { generate() }
                            .buttonStyle(.borderedProminent)
                    }
                } else if let cardURL,
                          let image = UIImage(contentsOfFile: cardURL.path) {
                    GeometryReader { geometry in
                        ScrollView {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: max(geometry.size.width - AppSpacing.page * 2, 1))
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
                                .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
                                .padding(AppSpacing.page)
                        }
                    }
                } else {
                    ContentUnavailableView("没有可预览的长图", systemImage: "photo.on.rectangle")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LeafyPageBackground())
            .navigationTitle("图文卡片")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItemGroup(placement: .leafyTrailing) {
                    Button {
                        saveCard()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .disabled(cardURL == nil || isGenerating)
                    .accessibilityLabel("保存长图")

                    Button {
                        isSharing = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(cardURL == nil || isGenerating)
                    .accessibilityLabel("分享长图")
                }
            }
            .task { generate() }
            .onDisappear { ScheduleMemoShareCardGenerator.deleteRenderedFile(cardURL) }
            .sheet(isPresented: $isSharing) {
                if let cardURL {
                    LeafySystemShare(activityItems: [cardURL])
                }
            }
            .alert("保存结果", isPresented: Binding(
                get: { resultMessage != nil },
                set: { if !$0 { resultMessage = nil } }
            )) {
                Button("好") { resultMessage = nil }
            } message: {
                Text(resultMessage ?? "")
            }
        }
    }

    @MainActor
    private func generate() {
        guard !isGenerating else { return }
        isGenerating = true
        errorMessage = nil
        ScheduleMemoShareCardGenerator.deleteRenderedFile(cardURL)
        cardURL = nil
        defer { isGenerating = false }
        do {
            cardURL = try ScheduleMemoShareCardGenerator.render(source.snapshot)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func saveCard() {
        guard let cardURL else { return }
        Task {
            do {
                try await LeafyPhotoLibrarySaver.saveImageFiles([cardURL])
                resultMessage = "图文长图已保存到系统相册。"
            } catch {
                resultMessage = error.localizedDescription
            }
        }
    }
}
