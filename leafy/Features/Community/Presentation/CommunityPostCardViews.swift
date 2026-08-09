import Foundation
import OSLog
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

nonisolated struct CommunityPostCardTheme: Sendable, Equatable {
    let preferenceRawValue: String
    let accentHex: String
    let backgroundHex: String

    init(
        preferenceRawValue: String,
        customColorHex: String = AppThemeColorPreference.defaultCustomColorHex
    ) {
        let preference = AppThemeColorPreference.storedValue(preferenceRawValue)
        self.preferenceRawValue = preference.rawValue

        switch preference {
        case .tiffanyBlue:
            accentHex = "#81D8D0"
            backgroundHex = "#E8F9F7"
        case .candyPink:
            accentHex = "#FB6095"
            backgroundHex = "#FFEDF4"
        case .custom:
            let resolvedHex = Self.normalizedHex(customColorHex)
            accentHex = resolvedHex
            backgroundHex = Self.softenedHex(resolvedHex)
        case .green:
            accentHex = "#9DC183"
            backgroundHex = "#ECF4E7"
        }
    }

    static var current: CommunityPostCardTheme {
        let defaults = UserDefaults.standard
        return CommunityPostCardTheme(
            preferenceRawValue: defaults.string(forKey: AppThemeColorPreference.storageKey)
                ?? AppThemeColorPreference.green.rawValue,
            customColorHex: defaults.string(forKey: AppThemeColorPreference.customColorHexKey)
                ?? AppThemeColorPreference.defaultCustomColorHex
        )
    }

    private static func normalizedHex(_ hex: String) -> String {
        guard let components = AppThemeColorPreference.rgbComponents(fromHex: hex) else {
            return AppThemeColorPreference.defaultCustomColorHex
        }
        return String(
            format: "#%02X%02X%02X",
            Int(components.red.rounded()),
            Int(components.green.rounded()),
            Int(components.blue.rounded())
        )
    }

    private static func softenedHex(_ accentHex: String) -> String {
        guard let components = AppThemeColorPreference.rgbComponents(fromHex: accentHex) else {
            return "#ECF4E7"
        }
        let whiteRatio = 0.84
        let red = components.red + (255 - components.red) * whiteRatio
        let green = components.green + (255 - components.green) * whiteRatio
        let blue = components.blue + (255 - components.blue) * whiteRatio
        return String(
            format: "#%02X%02X%02X",
            Int(red.rounded()),
            Int(green.rounded()),
            Int(blue.rounded())
        )
    }
}

nonisolated struct CommunityPostCardSnapshot: Sendable {
    let authorName: String
    let avatarData: Data?
    let avatarFallbackText: String?
    let dateText: String
    let category: String
    let title: String
    let body: String
    let attachmentNames: [String]
    let photoData: [Data]
    let isAnonymous: Bool
    let theme: CommunityPostCardTheme

    init(
        authorName: String,
        avatarData: Data?,
        avatarFallbackText: String? = nil,
        dateText: String,
        category: String,
        title: String,
        body: String,
        attachmentNames: [String],
        photoData: [Data],
        isAnonymous: Bool,
        theme: CommunityPostCardTheme = .current
    ) {
        self.authorName = authorName
        self.avatarData = avatarData
        self.avatarFallbackText = avatarFallbackText
        self.dateText = dateText
        self.category = category
        self.title = title
        self.body = body
        self.attachmentNames = attachmentNames
        self.photoData = photoData
        self.isAnonymous = isAnonymous
        self.theme = theme
    }

    var resolvedAvatarFallbackText: String {
        if isAnonymous {
            return "匿"
        }
        let supplied = avatarFallbackText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let first = supplied.first {
            return String(first)
        }
        let author = authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        return author.first.map(String.init) ?? "我"
    }
}

