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
    @AppStorage(TimetableBackgroundStore.photoFilterKey) private var photoFilterRaw = TimetablePhotoFilter.none.rawValue
    @AppStorage(TimetableBackgroundStore.shaderEffectKey) private var shaderEffectRaw = TimetableShaderEffect.staticMeshGradient.rawValue
    @AppStorage(TimetableBackgroundStore.shaderPaletteKey) private var shaderPaletteRaw = TimetableShaderPalette.forest.rawValue

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var isImporting = false
    @State private var previewLoadFailed = false
    @State private var operationAlert: LeafyOperationAlert?

    private let gridColumns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    private var selectedKind: TimetableBackgroundKind {
        guard backgroundIsEnabled else { return .off }
        return TimetableBackgroundKind(rawValue: kindRaw)
            ?? (backgroundFilename.isEmpty ? .off : .photo)
    }

    private var kindBinding: Binding<TimetableBackgroundKind> {
        Binding(
            get: { selectedKind },
            set: { newValue in
                if newValue == .off {
                    backgroundIsEnabled = false
                } else {
                    kindRaw = newValue.rawValue
                    backgroundIsEnabled = true
                }
            }
        )
    }

    private var displayMode: TimetableBackgroundDisplayMode {
        TimetableBackgroundDisplayMode(rawValue: displayModeRaw) ?? .fill
    }

    private var photoFilter: TimetablePhotoFilter {
        TimetablePhotoFilter(rawValue: photoFilterRaw) ?? .none
    }

    private var shaderEffect: TimetableShaderEffect {
        TimetableShaderEffect(rawValue: shaderEffectRaw) ?? .staticMeshGradient
    }

    private var shaderPalette: TimetableShaderPalette {
        TimetableShaderPalette(rawValue: shaderPaletteRaw) ?? .forest
    }

    private var hasBackgroundImage: Bool {
        !backgroundFilename.isEmpty && previewImage != nil
    }

    private var previewConfiguration: TimetableBackgroundConfiguration {
        TimetableBackgroundConfiguration(
            kind: selectedKind,
            filename: backgroundFilename,
            displayMode: displayMode,
            imageOpacity: imageOpacity,
            blurRadius: blurRadius * 0.36,
            overlayOpacity: overlayOpacity,
            courseCardOpacity: courseCardOpacity,
            lightPaletteHexes: lightPaletteHexes,
            darkPaletteHexes: darkPaletteHexes,
            solidColorHex: solidColorHex,
            photoFilter: photoFilter,
            shaderEffect: shaderEffect,
            shaderPalette: shaderPalette
        )
    }

    @MainActor
    private var previewPalette: [Color] {
        previewConfiguration.coursePalette(colorScheme: colorScheme)
            ?? TimetableBackgroundPalette.fallbackLightHexes.compactMap(TimetableBackgroundStore.color(hex:))
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
            solidColorHex,
            photoFilterRaw,
            shaderEffectRaw,
            shaderPaletteRaw
        ].joined(separator: "|")
    }

    var body: some View {
        List {
            previewSection
            sourceSection

            if previewConfiguration.requiresMetalEffects, !TimetableShaderAvailability.isAvailable {
                Section {
                    Label {
                        Text(L10n.text("当前设备无法使用 Metal 视觉效果。课表会显示默认背景，请选择原图、纯色或稍后重试。", language: leafyLanguage))
                            .leafyBody()
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(AppTheme.danger)
                }
                .listRowBackground(AppTheme.cardBackground)
            }

            switch selectedKind {
            case .off:
                Section {
                    ContentUnavailableView(
                        L10n.text("课表背景已关闭", language: leafyLanguage),
                        systemImage: "rectangle.slash"
                    )
                }
                .listRowBackground(AppTheme.cardBackground)
            case .photo:
                photoSection
                if hasBackgroundImage {
                    photoFilterSection
                    photoDisplayModeSection
                }
            case .solid:
                solidColorSection
            case .effect:
                shaderEffectSection
                shaderPaletteSection
            }

            if selectedKind != .off {
                adjustmentSection
            }
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
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.text("背景设置只保存在本机，只影响课表页；分享图和小组件会继续使用主题色。", language: leafyLanguage))
                Link(
                    L10n.text("效果基于 Paper Shaders", language: leafyLanguage),
                    destination: URL(string: "https://shaders.paper.design")!
                )
            }
        }
        .listRowBackground(AppTheme.cardBackground)
    }

    private var sourceSection: some View {
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

    private var photoFilterSection: some View {
        Section(L10n.text("照片滤镜", language: leafyLanguage)) {
            LazyVGrid(columns: gridColumns, spacing: 10) {
                ForEach(TimetablePhotoFilter.allCases) { filter in
                    Button {
                        photoFilterRaw = filter.rawValue
                    } label: {
                        TimetablePhotoFilterOption(
                            filter: filter,
                            image: previewImage,
                            configuration: previewConfiguration,
                            isSelected: photoFilter == filter,
                            language: leafyLanguage
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
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

    private var solidColorSection: some View {
        Section(L10n.text("纯色", language: leafyLanguage)) {
            ColorPicker(
                L10n.text("背景颜色", language: leafyLanguage),
                selection: solidColorBinding,
                supportsOpacity: false
            )
        }
        .listRowBackground(AppTheme.cardBackground)
    }

    private var shaderEffectSection: some View {
        Section(L10n.text("视觉效果", language: leafyLanguage)) {
            LazyVGrid(columns: gridColumns, spacing: 10) {
                ForEach(TimetableShaderEffect.allCases) { effect in
                    Button {
                        shaderEffectRaw = effect.rawValue
                    } label: {
                        TimetableShaderEffectOption(
                            effect: effect,
                            palette: shaderPalette,
                            isSelected: shaderEffect == effect,
                            language: leafyLanguage
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(AppTheme.cardBackground)
    }

    private var shaderPaletteSection: some View {
        Section(L10n.text("预设配色", language: leafyLanguage)) {
            ForEach(TimetableShaderPalette.allCases) { palette in
                Button {
                    shaderPaletteRaw = palette.rawValue
                } label: {
                    HStack(spacing: 12) {
                        HStack(spacing: -5) {
                            ForEach(Array(palette.shaderHexes(colorScheme: colorScheme).prefix(4).enumerated()), id: \.offset) { _, hex in
                                Circle()
                                    .fill(TimetableBackgroundStore.color(hex: hex) ?? AppTheme.accentSoft)
                                    .frame(width: 24, height: 24)
                                    .overlay(Circle().stroke(AppTheme.cardBackground, lineWidth: 2))
                            }
                        }
                        Text(palette.title(language: leafyLanguage))
                            .leafyBody()
                            .foregroundStyle(AppTheme.primaryText)
                        Spacer()
                        selectionIndicator(isSelected: shaderPalette == palette)
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
            return
        }
        let image = await TimetableBackgroundStore.image(filename: filename)
        guard !Task.isCancelled, filename == backgroundFilename else { return }
        previewImage = image
        previewLoadFailed = image == nil
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
            } else if configuration.kind == .off {
                disabledPlaceholder
            } else {
                TimetableBackgroundLayer(
                    configuration: configuration,
                    image: image,
                    allowsAnimation: true
                )
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

    private var disabledPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.slash")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(AppTheme.tertiaryText)
            Text(L10n.text("课表背景已关闭", language: leafyLanguage))
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

private struct TimetablePhotoFilterOption: View {
    let filter: TimetablePhotoFilter
    let image: UIImage?
    let configuration: TimetableBackgroundConfiguration
    let isSelected: Bool
    let language: AppLanguagePreference

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                AppTheme.fill
                if let image {
                    TimetableBackgroundLayer(
                        configuration: TimetableBackgroundConfiguration(
                            kind: .photo,
                            filename: configuration.filename,
                            displayMode: .fill,
                            imageOpacity: 0.75,
                            blurRadius: 0,
                            overlayOpacity: 0.06,
                            courseCardOpacity: configuration.courseCardOpacity,
                            lightPaletteHexes: configuration.lightPaletteHexes,
                            darkPaletteHexes: configuration.darkPaletteHexes,
                            solidColorHex: configuration.solidColorHex,
                            photoFilter: filter,
                            shaderEffect: configuration.shaderEffect,
                            shaderPalette: configuration.shaderPalette
                        ),
                        image: image,
                        allowsAnimation: false
                    )
                }
            }
            .frame(height: 64)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

            Text(filter.title(language: language))
                .microCaption()
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
        }
        .padding(6)
        .background(isSelected ? AppTheme.accentSoft : AppTheme.fill)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .stroke(isSelected ? AppTheme.accent : AppTheme.separator, lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
    }
}

private struct TimetableShaderEffectOption: View {
    let effect: TimetableShaderEffect
    let palette: TimetableShaderPalette
    let isSelected: Bool
    let language: AppLanguagePreference

    var body: some View {
        VStack(spacing: 6) {
            TimetableShaderEffectView(effect: effect, palette: palette, allowsAnimation: false)
                .frame(height: 64)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

            Text(effect.title(language: language))
                .microCaption()
                .foregroundStyle(AppTheme.primaryText)
        }
        .padding(6)
        .background(isSelected ? AppTheme.accentSoft : AppTheme.fill)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .stroke(isSelected ? AppTheme.accent : AppTheme.separator, lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
    }
}
