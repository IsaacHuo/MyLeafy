import Observation
import QuartzCore
import SwiftUI
import UIKit

nonisolated enum TimetableContinuousInteractionPhase: Equatable, Sendable {
    case idle
    case pinching
    case settling
    case paging
}

nonisolated struct TimetableZoomPreparedDay: Identifiable, Equatable, Sendable {
    let date: Date
    let ordinal: Int
    let academicWeek: Int?
    let dayOfWeek: Int

    var id: Date { date }
}

nonisolated struct TimetableZoomRenderWindow: Equatable, Sendable {
    static let dayCount = 21
    static let middleWeekStartOrdinal = 7

    let startDate: Date
    let days: [TimetableZoomPreparedDay]

    static func make(
        weekStartDate: Date,
        academicYear: AcademicYearTimetable,
        calendar: Calendar = .current
    ) -> TimetableZoomRenderWindow {
        let normalizedWeekStart = calendar.startOfDay(for: weekStartDate)
        let startDate = calendar.date(byAdding: .day, value: -7, to: normalizedWeekStart)
            ?? normalizedWeekStart
        let days = (0..<dayCount).compactMap { ordinal -> TimetableZoomPreparedDay? in
            guard let date = calendar.date(byAdding: .day, value: ordinal, to: startDate) else {
                return nil
            }
            let normalizedDate = calendar.startOfDay(for: date)
            let weekday = calendar.component(.weekday, from: normalizedDate)
            return TimetableZoomPreparedDay(
                date: normalizedDate,
                ordinal: ordinal,
                academicWeek: academicYear.pageIndex(containing: normalizedDate),
                dayOfWeek: ((weekday + 5) % 7) + 1
            )
        }
        return TimetableZoomRenderWindow(startDate: startDate, days: days)
    }
}

nonisolated struct TimetableZoomGeometry: Equatable, Sendable {
    var progress: CGFloat
    var horizontalOffset: CGFloat
    let viewportWidth: CGFloat
    let anchorOrdinal: Int
    let hidesWeekends: Bool
    let gutter: CGFloat

    private var resolvedProgress: CGFloat {
        min(max(progress, 0), 1)
    }

    func laneWidth(dayOfWeek: Int) -> CGFloat {
        let weekWidth = hidesWeekends
            ? ((1...5).contains(dayOfWeek) ? viewportWidth / 5 : 0)
            : viewportWidth / 7
        return weekWidth + (viewportWidth / 3 - weekWidth) * resolvedProgress
    }

    func laneLeading(ordinal: Int) -> CGFloat {
        guard ordinal > 0 else { return 0 }
        return (0..<ordinal).reduce(CGFloat.zero) { partial, candidate in
            partial + laneWidth(dayOfWeek: (candidate % 7) + 1)
        }
    }

    func laneFrame(ordinal: Int, dayOfWeek: Int) -> CGRect {
        let width = laneWidth(dayOfWeek: dayOfWeek)
        let leading = laneLeading(ordinal: ordinal) + contentTranslation
        let visibleWidth = max(width - min(gutter, width), 0.5)
        return CGRect(
            x: leading + (width - visibleWidth) * 0.5,
            y: 0,
            width: visibleWidth,
            height: 0
        )
    }

    var contentTranslation: CGFloat {
        let middleWeekLeading = laneLeading(ordinal: TimetableZoomRenderWindow.middleWeekStartOrdinal)
        let anchorDay = (anchorOrdinal % 7 + 7) % 7 + 1
        let anchorCenter = laneLeading(ordinal: anchorOrdinal) + laneWidth(dayOfWeek: anchorDay) * 0.5
        let weekAligned = -middleWeekLeading
        let anchorCentered = viewportWidth * 0.5 - anchorCenter
        return weekAligned
            + (anchorCentered - weekAligned) * resolvedProgress
            + horizontalOffset
    }

    func currentTimeIndicatorXRange(todayOrdinal: Int?) -> ClosedRange<CGFloat>? {
        guard let todayOrdinal else { return nil }

        let dayOfWeekIndex = (todayOrdinal % 7 + 7) % 7
        let weekStartOrdinal = todayOrdinal - dayOfWeekIndex
        let weekStartX = laneLeading(ordinal: weekStartOrdinal)
        let weekEndX = laneLeading(ordinal: weekStartOrdinal + 7)
        let threeDayStartX = laneLeading(ordinal: todayOrdinal - 1)
        let threeDayEndX = laneLeading(ordinal: todayOrdinal + 2)
        let startX = weekStartX
            + (threeDayStartX - weekStartX) * resolvedProgress
            + contentTranslation
        let endX = weekEndX
            + (threeDayEndX - weekEndX) * resolvedProgress
            + contentTranslation
        let clippedStart = max(0, min(startX, viewportWidth))
        let clippedEnd = max(0, min(endX, viewportWidth))
        guard clippedEnd > clippedStart else { return nil }
        return clippedStart...clippedEnd
    }
}