nonisolated enum CommunityPostCardGenerationError: LocalizedError, Sendable {
    case avatarDownloadFailed
    case photoDownloadFailed(Int)
    case invalidImage(Int)
    case contentTooLong
    case renderFailed
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .avatarDownloadFailed:
            return L10n.text("作者头像下载失败，请检查网络后重试。")
        case .photoDownloadFailed(let index):
            return L10n.text("第 %d 张帖子图片下载失败，请检查网络后重试。", index)
        case .invalidImage(let index):
            return L10n.text("第 %d 张帖子图片无法读取。", index)
        case .contentTooLong:
            return L10n.text("图文卡片内容过长，无法生成清晰的单张长图。请精简正文或图片后重试。")
        case .renderFailed:
            return L10n.text("图文卡片生成失败，请稍后重试。")
        case .writeFailed(let message):
            return L10n.text("图文卡片写入失败：%@", message)
        }
    }
}

@MainActor
enum CommunityPostCardLayout {
    static let canvasWidth: CGFloat = 360
    static let renderScale: CGFloat = 3
    static let maxPixelHeight = 16_384
    static let contentWidth: CGFloat = 284
    static let photoSpacing: CGFloat = 8
    static let textOnlyMinimumCanvasHeight: CGFloat = 240
    static let photoMinimumCanvasHeight: CGFloat = 360

    static func estimatedHeight(
        snapshot: CommunityPostCardSnapshot,
        photos: [UIImage]
    ) -> CGFloat {
        var sectionHeights: [CGFloat] = [42]
        sectionHeights.append(measuredHeight(snapshot.title, fontSize: 22, weight: .bold))
        if !snapshot.body.isEmpty {
            sectionHeights.append(
                measuredHeight(snapshot.body, fontSize: 15, weight: .regular, lineSpacing: 4)
            )
        }

        let attachmentCount = min(
            snapshot.attachmentNames.count,
            CommunityPostAttachment.postAttachmentLimit
        )
        if attachmentCount > 0 {
            sectionHeights.append(38 + CGFloat(attachmentCount * 22))
        }

        if !photos.isEmpty {
            sectionHeights.append(photoRowHeight(photos: photos))
        }
        sectionHeights.append(16)

        let sectionSpacing = CGFloat(max(0, sectionHeights.count - 1)) * 16
        let outerAndCardPadding: CGFloat = 76
        let measurementSafetyMargin: CGFloat = 24
        let measuredHeight = ceil(
            sectionHeights.reduce(0, +) +
            sectionSpacing +
            outerAndCardPadding +
            measurementSafetyMargin
        )
        return max(measuredHeight, minimumCanvasHeight(hasPhotos: !photos.isEmpty))
    }

    static func exceedsSafeHeight(
        snapshot: CommunityPostCardSnapshot,
        photos: [UIImage]
    ) -> Bool {
        estimatedHeight(snapshot: snapshot, photos: photos) * renderScale >
            CGFloat(maxPixelHeight)
    }

    static func minimumCanvasHeight(hasPhotos: Bool) -> CGFloat {
        hasPhotos ? photoMinimumCanvasHeight : textOnlyMinimumCanvasHeight
    }

    private static func photoRowHeight(photos: [UIImage]) -> CGFloat {
        if photos.count == 1,
           let photo = photos.first,
           photo.size.width > photo.size.height,
           photo.size.width > 0 {
            return floor(contentWidth * photo.size.height / photo.size.width)
        }

        let count = max(photos.count, 1)
        let totalSpacing = CGFloat(count - 1) * photoSpacing
        return floor(max(contentWidth - totalSpacing, 0) / CGFloat(count))
    }

    private static func measuredHeight(
        _ text: String,
        fontSize: CGFloat,
        weight: LeafyCardFontWeight,
        lineSpacing: CGFloat = 0
    ) -> CGFloat {
        guard !text.isEmpty else { return 0 }
#if canImport(UIKit)
        let font = UIFont.systemFont(ofSize: fontSize, weight: weight.uiKitWeight)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph
        ]
#elseif canImport(AppKit)
        let font = NSFont.systemFont(ofSize: fontSize, weight: weight.appKitWeight)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph
        ]
