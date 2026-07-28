import Foundation
import OSLog
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

nonisolated struct CommunityPostCardSnapshot: Sendable {
    let authorName: String
    let avatarData: Data?
    let dateText: String
    let category: String
    let title: String
    let body: String
    let attachmentNames: [String]
    let photoData: [Data]
    let isAnonymous: Bool
}

nonisolated enum CommunityPostCardPage: Sendable {
    case text(body: String, showsTitle: Bool, attachmentNames: [String])
    case photo(Data)
}

nonisolated enum CommunityPostCardGenerationError: LocalizedError, Sendable {
    case avatarDownloadFailed
    case photoDownloadFailed(Int)
    case invalidImage(Int)
    case renderFailed(Int)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .avatarDownloadFailed:
            return L10n.text("作者头像下载失败，请检查网络后重试。")
        case .photoDownloadFailed(let index):
            return L10n.text("第 %d 张帖子图片下载失败，请检查网络后重试。", index)
        case .invalidImage(let index):
            return L10n.text("第 %d 张帖子图片无法读取。", index)
        case .renderFailed(let index):
            return L10n.text("第 %d 页图文卡片生成失败，请稍后重试。", index)
        case .writeFailed(let message):
            return L10n.text("图文卡片写入失败：%@", message)
        }
    }
}

nonisolated enum CommunityPostCardPaginator {
    static let textWidth: CGFloat = 304
    static let firstPageBodyHeight: CGFloat = 330
    static let continuationBodyHeight: CGFloat = 420

    static func pages(
        title _: String,
        body: String,
        attachmentNames: [String]
    ) -> [CommunityPostCardPage] {
        var remaining = body
        var textPages: [(body: String, showsTitle: Bool)] = []
        var isFirstPage = true

        repeat {
            let height = isFirstPage ? firstPageBodyHeight : continuationBodyHeight
            let prefixCount = fittingPrefixCount(in: remaining, maxHeight: height)
            let count = remaining.isEmpty ? 0 : max(1, prefixCount)
            let splitIndex = remaining.index(remaining.startIndex, offsetBy: count)
            let fragment = String(remaining[..<splitIndex])
            textPages.append((fragment, isFirstPage))
            remaining = String(remaining[splitIndex...])
            isFirstPage = false
        } while !remaining.isEmpty

        if textPages.isEmpty {
            textPages = [("", true)]
        }

        let names = Array(attachmentNames.prefix(CommunityPostAttachment.postAttachmentLimit))
        if !names.isEmpty, let last = textPages.last {
            let availableHeight = last.showsTitle ? firstPageBodyHeight : continuationBodyHeight
            let attachmentHeight = CGFloat(38 + names.count * 24)
            let bodyHeight = measuredHeight(last.body)
            if bodyHeight + attachmentHeight <= availableHeight {
                textPages.removeLast()
                return textPages.map {
                    .text(body: $0.body, showsTitle: $0.showsTitle, attachmentNames: [])
                } + [
                    .text(body: last.body, showsTitle: last.showsTitle, attachmentNames: names)
                ]
            }
            return textPages.map {
                .text(body: $0.body, showsTitle: $0.showsTitle, attachmentNames: [])
            } + [
                .text(body: "", showsTitle: false, attachmentNames: names)
            ]
        }

        return textPages.map {
            .text(body: $0.body, showsTitle: $0.showsTitle, attachmentNames: [])
        }
    }

    private static func fittingPrefixCount(in text: String, maxHeight: CGFloat) -> Int {
        guard !text.isEmpty else { return 0 }
        let totalCount = text.count
        var best = 0
        var probe = min(512, totalCount)

        while true {
            let index = text.index(text.startIndex, offsetBy: probe)
            let candidate = String(text[..<index])
            guard measuredHeight(candidate) <= maxHeight else { break }
            best = probe
            guard probe < totalCount else { return totalCount }
            probe = min(totalCount, probe * 2)
        }

        var lower = best + 1
        var upper = probe - 1

        while lower <= upper {
            let middle = (lower + upper) / 2
            let index = text.index(text.startIndex, offsetBy: middle)
            let candidate = String(text[..<index])
            if measuredHeight(candidate) <= maxHeight {
                best = middle
                lower = middle + 1
            } else {
                upper = middle - 1
            }
        }

        guard best > 0, best < text.count else { return best }
        let bestIndex = text.index(text.startIndex, offsetBy: best)
        let candidate = String(text[..<bestIndex])
        let preferredBreaks = ["\n", "。", "！", "？", ".", "!", "?", " "]
        let minimumPreferredCount = max(1, Int(Double(best) * 0.72))
        for token in preferredBreaks {
            if let range = candidate.range(of: token, options: .backwards) {
                let count = candidate.distance(from: candidate.startIndex, to: range.upperBound)
                if count >= minimumPreferredCount {
                    return count
                }
            }
        }
        return best
    }

    private static func measuredHeight(_ text: String) -> CGFloat {
        guard !text.isEmpty else { return 0 }
#if canImport(UIKit)
        let font = UIFont.systemFont(ofSize: 17, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph
        ]
#elseif canImport(AppKit)
        let font = NSFont.systemFont(ofSize: 17, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph
        ]
#endif
        return ceil(
            (text as NSString).boundingRect(
                with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            ).height
        )
    }
}

