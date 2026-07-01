import PhotosUI
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct TimetableBackgroundSettingsView: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    @AppStorage(TimetableBackgroundStore.isEnabledKey) private var backgroundIsEnabled = false
    @AppStorage(TimetableBackgroundStore.filenameKey) private var backgroundFilename = ""
    @AppStorage(TimetableBackgroundStore.displayModeKey) private var displayModeRaw = TimetableBackgroundDisplayMode.fill.rawValue
    @AppStorage(TimetableBackgroundStore.imageOpacityKey) private var imageOpacity = TimetableBackgroundStore.defaultImageOpacity
    @AppStorage(TimetableBackgroundStore.blurRadiusKey) private var blurRadius = TimetableBackgroundStore.defaultBlurRadius
    @AppStorage(TimetableBackgroundStore.overlayOpacityKey) private var overlayOpacity = TimetableBackgroundStore.defaultOverlayOpacity
    @AppStorage(TimetableBackgroundStore.courseCardOpacityKey) private var courseCardOpacity = TimetableBackgroundStore.defaultCourseCardOpacity
    @AppStorage(TimetableBackgroundStore.lightPaletteKey) private var lightPaletteHexes = ""
    @AppStorage(TimetableBackgroundStore.darkPaletteKey) private var darkPaletteHexes = ""

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var isImporting = false
    @State private var operationAlert: LeafyOperationAlert?
    @State private var previewLoadTask: Task<Void, Never>?

    private var hasBackgroundImage: Bool {
        !backgroundFilename.isEmpty && previewImage != nil
    }

    private var displayMode: TimetableBackgroundDisplayMode {
        TimetableBackgroundDisplayMode(rawValue: displayModeRaw) ?? .fill
    }

    private var previewPalette: [Color] {
        let colors = TimetableBackgroundStore.colors(from: lightPaletteHexes)
        if !colors.isEmpty { return colors }
        return TimetableBackgroundPalette.fallbackLightHexes.compactMap { TimetableBackgroundStore.colors(from: $0).first }
    }

    var body: some View {
        List {
            Section {
                TimetableBackgroundPreview(
                    image: previewImage,
                    displayMode: displayMode,
                    imageOpacity: imageOpacity,
                    blurRadius: blurRadius,
                    overlayOpacity: overlayOpacity,
                    courseCardOpacity: courseCardOpacity,
                    palette: previewPalette,
                    isImporting: isImporting
                )
                .padding(.vertical, 6)
            } footer: {
                Text(L10n.text("底图只保存在本机，只影响课表页；分享图和小组件会继续使用主题色。", language: leafyLanguage))
            }
            .listRowBackground(AppTheme.cardBackground)

            Section {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    settingsRow(
                        icon: "photo.on.rectangle.angled",
                        title: isImporting ? "读取中" : "选择底图",
                        detail: "从照片中选择一张图片"
                    )
                }
                .buttonStyle(.plain)
                .disabled(isImporting)

                Toggle(isOn: $backgroundIsEnabled) {
                    settingsRow(
                        icon: "rectangle.on.rectangle.angled",
                        title: "启用底图",
                        detail: hasBackgroundImage ? "在课表页显示这张图片" : "选择图片后可开启"
                    )
                }
                .disabled(!hasBackgroundImage)
                .tint(AppTheme.accent)

                if hasBackgroundImage {
                    Button(role: .destructive) {
                        removeBackground()
                    } label: {
                        settingsRow(
                            icon: "trash.fill",
                            title: "移除底图",
                            detail: "删除本机保存的课表底图",
                            tint: AppTheme.danger
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(AppTheme.cardBackground)

            Section(L10n.text("显示方式", language: leafyLanguage)) {
                ForEach(TimetableBackgroundDisplayMode.allCases) { mode in
                    Button {
                        displayModeRaw = mode.rawValue
                        TimetableBackgroundStore.notifySettingsDidChange()
                    } label: {
                        HStack(spacing: 12) {
                            LeafyIconBadge(systemName: mode == .fill ? "rectangle.inset.filled" : "rectangle.center.inset.filled")

                            Text(mode.title(language: leafyLanguage))
                                .leafyBody()
                                .foregroundStyle(AppTheme.primaryText)

                            Spacer()

                            Image(systemName: mode == displayMode ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(mode == displayMode ? AppTheme.accent : AppTheme.tertiaryText)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(AppTheme.cardBackground)

            Section(L10n.text("调节", language: leafyLanguage)) {
                sliderRow(
                    title: "底图可见度",
                    valueText: percentageText(imageOpacity),
                    value: $imageOpacity,
                    range: 0.12...0.55
                )
                sliderRow(
                    title: "模糊强度",
                    valueText: String(format: "%.0f", blurRadius),
                    value: $blurRadius,
                    range: 0...24
                )
                sliderRow(
                    title: "遮罩强度",
                    valueText: percentageText(overlayOpacity),
                    value: $overlayOpacity,
                    range: 0...0.70
                )
                sliderRow(
                    title: "课程卡片浓度",
                    valueText: percentageText(courseCardOpacity),
                    value: $courseCardOpacity,
                    range: 0.50...0.96
                )
            }
            .listRowBackground(AppTheme.cardBackground)
        }
        .leafyInsetGroupedListStyle()
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 760, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(LeafyPageBackground())
        .navigationTitle(L10n.text("课表底图", language: leafyLanguage))
        .leafyInlineNavigationTitle()
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task { await importBackground(from: newItem) }
        }
        .onChange(of: backgroundIsEnabled) { _, _ in
            TimetableBackgroundStore.notifySettingsDidChange()
        }
        .onChange(of: imageOpacity) { _, _ in
            TimetableBackgroundStore.notifySettingsDidChange()
        }
        .onChange(of: blurRadius) { _, _ in
            TimetableBackgroundStore.notifySettingsDidChange()
        }
        .onChange(of: overlayOpacity) { _, _ in
            TimetableBackgroundStore.notifySettingsDidChange()
        }
        .onChange(of: courseCardOpacity) { _, _ in
            TimetableBackgroundStore.notifySettingsDidChange()
        }
        .task {
            reloadPreview()
        }
        .leafyOperationAlert($operationAlert)
    }

    private func settingsRow(icon: String, title: String, detail: String, tint: Color = AppTheme.accent) -> some View {
        HStack(spacing: 12) {
            LeafyIconBadge(systemName: icon, tint: tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text(title, language: leafyLanguage))
                    .leafyBody()
                    .foregroundStyle(AppTheme.primaryText)
                Text(L10n.text(detail, language: leafyLanguage))
                    .microCaption()
                    .foregroundStyle(AppTheme.tertiaryText)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func sliderRow(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.text(title, language: leafyLanguage))
                    .leafyBody()
                    .foregroundStyle(AppTheme.primaryText)

                Spacer()

                Text(valueText)
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
                    .monospacedDigit()
            }

            Slider(value: value, in: range)
                .tint(AppTheme.accent)
        }
        .padding(.vertical, 4)
    }

    private func percentageText(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    @MainActor
    private func importBackground(from item: PhotosPickerItem?) async {
        guard let item else { return }
        isImporting = true
        defer {
            isImporting = false
            selectedPhotoItem = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw TimetableBackgroundImageError.invalidImage
            }

            let result = try await TimetableBackgroundStore.importImageData(data, replacing: backgroundFilename)
            backgroundFilename = result.filename
            lightPaletteHexes = TimetableBackgroundStore.serialize(hexes: result.palette.lightHexes)
            darkPaletteHexes = TimetableBackgroundStore.serialize(hexes: result.palette.darkHexes)
            backgroundIsEnabled = true
            reloadPreview()
            TimetableBackgroundStore.notifySettingsDidChange()
            operationAlert = .success(L10n.text("课表底图已保存。", language: leafyLanguage))
        } catch {
            operationAlert = .failure(L10n.text("加载底图失败：%@", language: leafyLanguage, error.localizedDescription))
        }
    }

    private func reloadPreview() {
        previewLoadTask?.cancel()
        let filename = backgroundFilename
        previewLoadTask = Task {
            let image = await TimetableBackgroundStore.image(filename: filename)
            guard !Task.isCancelled, filename == backgroundFilename else { return }
            previewImage = image
            if image == nil {
                backgroundIsEnabled = false
            }
        }
    }

    private func removeBackground() {
        do {
            try TimetableBackgroundStore.removeBackground(filename: backgroundFilename)
            backgroundIsEnabled = false
            backgroundFilename = ""
            lightPaletteHexes = ""
            darkPaletteHexes = ""
            previewImage = nil
            TimetableBackgroundStore.notifySettingsDidChange()
            operationAlert = .success(L10n.text("课表底图已移除。", language: leafyLanguage))
        } catch {
            operationAlert = .failure(L10n.text("移除底图失败：%@", language: leafyLanguage, error.localizedDescription))
        }
    }
}

private struct TimetableBackgroundPreview: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let image: UIImage?
    let displayMode: TimetableBackgroundDisplayMode
    let imageOpacity: Double
    let blurRadius: Double
    let overlayOpacity: Double
    let courseCardOpacity: Double
    let palette: [Color]
    let isImporting: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .fill(AppTheme.fill)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: displayMode.contentMode)
                    .frame(height: 184)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .blur(radius: blurRadius * 0.36)
                    .opacity(imageOpacity)

                AppTheme.background.opacity(overlayOpacity)

                sampleCards
            } else {
                VStack(spacing: 10) {
                    if isImporting {
                        ProgressView()
                    } else {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(AppTheme.accentEmphasis)
                    }

                    Text(isImporting ? L10n.text("正在读取底图", language: leafyLanguage) : L10n.text("尚未选择底图", language: leafyLanguage))
                        .leafyBody()
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
        .frame(height: 184)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .stroke(AppTheme.separator, lineWidth: 1)
        )
    }

    private var sampleCards: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                VStack(alignment: .leading, spacing: 6) {
                    Text(["森林生态", "数据结构", "英语"][index])
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(2)

                    Text(["二教 203", "主楼 412", "三教 105"][index])
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                }
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
                .background(sampleColor(at: index).opacity(courseCardOpacity))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                        .stroke(AppTheme.separator, lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, 14)
    }

    private func sampleColor(at index: Int) -> Color {
        guard !palette.isEmpty else { return AppTheme.accentSoft }
        return palette[index % palette.count]
    }
}