nonisolated struct TimetableContinuousColumnsLayout: Layout {
    var geometry: TimetableZoomGeometry

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(geometry.progress, geometry.horizontalOffset) }
        set {
            geometry.progress = newValue.first
            geometry.horizontalOffset = newValue.second
        }
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let height = proposal.height
            ?? subviews.map { $0.sizeThatFits(.unspecified).height }.max()
            ?? 0
        return CGSize(width: geometry.viewportWidth, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        for (ordinal, subview) in subviews.enumerated() {
            let dayOfWeek = (ordinal % 7) + 1
            let frame = geometry.laneFrame(ordinal: ordinal, dayOfWeek: dayOfWeek)
            subview.place(
                at: CGPoint(x: bounds.minX + frame.midX, y: bounds.minY),
                anchor: .top,
                proposal: ProposedViewSize(width: frame.width, height: bounds.height)
            )
        }
    }
}

struct TimetableContinuousVisualState {
    let geometry: TimetableZoomGeometry
    let centerDate: Date
    let isInteractionActive: Bool
}

struct TimetableContinuousViewportReader<Content: View>: View {
    let controller: TimetableContinuousViewportController
    let viewportWidth: CGFloat
    let hidesWeekends: Bool
    let gutter: CGFloat
    @ViewBuilder let content: (TimetableContinuousVisualState) -> Content

    var body: some View {
        let geometry = TimetableZoomGeometry(
            progress: controller.zoomProgress,
            horizontalOffset: controller.horizontalOffset,
            viewportWidth: viewportWidth,
            anchorOrdinal: min(max(controller.anchorOrdinal, 0), TimetableZoomRenderWindow.dayCount - 1),
            hidesWeekends: hidesWeekends,
            gutter: gutter
        )
        content(
            TimetableContinuousVisualState(
                geometry: geometry,
                centerDate: controller.centerDate,
                isInteractionActive: controller.isInteractionActive
            )
        )
    }
}

struct TimetableContinuousCenterDateReader<Content: View>: View {
    let controller: TimetableContinuousViewportController
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        content(controller.centerDate)
    }
}

@MainActor
@Observable
final class TimetableContinuousViewportController {
    private static let fullMagnification: CGFloat = 1.8
    private static let projectionHorizon: CGFloat = 0.16
    private static let spring = Spring(response: 0.34, dampingRatio: 0.92)

    private(set) var zoomProgress: CGFloat
    private(set) var horizontalOffset: CGFloat = 0
    private(set) var phase: TimetableContinuousInteractionPhase = .idle
    private(set) var centerDate: Date
    private(set) var weekStartDate: Date
    private(set) var windowRevision = 0

    #if DEBUG
    @ObservationIgnored private(set) var gestureUpdateCount = 0
    #endif

    var verticalOffset: CGFloat = 0