@MainActor
enum CommunityPostCardGenerator {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "MyLeafy",
        category: "CommunityShareCards"
    )
    private static let temporaryRoot = FileManager.default.temporaryDirectory
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

    static func render(_ snapshot: CommunityPostCardSnapshot) throws -> [URL] {
        var pages = CommunityPostCardPaginator.pages(
            title: snapshot.title,
            body: snapshot.body,
            attachmentNames: snapshot.attachmentNames
        )
        pages.append(contentsOf: snapshot.photoData.map(CommunityPostCardPage.photo))

        let directory = temporaryRoot
            .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var urls: [URL] = []
            for (index, page) in pages.enumerated() {
                let view = CommunityPostShareCardPageView(
                    snapshot: snapshot,
                    page: page,
                    pageNumber: index + 1,
                    totalPages: pages.count
                )
                .frame(width: 360, height: 640)

                let renderer = ImageRenderer(content: view)
                renderer.scale = 3
                guard let image = renderer.leafyPlatformImage,
                      let data = image.jpegData(compressionQuality: 0.92) else {
                    throw CommunityPostCardGenerationError.renderFailed(index + 1)
                }
                let url = directory.appendingPathComponent(
                    String(format: "MyLeafy-card-%02d.jpg", index + 1)
                )
                try data.write(to: url, options: .atomic)
                urls.append(url)
            }
            return urls
        } catch let error as CommunityPostCardGenerationError {
            try? FileManager.default.removeItem(at: directory)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw CommunityPostCardGenerationError.writeFailed(error.localizedDescription)
        }
    }

    static func deleteRenderedFiles(_ urls: [URL]) {
        guard let directory = urls.first?.deletingLastPathComponent() else { return }
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
    }

    let id = UUID()
    let content: Content
}

struct CommunityPostCardPreviewSheet: View {
    let source: CommunityPostCardPreviewSource

