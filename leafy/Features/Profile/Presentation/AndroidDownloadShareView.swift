import LinkPresentation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class AndroidDownloadLinkItemSource: NSObject, UIActivityItemSource {
    let title: String
    let cardURL: URL?
    let appIcon: UIImage?

    init(title: String, cardURL: URL? = nil, appIcon: UIImage? = nil) {
        self.title = title
        self.cardURL = cardURL
        self.appIcon = appIcon
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        LeafyExternalLinks.androidDownload
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        LeafyExternalLinks.androidDownload
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        title
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        UTType.url.identifier
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.originalURL = LeafyExternalLinks.androidDownload
        metadata.url = LeafyExternalLinks.androidDownload
        metadata.title = title
        if let cardURL { metadata.imageProvider = NSItemProvider(contentsOf: cardURL) }
        if let appIcon { metadata.iconProvider = NSItemProvider(object: appIcon) }
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
                Text(L10n.text("把 MyLeafy 分享给安卓同学", language: language))
                    .font(.title3.bold())
                    .foregroundStyle(AppTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let cardImage {
                    Image(uiImage: cardImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(.black.opacity(0.05), lineWidth: 0.5)
                        }
                        .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
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

                VStack(spacing: 12) {
                    Button {
                        shareItems = ShareItems(items: [AndroidDownloadLinkItemSource(
                            title: AndroidDownloadShareContent.title(language: language),
                            cardURL: cardURL, appIcon: iconImage
                        )])
                    } label: {
                        Text(L10n.text("分享下载链接", language: language))
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.vertical, 2)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(AppTheme.accentEmphasis)

                    Button {
                        guard let cardURL else { return }
                        shareItems = ShareItems(items: [cardURL])
                    } label: {
                        Text(L10n.text("分享卡片图片", language: language))
                            .font(.body.weight(.medium))
                            .foregroundStyle(AppTheme.primaryText)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.vertical, 2)
                            .contentShape(Capsule())
                            .overlay { Capsule().strokeBorder(AppTheme.secondaryText.opacity(0.3), lineWidth: 0.5) }
                    }
                    .buttonStyle(.plain)
                    .disabled(cardURL == nil)
                    .opacity(cardURL == nil ? 0.5 : 1)
                }
                .padding(.top, 6)

                Link(L10n.text("打开官网下载页", language: language), destination: LeafyExternalLinks.androidDownload)
                    .font(.body.weight(.medium))
                    .foregroundStyle(AppTheme.accentEmphasis)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(AppSpacing.page)
            .frame(maxWidth: 400)
            .frame(maxWidth: .infinity)
        }
        .background(LeafyPageBackground())
        .navigationTitle(L10n.text("分享安卓版", language: language))
        .leafyInlineNavigationTitle()
        .task(id: language) {
            await Task.yield()
            guard !Task.isCancelled else { return }
            generateCard()
        }
        .onDisappear { AndroidDownloadShareCardRenderer.deleteRenderedFile(cardURL) }
        .leafySheet(item: $shareItems) { payload in
            ShareSheet(activityItems: payload.items)
        }
    }

    private func generateCard() {
        errorMessage = nil
        do {
            let card = try AndroidDownloadShareContent.card(language: language)
            iconImage = card.iconImage
            let newURL = try AndroidDownloadShareCardRenderer.render(card)
            guard let image = UIImage(contentsOfFile: newURL.path) else {
                AndroidDownloadShareCardRenderer.deleteRenderedFile(newURL)
                throw AndroidDownloadShareCardError.renderFailed
            }
            AndroidDownloadShareCardRenderer.deleteRenderedFile(cardURL)
            cardURL = newURL
            cardImage = image
        } catch {
            AndroidDownloadShareCardRenderer.deleteRenderedFile(cardURL)
            cardURL = nil
            cardImage = nil
            iconImage = nil
            errorMessage = error.localizedDescription
        }
    }
}

#Preview { NavigationStack { AndroidDownloadShareView() } }
