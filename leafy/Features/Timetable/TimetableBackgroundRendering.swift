import Foundation
import SwiftUI
#if canImport(Metal)
import Metal
#endif
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct TimetableBackgroundLayer: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let configuration: TimetableBackgroundConfiguration
    let image: UIImage?
    var allowsAnimation = true

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                backgroundSource(size: proxy.size)

                maskColor
                    .opacity(configuration.overlayOpacity)

                AppTheme.pageGradient(for: themeColorPreference)
                    .opacity(colorScheme == .dark ? 0.18 : 0.28)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func backgroundSource(size: CGSize) -> some View {
        if configuration.requiresMetalEffects && !TimetableShaderAvailability.isAvailable {
            Color.clear
        } else {
            switch configuration.kind {
            case .off:
                Color.clear
            case .photo:
                if let image {
                    TimetableFilteredPhotoView(
                        image: image,
                        configuration: configuration,
                        allowsAnimation: allowsAnimation
                    )
                    .frame(width: size.width, height: size.height)
                    .blur(radius: configuration.blurRadius)
                    .opacity(configuration.imageOpacity)
                } else {
                    Color.clear
                }
            case .solid:
                (TimetableBackgroundStore.color(hex: configuration.solidColorHex) ?? AppTheme.accentSoft)
                    .opacity(configuration.imageOpacity)
            case .effect:
                TimetableShaderEffectView(
                    effect: configuration.shaderEffect,
                    palette: configuration.shaderPalette,
                    allowsAnimation: allowsAnimation
                )
                .opacity(configuration.imageOpacity)
            }
        }
    }

    private var maskColor: Color {
        colorScheme == .dark ? .black : AppTheme.background
    }
}

enum TimetableShaderAvailability {
    static let isAvailable: Bool = {
        #if canImport(Metal)
        MTLCreateSystemDefaultDevice() != nil
        #else
        false
        #endif
    }()
}

struct TimetableShaderEffectView: View {
    @Environment(\.colorScheme) private var colorScheme

    let effect: TimetableShaderEffect
    let palette: TimetableShaderPalette
    var allowsAnimation = true

    var body: some View {
        let colors = resolvedColors
        switch effect {
        case .staticMeshGradient:
            Rectangle()
                .fill(
                    ShaderLibrary.leafyStaticMeshGradient(
                        .boundingRect,
                        .color(colors[0]),
                        .color(colors[1]),
                        .color(colors[2]),
                        .color(colors[3])
                    )
                )
        case .waves:
            Rectangle()
                .fill(
                    ShaderLibrary.leafyWaves(
                        .boundingRect,
                        .color(colors[0]),
                        .color(colors[2])
                    )
                )
        case .meshGradient:
            if allowsAnimation {
                TimetableShaderTimeline(allowsAnimation: true, fixedTime: 9.0) { time in
                    meshGradient(colors: colors, time: time)
                }
            } else {
                meshGradient(colors: colors, time: 9.0)
            }
        }
    }

    private func meshGradient(colors: [Color], time: TimeInterval) -> some View {
        Rectangle()
            .fill(
                ShaderLibrary.leafyMeshGradient(
                    .boundingRect,
                    .float(time),
                    .color(colors[0]),
                    .color(colors[1]),
                    .color(colors[2]),
                    .color(colors[3])
                )
            )
    }

    @MainActor
    private var resolvedColors: [Color] {
        let colors = palette.shaderHexes(colorScheme: colorScheme)
            .compactMap(TimetableBackgroundStore.color(hex:))
        if colors.count == 4 {
            return colors
        }
        return [.green, .mint, .teal, .yellow]
    }
}

private struct TimetableFilteredPhotoView: View {
    @Environment(\.colorScheme) private var colorScheme

    let image: UIImage
    let configuration: TimetableBackgroundConfiguration
    let allowsAnimation: Bool

    var body: some View {
        switch configuration.photoFilter {
        case .water:
            if allowsAnimation {
                TimetableShaderTimeline(allowsAnimation: true, fixedTime: 4.0) { time in
                    filteredImage(time: time)
                }
            } else {
                filteredImage(time: 4.0)
            }
        default:
            filteredImage(time: 4.0)
        }
    }

    @ViewBuilder
    private func filteredImage(time: TimeInterval) -> some View {
        let imageView = Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: configuration.displayMode.contentMode)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

        switch configuration.photoFilter {
        case .none:
            imageView
        case .paperTexture:
            imageView.layerEffect(
                ShaderLibrary.leafyPaperTexture(.boundingRect),
                maxSampleOffset: .zero
            )
        case .flutedGlass:
            imageView.layerEffect(
                ShaderLibrary.leafyFlutedGlass(.boundingRect),
                maxSampleOffset: CGSize(width: 22, height: 22)
            )
        case .water:
            imageView.layerEffect(
                ShaderLibrary.leafyWater(
                    .boundingRect,
                    .float(time)
                ),
                maxSampleOffset: CGSize(width: 18, height: 18)
            )
        case .imageDithering:
            imageView.layerEffect(
                ShaderLibrary.leafyImageDithering(
                    .boundingRect,
                    .color(filterColors.background),
                    .color(filterColors.foreground),
                    .color(filterColors.highlight)
                ),
                maxSampleOffset: CGSize(width: 8, height: 8)
            )
        case .halftoneDots:
            imageView.layerEffect(
                ShaderLibrary.leafyHalftoneDots(
                    .boundingRect,
                    .color(filterColors.background),
                    .color(filterColors.foreground)
                ),
                maxSampleOffset: CGSize(width: 12, height: 12)
            )
        case .halftoneCMYK:
            imageView.layerEffect(
                ShaderLibrary.leafyHalftoneCMYK(.boundingRect),
                maxSampleOffset: CGSize(width: 8, height: 8)
            )
        }
    }

    private var filterColors: (background: Color, foreground: Color, highlight: Color) {
        let palette = configuration.coursePalette(colorScheme: colorScheme) ?? []
        let background = colorScheme == .dark ? Color.black : AppTheme.background
        let foreground = palette.first ?? AppTheme.accent
        let highlight = palette.dropFirst().first ?? AppTheme.accentSoft
        return (background, foreground, highlight)
    }
}

private struct TimetableShaderTimeline<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var systemStateRevision = 0

    let allowsAnimation: Bool
    let fixedTime: TimeInterval
    @ViewBuilder let content: (TimeInterval) -> Content

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: isPaused)) { context in
            content(
                isPaused
                    ? fixedTime
                    : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000)
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            systemStateRevision &+= 1
        }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            systemStateRevision &+= 1
        }
    }

    private var isPaused: Bool {
        _ = systemStateRevision
        let processInfo = ProcessInfo.processInfo
        let isThermallyConstrained = processInfo.thermalState == .serious || processInfo.thermalState == .critical
        return !allowsAnimation
            || accessibilityReduceMotion
            || scenePhase != .active
            || processInfo.isLowPowerModeEnabled
            || isThermallyConstrained
    }
}