    @ObservationIgnored private var rangeStart: Date
    @ObservationIgnored private var rangeEnd: Date
    @ObservationIgnored private var gestureStartProgress: CGFloat = 0
    @ObservationIgnored private var animatedValue: Double = 0
    @ObservationIgnored private var animatedVelocity: Double = 0
    @ObservationIgnored private var animationTarget: Double = 0
    @ObservationIgnored private var animationKind = AnimationKind.none
    @ObservationIgnored private var lastFrameTimestamp: CFTimeInterval?
    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private lazy var displayLinkTarget = TimetableDisplayLinkTarget(owner: self)
    @ObservationIgnored private var calendar: Calendar
    private let boundaryFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)

    private enum AnimationKind: Equatable {
        case none
        case zoom
        case page(Int)
    }

    init(
        weekStartDate: Date,
        centerDate: Date,
        rangeStart: Date,
        rangeEnd: Date,
        zoomProgress: CGFloat = 0,
        calendar: Calendar = .current
    ) {
        self.calendar = calendar
        self.weekStartDate = calendar.startOfDay(for: weekStartDate)
        self.centerDate = calendar.startOfDay(for: centerDate)
        self.rangeStart = calendar.startOfDay(for: rangeStart)
        self.rangeEnd = calendar.startOfDay(for: rangeEnd)
        self.zoomProgress = min(max(zoomProgress, 0), 1)
    }

    var isThreeDay: Bool {
        zoomProgress >= 0.999
    }

    var isInteractionActive: Bool {
        phase != .idle
    }

    var anchorOrdinal: Int {
        let windowStart = calendar.date(byAdding: .day, value: -7, to: weekStartDate)
            ?? weekStartDate
        return calendar.dateComponents([.day], from: windowStart, to: centerDate).day
            ?? TimetableZoomRenderWindow.middleWeekStartOrdinal + 1
    }

    var threeDayDates: [Date] {
        (-1...1).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: centerDate)
                .map { calendar.startOfDay(for: $0) }
        }
    }

    func updateBounds(rangeStart: Date, rangeEnd: Date) {
        self.rangeStart = calendar.startOfDay(for: rangeStart)
        self.rangeEnd = calendar.startOfDay(for: rangeEnd)
        centerDate = clampedCenterDate(centerDate)
        weekStartDate = Self.monday(containing: centerDate, calendar: calendar)
        windowRevision += 1
    }

    func positionOnWeek(_ weekStartDate: Date, centersToday: Bool, today: Date = Date()) {
        stopAnimation()
        let normalizedWeekStart = calendar.startOfDay(for: weekStartDate)
        self.weekStartDate = normalizedWeekStart
        if centersToday {
            centerDate = calendar.startOfDay(for: today)
        } else {
            centerDate = calendar.date(byAdding: .day, value: 1, to: normalizedWeekStart)
                ?? normalizedWeekStart
        }
        horizontalOffset = 0
        windowRevision += 1
    }

    func beginMagnification(centersToday: Bool, today: Date = Date()) {
        guard phase != .paging else { return }
        stopAnimation()
        if zoomProgress <= 0.001 {
            if centersToday {
                centerDate = calendar.startOfDay(for: today)
            } else {
                centerDate = calendar.date(byAdding: .day, value: 1, to: weekStartDate)
                    ?? weekStartDate
            }
        } else {
            weekStartDate = Self.monday(containing: centerDate, calendar: calendar)
        }
        gestureStartProgress = zoomProgress
        phase = .pinching
        boundaryFeedbackGenerator.prepare()
    }

    func updateMagnification(_ magnification: CGFloat) {
        guard phase == .pinching else { return }
        #if DEBUG
        gestureUpdateCount += 1
        #endif
        let safeMagnification = max(magnification, 0.001)
        let delta = log(safeMagnification) / log(Self.fullMagnification)
        let previousProgress = zoomProgress
        zoomProgress = min(max(gestureStartProgress + delta, 0), 1)
        playBoundaryHapticIfNeeded(from: previousProgress, to: zoomProgress)
    }

    func endMagnification(
        magnification: CGFloat,
        velocity: CGFloat,
        reducesMotion: Bool
    ) {
        guard phase == .pinching else { return }
        let safeMagnification = max(magnification, 0.001)
        let rawProgressVelocity = velocity / (safeMagnification * log(Self.fullMagnification))
        let progressVelocity = min(max(rawProgressVelocity, -4), 4)
        let projected = zoomProgress + progressVelocity * Self.projectionHorizon
        let target: CGFloat = projected >= 0.5 ? 1 : 0
        if target == 0 {
            weekStartDate = Self.monday(containing: centerDate, calendar: calendar)
        }
        guard !reducesMotion else {
            zoomProgress = target
            phase = .idle
            return
        }
        boundaryFeedbackGenerator.prepare()
        startAnimation(
            kind: .zoom,
            value: Double(zoomProgress),
            velocity: Double(progressVelocity),
            target: Double(target)
        )
    }

    func setZoomTarget(_ target: CGFloat, centersToday: Bool, reducesMotion: Bool) {
        beginMagnification(centersToday: centersToday)
        let resolvedTarget: CGFloat = target >= 0.5 ? 1 : 0
        if resolvedTarget == 0 {
            weekStartDate = Self.monday(containing: centerDate, calendar: calendar)
        }
        guard !reducesMotion else {
            zoomProgress = resolvedTarget
            phase = .idle
            return
        }
        startAnimation(
            kind: .zoom,
            value: Double(zoomProgress),
            velocity: 0,
            target: Double(resolvedTarget)
        )
    }

    func beginPaging() {
        guard phase == .idle, zoomProgress <= 0.001 || zoomProgress >= 0.999 else { return }
        stopAnimation()
        phase = .paging
        horizontalOffset = 0
    }

    func updatePaging(translation: CGFloat) {
        guard phase == .paging else { return }
        horizontalOffset = translation
    }

    func endPaging(
        predictedTranslation: CGFloat,
        velocity: CGFloat,
        viewportWidth: CGFloat,
        reducesMotion: Bool
    ) {
        guard phase == .paging, viewportWidth > 0 else { return }
        let requestedDirection: Int
        if abs(predictedTranslation) >= viewportWidth * 0.28 {
            requestedDirection = predictedTranslation < 0 ? 1 : -1
        } else {
            requestedDirection = 0
        }
        let direction = allowedPageDirection(requestedDirection)
        let targetOffset = CGFloat(-direction) * viewportWidth
        guard !reducesMotion else {
            horizontalOffset = targetOffset
            completePage(direction: direction)
            return
        }
        startAnimation(
            kind: .page(direction),
            value: Double(horizontalOffset),
            velocity: Double(velocity),
            target: Double(targetOffset)
        )
    }

    func returnToToday(_ today: Date = Date()) {
        stopAnimation()
        let normalizedToday = calendar.startOfDay(for: today)
        centerDate = clampedCenterDate(normalizedToday)
        weekStartDate = Self.monday(containing: centerDate, calendar: calendar)
        horizontalOffset = 0
        windowRevision += 1
    }

    func displayLinkDidFire(_ link: CADisplayLink) {
        guard animationKind != .none else {
            stopAnimation()
            return
        }
        let timestamp = link.timestamp
        let deltaTime = min(max(timestamp - (lastFrameTimestamp ?? timestamp), 0), 1.0 / 30.0)
        lastFrameTimestamp = timestamp
        guard deltaTime > 0 else { return }

        Self.spring.update(
            value: &animatedValue,
            velocity: &animatedVelocity,
            target: animationTarget,
            deltaTime: deltaTime
        )
        switch animationKind {
        case .zoom:
            let previousProgress = zoomProgress
            zoomProgress = min(max(CGFloat(animatedValue), 0), 1)
            playBoundaryHapticIfNeeded(from: previousProgress, to: zoomProgress)
        case .page:
            horizontalOffset = CGFloat(animatedValue)
        case .none:
            break
        }

        if abs(animatedValue - animationTarget) < 0.001,
           abs(animatedVelocity) < 0.01 {
            let completedKind = animationKind
            stopAnimation()
            switch completedKind {
            case .zoom:
                let previousProgress = zoomProgress
                zoomProgress = CGFloat(animationTarget)
                playBoundaryHapticIfNeeded(from: previousProgress, to: zoomProgress)
                phase = .idle
            case let .page(direction):
                completePage(direction: direction)
            case .none:
                break
            }
        }
    }

    private func startAnimation(kind: AnimationKind, value: Double, velocity: Double, target: Double) {
        stopAnimation()
        animationKind = kind
        animatedValue = value
        animatedVelocity = velocity
        animationTarget = target
        lastFrameTimestamp = nil
        phase = kind == .zoom ? .settling : .paging

        let link = CADisplayLink(target: displayLinkTarget, selector: #selector(TimetableDisplayLinkTarget.tick(_:)))
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopAnimation() {
        displayLink?.invalidate()
        displayLink = nil
        lastFrameTimestamp = nil
        animationKind = .none
    }

    private func completePage(direction: Int) {
        guard direction != 0 else {
            horizontalOffset = 0
            phase = .idle
            return
        }
        let dayDelta = isThreeDay ? direction * 3 : direction * 7
        let proposedCenter = calendar.date(byAdding: .day, value: dayDelta, to: centerDate)
            ?? centerDate
        centerDate = clampedCenterDate(proposedCenter)
        weekStartDate = Self.monday(containing: centerDate, calendar: calendar)
        if !isThreeDay {
            centerDate = calendar.date(byAdding: .day, value: 1, to: weekStartDate)
                ?? weekStartDate
        }
        horizontalOffset = 0
        phase = .idle
        windowRevision += 1
    }

    private func allowedPageDirection(_ direction: Int) -> Int {
        guard direction != 0 else { return 0 }
        let delta = isThreeDay ? direction * 3 : direction * 7
        let proposed = calendar.date(byAdding: .day, value: delta, to: centerDate) ?? centerDate
        let clamped = clampedCenterDate(proposed)
        return calendar.isDate(clamped, inSameDayAs: proposed) ? direction : 0
    }

    private func clampedCenterDate(_ date: Date) -> Date {
        min(max(calendar.startOfDay(for: date), rangeStart), rangeEnd)
    }

    private static func monday(containing date: Date, calendar: Calendar) -> Date {
        let normalized = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: normalized)
        let offset = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -offset, to: normalized) ?? normalized
    }

    private func playBoundaryHapticIfNeeded(from previous: CGFloat, to new: CGFloat) {
        let reachedFullWeek = previous > 0.001 && new <= 0.001
        let reachedThreeDay = previous < 0.999 && new >= 0.999
        guard reachedFullWeek || reachedThreeDay else { return }
        boundaryFeedbackGenerator.impactOccurred()
    }
}

@MainActor
private final class TimetableDisplayLinkTarget: NSObject {
    weak var owner: TimetableContinuousViewportController?

    init(owner: TimetableContinuousViewportController) {
        self.owner = owner
    }

    @objc func tick(_ link: CADisplayLink) {
        owner?.displayLinkDidFire(link)
    }
}
