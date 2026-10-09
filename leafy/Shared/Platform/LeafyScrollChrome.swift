import SwiftUI
import UIKit

nonisolated struct LeafyVerticalScrollSample: Equatable {
    let offset: CGFloat
    let maximumOffset: CGFloat
    let isUserDriven: Bool
}

nonisolated struct LeafyScrollHeaderState {
    private(set) var isVisible = true
    private var previousOffset: CGFloat?
    private var previousMaximum: CGFloat?
    private var travel: CGFloat = 0

    mutating func reset() { self = Self() }

    mutating func update(_ sample: LeafyVerticalScrollSample) {
        guard sample.offset.isFinite, sample.maximumOffset.isFinite else { return }
        guard sample.maximumOffset > 1 else { reset(); return }
        let offset = min(max(sample.offset, 0), sample.maximumOffset)
        defer { previousOffset = offset; previousMaximum = sample.maximumOffset }
        if sample.offset <= 1 {
            isVisible = true
            travel = 0
            return
        }
        if let previousMaximum, abs(previousMaximum - sample.maximumOffset) > 1 {
            travel = 0
            return
        }
        guard sample.offset <= sample.maximumOffset + 1, sample.isUserDriven,
              let previousOffset else { travel = 0; return }
        let delta = offset - previousOffset
        guard abs(delta) > 0.1 else { return }
        if delta * travel < 0 { travel = delta } else { travel += delta }
        if travel >= 12 {
            isVisible = false
            travel = 0
        } else if travel <= -12 {
            isVisible = true
            travel = 0
        }
    }
}

private struct LeafyCampusPaneKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var leafyCampusPane: Bool {
        get { self[LeafyCampusPaneKey.self] }
        set { self[LeafyCampusPaneKey.self] = newValue }
    }
}

extension View {
    func leafyCampusScrollEdges() -> some View { modifier(LeafyCampusScrollEdgesModifier()) }

    func leafyScrollHeader(visible: Bool) -> some View {
        modifier(LeafyScrollHeaderModifier(visible: visible))
    }

    func leafyVerticalScrollObserver(
        enabled: Bool = true,
        logicalTopOffset: CGFloat = 0,
        onChange: ((LeafyVerticalScrollSample) -> Void)?
    ) -> some View {
        modifier(LeafyVerticalScrollObserverModifier(
            enabled: enabled, logicalTopOffset: logicalTopOffset, onChange: onChange
        ))
    }
}

private struct LeafyScrollHeaderModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let visible: Bool
    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : -8)
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: visible)
    }
}

struct LeafyNavigationBackgroundModifier: ViewModifier {
    @Environment(\.leafyCampusPane) private var campusPane
    @ViewBuilder func body(content: Content) -> some View {
        if campusPane {
            content.toolbarBackground(.hidden, for: .navigationBar)
        } else if #available(iOS 26.0, *) {
            content.toolbarBackground(.hidden, for: .navigationBar)
        } else {
            content.toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

private struct LeafyCampusScrollEdgesModifier: ViewModifier {
    @Environment(\.leafyCampusPane) private var campusPane
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *), campusPane {
            content.scrollEdgeEffectHidden(true, for: [.top, .bottom])
        } else {
            content
        }
    }
}

private struct LeafyVerticalScrollObserverModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    let enabled: Bool
    let logicalTopOffset: CGFloat
    let onChange: ((LeafyVerticalScrollSample) -> Void)?

    @ViewBuilder func body(content: Content) -> some View {
        if let onChange {
            if #available(iOS 18.0, *) {
                content.modifier(LeafyNativeVerticalScrollObserver(
                    enabled: enabled && isEnabled, logicalTopOffset: logicalTopOffset, onChange: onChange
                ))
            } else {
                content.background(LeafyLegacyVerticalScrollObserver(
                    enabled: enabled && isEnabled, logicalTopOffset: logicalTopOffset, onChange: onChange
                ).allowsHitTesting(false))
            }
        } else {
            content
        }
    }
}

@available(iOS 18.0, *)
private struct LeafyNativeVerticalScrollObserver: ViewModifier {
    @State private var userDriven = false
    let enabled: Bool
    let logicalTopOffset: CGFloat
    let onChange: (LeafyVerticalScrollSample) -> Void

