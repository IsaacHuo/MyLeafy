import CoreImage.CIFilterBuiltins
import LinkPresentation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
enum AndroidDownloadShareContent {
    static func title(language: AppLanguagePreference) -> String {
        L10n.text("MyLeafy 安卓版", language: language)
    }

    static func snapshot(language: AppLanguagePreference) throws -> CommunityPostCardSnapshot {
        guard let qrData = try qrCode().pngData(),
              let iconData = try LeafyAppIconManager.primaryIconImage().pngData() else {
            throw CommunityPostCardGenerationError.renderFailed
        }
        return CommunityPostCardSnapshot(
            authorName: AppBrand.displayName,
            avatarData: iconData,
            dateText: "Android",
            category: L10n.text("官方下载", language: language),
            title: title(language: language),
            body: L10n.text("MyLeafy 安卓版支持课表、成绩查询、个人日程和校园社区。扫描二维码即可访问官方下载页面，获取安装包与使用说明。欢迎分享给使用安卓手机的同学。", language: language),
            attachmentNames: [],
            photoData: [qrData],
            isAnonymous: false,
            avatarStyle: .appIcon
        )
    }

    static func qrCode() throws -> UIImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(LeafyExternalLinks.androidDownload.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { throw CommunityPostCardGenerationError.renderFailed }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else {
            throw CommunityPostCardGenerationError.renderFailed
        }
        let size = CGSize(width: CGFloat(cgImage.width + 32), height: CGFloat(cgImage.height + 32))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.interpolationQuality = .none
            UIImage(cgImage: cgImage).draw(in: CGRect(x: 16, y: 16, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
        }
    }
}

@MainActor
final class AndroidDownloadLinkItemSource: NSObject, UIActivityItemSource {
    let title: String
    let cardURL: URL
    let appIcon: UIImage

    init(title: String, cardURL: URL, appIcon: UIImage) {
        self.title = title
        self.cardURL = cardURL
        self.appIcon = appIcon
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        LeafyExternalLinks.androidDownload
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        LeafyExternalLinks.androidDownload
    }

    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        title
    }

    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        UTType.url.identifier
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.originalURL = LeafyExternalLinks.androidDownload
        metadata.url = LeafyExternalLinks.androidDownload
        metadata.title = title
        metadata.imageProvider = NSItemProvider(contentsOf: cardURL)
        metadata.iconProvider = NSItemProvider(object: appIcon)
        return metadata
    }
}

struct AndroidDownloadShareView: View {
    @Environment(\.leafyLanguage) private var language
    @State private var cardURL: URL?
    @State private var cardImage: UIImage?
    @State private var iconImage: UIImage?
    @State private var errorMessage: String?
    @State private var shareItems: ShareItems?

    private struct ShareItems: Identifiable {
        let id = UUID()
        let items: [Any]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                Text(L10n.text("向使用安卓手机的同学分享 MyLeafy 下载页面或介绍卡片。", language: language))
                    .leafyBody()
                    .foregroundStyle(AppTheme.secondaryText)

                HStack(spacing: AppSpacing.compact) {
                    Button {
                        guard let cardURL, let iconImage else { return }
                        shareItems = ShareItems(items: [AndroidDownloadLinkItemSource(
                            title: AndroidDownloadShareContent.title(language: language), cardURL: cardURL, appIcon: iconImage
                        )])
                    } label: {
                        Label(L10n.text("分享下载链接", language: language), systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(cardURL == nil)

                    Button {
                        guard let cardURL else { return }
                        shareItems = ShareItems(items: [cardURL])
                    } label: {
                        Label(L10n.text("分享卡片图片", language: language), systemImage: "photo")
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(cardURL == nil)

                }

                if let cardImage {
                    Image(uiImage: cardImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
                        .accessibilityLabel(L10n.text("MyLeafy 安卓版介绍卡片，含官网下载二维码", language: language))
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label(L10n.text("卡片生成失败", language: language), systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button(L10n.text("重试", language: language), action: generateCard)
                    }
                } else {
                    ProgressView(L10n.text("正在生成分享卡片…", language: language))
                        .frame(maxWidth: .infinity, minHeight: 240)
                }

                Link(L10n.text("打开官网下载页", language: language), destination: LeafyExternalLinks.androidDownload)
                Text(L10n.text("链接可以直接打开下载页；图片卡片可以在微信中长按识别二维码。", language: language))
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .padding(AppSpacing.page)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .background(LeafyPageBackground())
        .navigationTitle(L10n.text("分享安卓版", language: language))
        .leafyInlineNavigationTitle()
        .task(id: language) { generateCard() }
        .onDisappear { CommunityPostCardGenerator.deleteRenderedFile(cardURL) }
        .leafySheet(item: $shareItems) { payload in
            ShareSheet(activityItems: payload.items)
        }
    }

    private func generateCard() {
        errorMessage = nil
        do {
            let snapshot = try AndroidDownloadShareContent.snapshot(language: language)
            let newURL = try CommunityPostCardGenerator.render(snapshot)
            guard let image = UIImage(contentsOfFile: newURL.path) else {
                CommunityPostCardGenerator.deleteRenderedFile(newURL)
                throw CommunityPostCardGenerationError.renderFailed
            }
            CommunityPostCardGenerator.deleteRenderedFile(cardURL)
            cardURL = newURL
            cardImage = image
            iconImage = try LeafyAppIconManager.primaryIconImage()
        } catch {
            CommunityPostCardGenerator.deleteRenderedFile(cardURL)
            cardURL = nil
            cardImage = nil
            iconImage = nil
            errorMessage = error.localizedDescription
        }
    }
}

#Preview { NavigationStack { AndroidDownloadShareView() } }
