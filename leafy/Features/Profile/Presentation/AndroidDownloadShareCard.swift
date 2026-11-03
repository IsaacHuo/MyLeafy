import CoreImage.CIFilterBuiltins
import OSLog
import SwiftUI
import UIKit

@MainActor
enum AndroidDownloadShareContent {
    static let canvasSize = CGSize(width: 360, height: 528)
    static let renderScale: CGFloat = 3

    static func title(language: AppLanguagePreference) -> String {
        L10n.text("MyLeafy 安卓版", language: language)
    }

    static func card(language: AppLanguagePreference) throws -> AndroidDownloadShareCard {
        guard let iconImage = UIImage(named: "AndroidShareAppIcon") else {
            throw AndroidDownloadShareCardError.renderFailed
        }
        return try AndroidDownloadShareCard(
            language: language,
            iconImage: iconImage,
            qrImage: qrCode()
        )
    }

    static func qrCode() throws -> UIImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(LeafyExternalLinks.androidDownload.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { throw AndroidDownloadShareCardError.renderFailed }
        let moduleScale: CGFloat = 8
        let scaled = output.transformed(by: CGAffineTransform(scaleX: moduleScale, y: moduleScale))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else {
            throw AndroidDownloadShareCardError.renderFailed
        }
        // Four white modules on every edge preserve the QR code's quiet zone.
        let margin = moduleScale * 4
        let size = CGSize(width: CGFloat(cgImage.width) + margin * 2, height: CGFloat(cgImage.height) + margin * 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.interpolationQuality = .none
            UIImage(cgImage: cgImage).draw(in: CGRect(
                x: margin, y: margin, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)
            ))
        }
    }
}

/// A fixed, light canvas keeps the preview and exported image identical in any app appearance.
struct AndroidDownloadShareCard: View {
    let language: AppLanguagePreference
    let iconImage: UIImage
    let qrImage: UIImage

    private let sage = AppTheme.accent(for: .green)

    var body: some View {
        VStack(spacing: 0) {
            Image(uiImage: iconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            Text(AndroidDownloadShareContent.title(language: language))
                .font(.system(size: 28, weight: .bold))
                .padding(.top, 16)

            Text(L10n.text("课表、日程与校园生活", language: language))
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
                .padding(.top, 6)

            HStack(spacing: 0) {
                feature("calendar", title: "androidShare.feature.timetable")
                featureDivider
                feature("calendar.badge.checkmark", title: "日程")
                featureDivider
                feature("graduationcap", title: "校园")
            }
            .frame(height: 50)
            .padding(.horizontal, 28)
            .padding(.top, 24)

            Image(uiImage: qrImage)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 144, height: 144)
                .padding(.top, 16)

            Text(L10n.text("扫码前往官网下载", language: language))
                .font(.system(size: 16, weight: .semibold))
                .padding(.top, 4)

            Text(verbatim: "myleafy.space")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.top, 3)
        }
        .padding(.top, 44)
        .frame(
            width: AndroidDownloadShareContent.canvasSize.width,
            height: AndroidDownloadShareContent.canvasSize.height,
            alignment: .top
        )
        .background(alignment: .top) {
            AndroidDownloadCardHeader()
                .fill(sage.opacity(0.20))
                .frame(height: 88)
        }
        .background(.white)
        .foregroundStyle(.black)
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .large)
        .environment(\.locale, language.locale)
    }

    private var featureDivider: some View {
        Rectangle()
            .fill(.black.opacity(0.08))
            .frame(width: 1, height: 34)
    }

    private func feature(_ symbol: String, title: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(sage)
                .frame(height: 30)
            Text(L10n.text(title, language: language))
                .font(.system(size: 15, weight: .medium))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AndroidDownloadCardHeader: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: rect.maxX, y: 0))
            path.addCurve(
                to: CGPoint(x: 0, y: rect.maxY),
                control1: CGPoint(x: rect.width * 0.70, y: rect.height * 0.45),
                control2: CGPoint(x: rect.width * 0.30, y: rect.height * 0.10)
            )
            path.closeSubpath()
        }
    }
}

enum AndroidDownloadShareCardError: LocalizedError {
    case renderFailed
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .renderFailed:
            L10n.text("无法生成安卓版分享卡片，请重试。")
        case .writeFailed(let message):
            L10n.text("分享卡片写入失败：%@", message)
        }
    }
}

@MainActor
enum AndroidDownloadShareCardRenderer {
    private static let logger = Logger(subsystem: "com.isaachuo.leafy", category: "AndroidDownloadShare")
    private static let temporaryRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("AndroidDownloadShareCards", isDirectory: true)

    static func render(_ card: AndroidDownloadShareCard) throws -> URL {
        let renderer = ImageRenderer(content: card)
        renderer.scale = AndroidDownloadShareContent.renderScale
        renderer.isOpaque = true
        guard let image = renderer.uiImage, let data = image.pngData() else {
            throw AndroidDownloadShareCardError.renderFailed
        }
        let directory = temporaryRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("MyLeafy-Android.png")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            deleteRenderedFile(url)
            throw AndroidDownloadShareCardError.writeFailed(error.localizedDescription)
        }
    }

    static func deleteRenderedFile(_ url: URL?) {
        guard let directory = url?.deletingLastPathComponent(),
              directory.deletingLastPathComponent().standardizedFileURL == temporaryRoot.standardizedFileURL,
              FileManager.default.fileExists(atPath: directory.path) else { return }
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            logger
                .error("Failed to remove temporary Android share card: \(error.localizedDescription, privacy: .public)")
        }
    }
}