    @Environment(\.dismiss) private var dismiss
    @State private var pageURLs: [URL] = []
    @State private var selectedPage = 0
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
                } else if pageURLs.isEmpty {
                    ContentUnavailableView("没有可预览的页面", systemImage: "photo.on.rectangle")
                } else {
                    VStack(spacing: 12) {
                        TabView(selection: $selectedPage) {
                            ForEach(Array(pageURLs.enumerated()), id: \.offset) { index, url in
                                if let image = UIImage(contentsOfFile: url.path) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
                                        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
                                        .padding(.horizontal, AppSpacing.page)
                                        .tag(index)
                                } else {
                                    ContentUnavailableView("页面无法读取", systemImage: "photo.badge.exclamationmark")
                                        .tag(index)
                                }
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))

                        Text("\(selectedPage + 1) / \(pageURLs.count)")
                            .microCaption()
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .padding(.vertical, AppSpacing.compact)
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
                        Task { await saveAllPages() }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .disabled(pageURLs.isEmpty || isGenerating || isSaving)
                    .accessibilityLabel(isSaving ? "正在保存卡片" : "保存全部卡片")

                    Button {
                        isSharing = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(pageURLs.isEmpty || isGenerating)
                    .accessibilityLabel("分享全部卡片")
                }
            }
            .task {
                await generate()
            }
            .onDisappear {
                CommunityPostCardGenerator.deleteRenderedFiles(pageURLs)
            }
            .sheet(isPresented: $isSharing) {
                ShareSheet(activityItems: pageURLs)
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
        CommunityPostCardGenerator.deleteRenderedFiles(pageURLs)
        pageURLs = []
        selectedPage = 0
        defer { isGenerating = false }

        do {
            let snapshot: CommunityPostCardSnapshot
            switch source.content {
            case .post(let post):
                snapshot = try await CommunityPostCardGenerator.snapshot(from: post)
            case .draft(let payload, let profile):
                snapshot = try await CommunityPostCardGenerator.snapshot(from: payload, profile: profile)
            }
            pageURLs = try CommunityPostCardGenerator.render(snapshot)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func saveAllPages() async {
        guard !pageURLs.isEmpty, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await LeafyPhotoLibrarySaver.saveImageFiles(pageURLs)
#if os(macOS)
            resultMessage = L10n.text("已保存到所选文件夹。")
#else
            resultMessage = L10n.text("已保存 %d 张图文卡片到系统相册。", pageURLs.count)
#endif
        } catch {
            resultMessage = error.localizedDescription
        }
    }
}

private struct CommunityPostShareCardPageView: View {
    let snapshot: CommunityPostCardSnapshot
    let page: CommunityPostCardPage
    let pageNumber: Int
    let totalPages: Int

    private let background = Color(red: 0.965, green: 0.958, blue: 0.935)
    private let card = Color.white
    private let ink = Color(red: 0.10, green: 0.12, blue: 0.11)
    private let secondary = Color(red: 0.42, green: 0.45, blue: 0.43)
    private let accent = Color(red: 0.12, green: 0.48, blue: 0.32)

    var body: some View {
        ZStack {
            background
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(card)
                .shadow(color: .black.opacity(0.08), radius: 18, y: 9)
                .padding(18)

            VStack(alignment: .leading, spacing: 16) {
                identityHeader

                switch page {
                case .text(let body, let showsTitle, let attachmentNames):
                    textContent(body: body, showsTitle: showsTitle, attachmentNames: attachmentNames)
                case .photo(let data):
                    photoContent(data: data)
                }

                Spacer(minLength: 0)
                footer
            }
            .padding(38)
        }
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
                    Image(systemName: snapshot.isAnonymous ? "person.crop.circle.fill" : "leaf.fill")
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                        .foregroundStyle(accent)
                        .background(accent.opacity(0.10))
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

    private func textContent(
        body: String,
        showsTitle: Bool,
        attachmentNames: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsTitle {
                Text(snapshot.title)
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !body.isEmpty {
                Text(body)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(ink)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !attachmentNames.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 7) {
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
        }
    }

    @ViewBuilder
    private func photoContent(data: Data) -> some View {
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 460)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            ContentUnavailableView("图片无法读取", systemImage: "photo.badge.exclamationmark")
        }
    }

    private var footer: some View {
        HStack {
            Label(AppBrand.displayName, systemImage: "leaf.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent)
            Spacer()
            Text("\(pageNumber) / \(totalPages)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(secondary)
        }
    }
}
