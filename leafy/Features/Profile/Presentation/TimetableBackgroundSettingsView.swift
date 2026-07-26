import PhotosUI
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct TimetableBackgroundSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.leafyLanguage) private var leafyLanguage

    @AppStorage(TimetableBackgroundStore.isEnabledKey) private var backgroundIsEnabled = false
    @AppStorage(TimetableBackgroundStore.kindKey) private var kindRaw = TimetableBackgroundKind.photo.rawValue
    @AppStorage(TimetableBackgroundStore.filenameKey) private var backgroundFilename = ""
    @AppStorage(TimetableBackgroundStore.displayModeKey) private var displayModeRaw = TimetableBackgroundDisplayMode.fill.rawValue
    @AppStorage(TimetableBackgroundStore.imageOpacityKey) private var imageOpacity = TimetableBackgroundStore.defaultImageOpacity
    @AppStorage(TimetableBackgroundStore.blurRadiusKey) private var blurRadius = TimetableBackgroundStore.defaultBlurRadius
    @AppStorage(TimetableBackgroundStore.overlayOpacityKey) private var overlayOpacity = TimetableBackgroundStore.defaultOverlayOpacity
    @AppStorage(TimetableBackgroundStore.courseCardOpacityKey) private var courseCardOpacity = TimetableBackgroundStore.defaultCourseCardOpacity
    @AppStorage(TimetableBackgroundStore.lightPaletteKey) private var lightPaletteHexes = ""
    @AppStorage(TimetableBackgroundStore.darkPaletteKey) private var darkPaletteHexes = ""
    @AppStorage(TimetableBackgroundStore.solidColorHexKey) private var solidColorHex = TimetableBackgroundStore.defaultSolidColorHex

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var isImporting = false
    @State private var previewLoadFailed = false
    @State private var operationAlert: LeafyOperationAlert?

    private var selectedKind: TimetableBackgroundKind {
        TimetableBackgroundKind.resolved(rawValue: kindRaw)
    }

    private var kindBinding: Binding<TimetableBackgroundKind> {
        Binding(
            get: { selectedKind },
            set: { newValue in
                kindRaw = newValue.rawValue
                if newValue == .photo, !hasBackgroundImage {
                    backgroundIsEnabled = false
                }
            }
        )
    }

    private var displayMode: TimetableBackgroundDisplayMode {
        TimetableBackgroundDisplayMode(rawValue: displayModeRaw) ?? .fill
    }

    private var hasBackgroundImage: Bool {
        !backgroundFilename.isEmpty && previewImage != nil
    }

    private var canEnableBackground: Bool {
        selectedKind == .solid || hasBackgroundImage
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { backgroundIsEnabled && canEnableBackground },
            set: { newValue in
                backgroundIsEnabled = newValue && canEnableBackground
            }
        )
    }

    private var previewConfiguration: TimetableBackgroundConfiguration {
        TimetableBackgroundConfiguration(
            isEnabled: true,
            kind: selectedKind,
            filename: backgroundFilename,
            displayMode: displayMode,
            imageOpacity: imageOpacity,
            blurRadius: blurRadius * 0.36,
            overlayOpacity: overlayOpacity,
            courseCardOpacity: courseCardOpacity,
            lightPaletteHexes: lightPaletteHexes,
            darkPaletteHexes: darkPaletteHexes,
            solidColorHex: solidColorHex
        )
    }

    @MainActor
    private var previewPalette: [Color] {
        let hexes: [String]
        switch selectedKind {
        case .photo:
            let serialized = colorScheme == .dark ? darkPaletteHexes : lightPaletteHexes
            let storedColors = TimetableBackgroundStore.colors(from: serialized)
            if !storedColors.isEmpty {
                return storedColors
            }
            hexes = colorScheme == .dark
                ? TimetableBackgroundPalette.fallbackDarkHexes
                : TimetableBackgroundPalette.fallbackLightHexes
        case .solid:
            let base = TimetableBackgroundRGB(hex: solidColorHex)
                ?? TimetableBackgroundStore.defaultSolidColor
            let palette = TimetableBackgroundPaletteExtractor.palette(baseColor: base)
            hexes = colorScheme == .dark ? palette.darkHexes : palette.lightHexes
        }
        return hexes.compactMap { TimetableBackgroundStore.color(hex: $0) }
    }

    private var settingsSignature: String {
        [
            backgroundIsEnabled.description,
            kindRaw,
            backgroundFilename,
            displayModeRaw,
            String(imageOpacity),
            String(blurRadius),
            String(overlayOpacity),
            String(courseCardOpacity),
            solidColorHex
        ].joined(separator: "|")
    }

    var body: some View {
        List {
            previewSection
            typeSection

            switch selectedKind {
            case .photo:
                photoSection
                if hasBackgroundImage {
                    photoDisplayModeSection
                }
            case .solid:
                solidColorSection
            }

            adjustmentSection
        }
        .leafyInsetGroupedListStyle()
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 760, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(LeafyPageBackground())
        .navigationTitle(L10n.text("课表背景", language: leafyLanguage))
        .leafyInlineNavigationTitle()
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task { await importBackground(from: newItem) }
        }
        .onChange(of: settingsSignature) { _, _ in
            TimetableBackgroundStore.notifySettingsDidChange()
        }
        .task(id: backgroundFilename) {
            if TimetableBackgroundKind(rawValue: kindRaw) == nil {
                kindRaw = TimetableBackgroundKind.photo.rawValue
            }
            await loadPreview(filename: backgroundFilename)
        }
        .leafyOperationAlert($operationAlert)
    }

    private var previewSection: some View {
        Section {
            TimetableBackgroundPreview(
                configuration: previewConfiguration,
                image: previewImage,
                palette: previewPalette,
                isImporting: isImporting
            )
            .padding(.vertical, 6)
        } footer: {
            Text(L10n.text("背景设置只保存在本机，只影响课表页；分享图和小组件会继续使用主题色。", language: leafyLanguage))
        }
        .listRowBackground(AppTheme.cardBackground)
    }

    private var typeSection: some View {
        Section(L10n.text("背景类型", language: leafyLanguage)) {
            Picker(L10n.text("背景类型", language: leafyLanguage), selection: kindBinding) {
                ForEach(TimetableBackgroundKind.allCases) { kind in
                    Text(kind.title(language: leafyLanguage)).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .listRowBackground(AppTheme.cardBackground)
    }

    private var photoSection: some View {
        Section(L10n.text("照片", language: leafyLanguage)) {
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                settingsRow(
                    icon: "photo.on.rectangle.angled",
                    title: isImporting ? "读取中" : (hasBackgroundImage ? "更换照片" : "选择照片"),
                    detail: "从照片中选择一张图片"
                )
            }
            .buttonStyle(.plain)
            .disabled(isImporting)

            Toggle(isOn: enabledBinding) {
                settingsRow(
                    icon: "rectangle.on.rectangle.angled",
                    title: "启用背景",
                    detail: hasBackgroundImage ? "在课表页显示这张照片" : "选择照片后可开启"
                )
            }
            .disabled(!hasBackgroundImage)
            .tint(AppTheme.accent)

            if previewLoadFailed {
                Label {
                    Text(L10n.text("照片文件不可用，请重新选择。", language: leafyLanguage))
                        .leafyBody()
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(AppTheme.danger)
            }

            if !backgroundFilename.isEmpty {
                Button(role: .destructive) {
                    removeBackground()
                } label: {
                    settingsRow(
                        icon: "trash.fill",
                        title: "移除照片",
                        detail: "删除本机保存的课表背景照片",
                        tint: AppTheme.danger
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .listRowBackground(AppTheme.cardBackground)
    }

    private var solidColorSection: some View {
        Section(L10n.text("纯色", language: leafyLanguage)) {
            ColorPicker(
                L10n.text("背景颜色", language: leafyLanguage),
                selection: solidColorBinding,
                supportsOpacity: false
            )

            Toggle(isOn: enabledBinding) {
                settingsRow(
                    icon: "rectangle.fill",
                    title: "启用背景",
                    detail: "在课表页显示这个颜色"
                )
            }
            .tint(AppTheme.accent)
        }
        .listRowBackground(AppTheme.cardBackground)
    }

    private var photoDisplayModeSection: some View {
        Section(L10n.text("显示方式", language: leafyLanguage)) {
            ForEach(TimetableBackgroundDisplayMode.allCases) { mode in
                Button {
                    displayModeRaw = mode.rawValue
                } label: {
                    HStack(spacing: 12) {
                        LeafyIconBadge(systemName: mode == .fill ? "rectangle.inset.filled" : "rectangle.center.inset.filled")
                        Text(mode.title(language: leafyLanguage))
                            .leafyBody()
                            .foregroundStyle(AppTheme.primaryText)
                        Spacer()
                        selectionIndicator(isSelected: mode == displayMode)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .listRowBackground(AppTheme.cardBackground)
    }

    private var adjustmentSection: some View {
        Section(L10n.text("调节", language: leafyLanguage)) {
            sliderRow(
                title: "背景可见度",
                valueText: percentageText(imageOpacity),
                value: $imageOpacity,
                range: 0.12...0.55
            )
            if selectedKind == .photo {
                sliderRow(
                    title: "模糊强度",
                    valueText: String(format: "%.0f", blurRadius),
                    value: $blurRadius,
                    range: 0...24
                )
            }
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

    private var solidColorBinding: Binding<Color> {
        Binding(
            get: {
                TimetableBackgroundStore.color(hex: solidColorHex)
                    ?? TimetableBackgroundStore.color(hex: TimetableBackgroundStore.defaultSolidColorHex)
                    ?? AppTheme.accentSoft
            },
            set: { newColor in
                if let hex = hexString(from: newColor) {
                    solidColorHex = hex
                }
            }
        )
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

    private func selectionIndicator(isSelected: Bool) -> some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.tertiaryText)
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
            kindRaw = TimetableBackgroundKind.photo.rawValue
            backgroundIsEnabled = true
            previewLoadFailed = false
            TimetableBackgroundStore.notifySettingsDidChange()
            operationAlert = .success(L10n.text("课表背景照片已保存。", language: leafyLanguage))
        } catch is CancellationError {
            return
        } catch {
            operationAlert = .failure(L10n.text("加载照片失败：%@", language: leafyLanguage, error.localizedDescription))
        }
    }

    @MainActor
    private func loadPreview(filename: String) async {
        guard !filename.isEmpty else {
            previewImage = nil
            previewLoadFailed = false
            if selectedKind == .photo {
                backgroundIsEnabled = false
            }
            return
        }
        let image = await TimetableBackgroundStore.image(filename: filename)
        guard !Task.isCancelled, filename == backgroundFilename else { return }
        previewImage = image
        previewLoadFailed = image == nil
        if selectedKind == .photo, image == nil {
            backgroundIsEnabled = false
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
            previewLoadFailed = false
            TimetableBackgroundStore.notifySettingsDidChange()
            operationAlert = .success(L10n.text("课表背景照片已移除。", language: leafyLanguage))
        } catch {
            operationAlert = .failure(L10n.text("移除照片失败：%@", language: leafyLanguage, error.localizedDescription))
        }
    }

    private func hexString(from color: Color) -> String? {
        #if canImport(UIKit)
        let platformColor = UIColor(color)
        #else
        let platformColor = NSColor(color)
        #endif
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard platformColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }
        return TimetableBackgroundRGB(red: red, green: green, blue: blue).hexString
    }
}

private struct TimetableBackgroundPreview: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let configuration: TimetableBackgroundConfiguration
    let image: UIImage?
    let palette: [Color]
    let isImporting: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .fill(AppTheme.fill)

            if configuration.kind == .photo, image == nil {
                placeholder
            } else {
                TimetableBackgroundLayer(configuration: configuration, image: image)
                sampleCards
            }
        }
        .frame(height: 184)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .stroke(AppTheme.separator, lineWidth: 1)
        )
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            if isImporting {
                ProgressView()
            } else {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(AppTheme.accentEmphasis)
            }
            Text(isImporting ? L10n.text("正在读取照片", language: leafyLanguage) : L10n.text("尚未选择照片", language: leafyLanguage))
                .leafyBody()
                .foregroundStyle(AppTheme.secondaryText)
        }
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
                .background(sampleColor(at: index).opacity(configuration.courseCardOpacity))
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