    func body(content: Content) -> some View {
        content
            .onScrollPhaseChange { _, phase in
                userDriven = phase == .tracking || phase == .interacting || phase == .decelerating
            }
            .onScrollGeometryChange(for: LeafyVerticalScrollSample.self) { geometry in
                LeafyVerticalScrollSample(
                    offset: geometry.contentOffset.y + geometry.contentInsets.top - logicalTopOffset,
                    maximumOffset: max(0, geometry.contentSize.height + geometry.contentInsets.top
                        + geometry.contentInsets.bottom - geometry.containerSize.height - logicalTopOffset),
                    isUserDriven: userDriven
                )
            } action: { _, sample in
                if enabled { onChange(sample) }
            }
    }
}

/// Observe the owning scroll container only; never replace UIKit's delegate.
private struct LeafyLegacyVerticalScrollObserver: UIViewRepresentable {
    let enabled: Bool
    let logicalTopOffset: CGFloat
    let onChange: (LeafyVerticalScrollSample) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> Marker {
        let view = Marker()
        view.isUserInteractionEnabled = false
        view.onAttach = { [weak coordinator = context.coordinator] marker in coordinator?.attach(marker) }
        return view
    }
    func updateUIView(_ view: Marker, context: Context) {
        context.coordinator.enabled = enabled
        context.coordinator.logicalTopOffset = logicalTopOffset
        context.coordinator.onChange = onChange
        context.coordinator.attach(view)
    }
    static func dismantleUIView(_ view: Marker, coordinator: Coordinator) {
        view.onAttach = nil
        coordinator.observation = nil
    }

    final class Marker: UIView {
        var onAttach: ((Marker) -> Void)?
        override func didMoveToWindow() { super.didMoveToWindow(); onAttach?(self) }
        override func layoutSubviews() { super.layoutSubviews(); onAttach?(self) }
    }

    final class Coordinator {
        var enabled = false
        var logicalTopOffset: CGFloat = 0
        var onChange: ((LeafyVerticalScrollSample) -> Void)?
        var observation: NSKeyValueObservation?
        private weak var scrollView: UIScrollView?

        func attach(_ marker: Marker) {
            guard marker.window != nil else { observation = nil; scrollView = nil; return }
            if scrollView != nil, observation != nil { return }
            var ancestor = marker.superview
            // The background marker sits next to the hosting scroll view. Stop before the window.
            for _ in 0..<5 {
                guard let view = ancestor, !(view is UIWindow) else { break }
                if let found = (view as? UIScrollView) ?? findScrollView(in: view, excluding: marker, depth: 3) {
                    scrollView = found
                    observation = found.observe(\.contentOffset, options: [.initial, .new]) { [weak self] view, _ in
                        MainActor.assumeIsolated { self?.emit(view) }
                    }
                    return
                }
                ancestor = view.superview
            }
        }

        private func findScrollView(in view: UIView, excluding marker: UIView, depth: Int) -> UIScrollView? {
            guard depth > 0 else { return nil }
            for child in view.subviews where child !== marker {
                if let scroll = child as? UIScrollView {
                    let markerRect = marker.convert(marker.bounds, to: scroll)
                    let overlap = scroll.bounds.intersection(markerRect)
                    let markerArea = markerRect.width * markerRect.height
                    if !scroll.isHidden, scroll.alpha > 0.01, markerArea > 1,
                       overlap.width * overlap.height >= markerArea * 0.8 { return scroll }
                }
                if let scroll = findScrollView(in: child, excluding: marker, depth: depth - 1) { return scroll }
            }
            return nil
        }

        private func emit(_ view: UIScrollView) {
            guard enabled else { return }
            let sample = LeafyVerticalScrollSample(
                offset: view.contentOffset.y + view.adjustedContentInset.top - logicalTopOffset,
                maximumOffset: max(0, view.contentSize.height + view.adjustedContentInset.top
                    + view.adjustedContentInset.bottom - view.bounds.height - logicalTopOffset),
                isUserDriven: view.isTracking || view.isDragging || view.isDecelerating
            )
            DispatchQueue.main.async { [weak self] in
                guard let self, self.enabled else { return }
                self.onChange?(sample)
            }
        }
    }
}