#endif
        return ceil(
            (text as NSString).boundingRect(
                with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            ).height
        )
    }
}

private enum LeafyCardFontWeight {
    case regular
    case bold

#if canImport(UIKit)
    var uiKitWeight: UIFont.Weight {
        switch self {
        case .regular: return .regular
        case .bold: return .bold
        }
    }
#elseif canImport(AppKit)
    var appKitWeight: NSFont.Weight {
        switch self {
        case .regular: return .regular
        case .bold: return .bold
        }
    }
#endif
}

@MainActor
enum CommunityPostCardGenerator {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "MyLeafy",
        category: "CommunityShareCards"
    )
    static let temporaryRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("CommunityPostCards", isDirectory: true)

    static func snapshot(from post: CommunityPost) async throws -> CommunityPostCardSnapshot {
        let avatarData: Data?
        if post.isAnonymous {
            avatarData = nil
        } else if let avatarURL = post.author?.resolvedAvatarURL {
            do {
                avatarData = try await downloadData(from: avatarURL)
            } catch {
                throw CommunityPostCardGenerationError.avatarDownloadFailed
            }
        } else {
            avatarData = nil
        }

        var photos: [Data] = []
        for (index, image) in post.images.sorted(by: { $0.sortOrder < $1.sortOrder }).enumerated() {
            guard let url = image.resolvedFullURL else {
                throw CommunityPostCardGenerationError.photoDownloadFailed(index + 1)
            }
            do {
                photos.append(try await downloadData(from: url))
            } catch {
                throw CommunityPostCardGenerationError.photoDownloadFailed(index + 1)
            }
        }

        return CommunityPostCardSnapshot(
            authorName: post.displayAuthorName,
            avatarData: avatarData,
            dateText: post.relativeTimestamp,
            category: post.categoryLabel,
            title: post.title,
            body: post.body,
            attachmentNames: post.attachments
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(\.displayName),
            photoData: photos,
            isAnonymous: post.isAnonymous
        )
    }

    static func snapshot(
        from payload: CommunityPostDraftEditorPayload,
        profile: CommunityProfile
    ) async throws -> CommunityPostCardSnapshot {
        let avatarData: Data?
        if payload.draft.input.isAnonymous {
            avatarData = nil
        } else if let avatarURL = profile.resolvedAvatarURL {
            do {
                avatarData = try await downloadData(from: avatarURL)
            } catch {
                throw CommunityPostCardGenerationError.avatarDownloadFailed
            }
        } else {
            avatarData = nil
        }

        return CommunityPostCardSnapshot(
            authorName: payload.draft.input.isAnonymous
                ? L10n.text("匿名同学")
                : profile.limitedResolvedDisplayName,
            avatarData: avatarData,
            dateText: DateFormatters.headerWithTime.string(from: payload.draft.updatedAt),
            category: CommunityPostCategory.normalized(payload.draft.input.category) ?? L10n.text("社区"),
            title: payload.draft.displayTitle,
            body: payload.draft.input.body,
            attachmentNames: payload.draft.attachments
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(\.displayName),
            photoData: payload.images.map(\.data),
            isAnonymous: payload.draft.input.isAnonymous
        )
    }

    static func render(_ snapshot: CommunityPostCardSnapshot) throws -> URL {
        let photos = try snapshot.photoData.enumerated().map { index, data in
            guard let image = UIImage(data: data),
                  image.size.width > 0,
                  image.size.height > 0 else {
                throw CommunityPostCardGenerationError.invalidImage(index + 1)
            }
            return image
        }
        guard !CommunityPostCardLayout.exceedsSafeHeight(snapshot: snapshot, photos: photos) else {
            throw CommunityPostCardGenerationError.contentTooLong
        }

        let view = CommunityPostLongCardView(snapshot: snapshot, photos: photos)
            .frame(width: CommunityPostCardLayout.canvasWidth)
            .fixedSize(horizontal: false, vertical: true)
        let renderer = ImageRenderer(content: view)
        renderer.scale = CommunityPostCardLayout.renderScale
        guard let image = renderer.leafyPlatformImage,
              let cgImage = image.cgImage else {
            throw CommunityPostCardGenerationError.renderFailed
        }
        guard cgImage.height <= CommunityPostCardLayout.maxPixelHeight else {
            throw CommunityPostCardGenerationError.contentTooLong
        }
        guard let data = image.jpegData(compressionQuality: 0.92) else {
            throw CommunityPostCardGenerationError.renderFailed
        }

        let directory = temporaryRoot
            .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        let url = directory.appendingPathComponent("MyLeafy-card.jpg")

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return url
        } catch let error as CommunityPostCardGenerationError {
            try? FileManager.default.removeItem(at: directory)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw CommunityPostCardGenerationError.writeFailed(error.localizedDescription)
        }
    }

    static func deleteRenderedFile(_ url: URL?) {
        guard let directory = url?.deletingLastPathComponent() else { return }
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            logger.error(
                "Delete share-card files failed directory=\(directory.lastPathComponent, privacy: .public) error=\(error.localizedDescription, privacy: .private)"
            )
        }
    }

    static func cleanupStaleRenderedFiles() {
        guard FileManager.default.fileExists(atPath: temporaryRoot.path) else { return }
        do {
            try FileManager.default.removeItem(at: temporaryRoot)
        } catch {
            logger.error(
                "Clean stale share-card files failed error=\(error.localizedDescription, privacy: .private)"
            )
        }
    }

    private static func downloadData(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              UIImage(data: data) != nil else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

struct CommunityPostCardPreviewSource: Identifiable {
    enum Content {
        case post(CommunityPost)
        case draft(CommunityPostDraftEditorPayload, CommunityProfile)
        case snapshot(CommunityPostCardSnapshot)
    }

    let id = UUID()
    let content: Content
}

struct CommunityPostCardPreviewSheet: View {
    let source: CommunityPostCardPreviewSource

    @Environment(\.dismiss) private var dismiss
    @State private var cardURL: URL?
    @State private var isGenerating = false
    @State private var isSaving = false
    @State private var isSharing = false
    @State private var errorMessage: String?
    @State private var resultMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isGenerating {
                    ProgressView("正在生成图文卡片…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("生成失败", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("重试") {
                            Task { await generate() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if let cardURL {
                    GeometryReader { geometry in
                        ScrollView {
                            if let image = UIImage(contentsOfFile: cardURL.path) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: max(
                                        geometry.size.width - AppSpacing.page * 2,
                                        1
                                    ))
                                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
                                    .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
                                    .padding(AppSpacing.page)
                            } else {
                                ContentUnavailableView(
                                    "长图无法读取",
                                    systemImage: "photo.badge.exclamationmark"
                                )
                                .frame(maxWidth: .infinity, minHeight: 320)
                                .padding(AppSpacing.page)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("没有可预览的长图", systemImage: "photo.on.rectangle")
                }
            }
            .background(LeafyPageBackground())
            .navigationTitle("图文卡片")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItemGroup(placement: .leafyTrailing) {
                    Button {
                        Task { await saveCard() }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .disabled(cardURL == nil || isGenerating || isSaving)
                    .accessibilityLabel(isSaving ? "正在保存长图" : "保存长图")

                    Button {
                        isSharing = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(cardURL == nil || isGenerating)
                    .accessibilityLabel("分享长图")
                }
            }
            .task {
                await generate()
            }
            .onDisappear {
                CommunityPostCardGenerator.deleteRenderedFile(cardURL)
            }
            .sheet(isPresented: $isSharing) {
                if let cardURL {
                    ShareSheet(activityItems: [cardURL])
                }
            }
            .alert("保存结果", isPresented: Binding(
                get: { resultMessage != nil },
                set: { if !$0 { resultMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(resultMessage ?? "")
            }
        }
    }

    @MainActor
    private func generate() async {
        guard !isGenerating else { return }
        isGenerating = true
        errorMessage = nil
        CommunityPostCardGenerator.deleteRenderedFile(cardURL)
        cardURL = nil
        defer { isGenerating = false }

        do {
            let snapshot: CommunityPostCardSnapshot
            switch source.content {
            case .post(let post):
                snapshot = try await CommunityPostCardGenerator.snapshot(from: post)
            case .draft(let payload, let profile):
                snapshot = try await CommunityPostCardGenerator.snapshot(from: payload, profile: profile)
            case .snapshot(let suppliedSnapshot):
                snapshot = suppliedSnapshot
            }
            cardURL = try CommunityPostCardGenerator.render(snapshot)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func saveCard() async {
        guard let cardURL, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await LeafyPhotoLibrarySaver.saveImageFiles([cardURL])
#if os(macOS)
            resultMessage = L10n.text("已保存到所选文件夹。")
#else
            resultMessage = L10n.text("图文长图已保存到系统相册。")
#endif
        } catch {
            resultMessage = error.localizedDescription
        }
    }
}

private struct CommunityPostLongCardView: View {
    let snapshot: CommunityPostCardSnapshot
    let photos: [UIImage]

    private let card = Color.white
    private let ink = Color(red: 0.10, green: 0.12, blue: 0.11)
    private let secondary = Color(red: 0.42, green: 0.45, blue: 0.43)

    private var background: Color {
        AppThemeColorPreference.color(fromHex: snapshot.theme.backgroundHex)
    }

    private var accent: Color {
        AppThemeColorPreference.color(fromHex: snapshot.theme.accentHex)
    }

    private var minimumCanvasHeight: CGFloat {
        CommunityPostCardLayout.minimumCanvasHeight(hasPhotos: !photos.isEmpty)
    }

    private var minimumContentHeight: CGFloat {
        max(minimumCanvasHeight - 76, 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                identityHeader
                title

                if !snapshot.body.isEmpty {
                    bodyText
                }

                if !attachmentNames.isEmpty {
                    attachments
                }

                if !photos.isEmpty {
                    photosSection
                }

                footer
            }
            .frame(maxWidth: .infinity, minHeight: minimumContentHeight, alignment: .topLeading)
            .padding(20)
            .background(card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 18, y: 9)
            .padding(18)
        }
        .frame(width: CommunityPostCardLayout.canvasWidth)
        .frame(minHeight: minimumCanvasHeight, alignment: .top)
        .background(background)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.colorScheme, .light)
    }

    private var identityHeader: some View {
        HStack(spacing: 10) {
            Group {
                if !snapshot.isAnonymous,
                   let data = snapshot.avatarData,
                   let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Text(snapshot.resolvedAvatarFallbackText)
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
                    .foregroundStyle(ink)
                    .lineLimit(1)
                Text("\(snapshot.dateText) · \(snapshot.category)")
                    .font(.system(size: 10))
                    .foregroundStyle(secondary)
                    .lineLimit(1)
            }
        }
    }

    private var title: some View {
        Text(snapshot.title)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var bodyText: some View {
        Text(snapshot.body)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(ink)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attachmentNames: [String] {
        Array(snapshot.attachmentNames.prefix(CommunityPostAttachment.postAttachmentLimit))
    }

    @ViewBuilder
    private var photosSection: some View {
        if photos.count == 1,
           let photo = photos.first,
           photo.size.width > photo.size.height {
            Image(uiImage: photo)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            HStack(spacing: CommunityPostCardLayout.photoSpacing) {
                ForEach(Array(photos.enumerated()), id: \.offset) { _, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .clipped()
                }
            }
        }
    }

    private var attachments: some View {
        VStack(alignment: .leading, spacing: 7) {
            Divider()

            Text("附件")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(secondary)

            ForEach(attachmentNames, id: \.self) { name in
                Label(name, systemImage: "paperclip")
                    .font(.system(size: 11))
                    .foregroundStyle(ink)
                    .lineLimit(1)
            }
        }
    }

    private var footer: some View {
        Text(AppBrand.displayName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(accent)
    }
}
