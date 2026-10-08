import SwiftUI

struct TimetableConflictDisplayItem: Identifiable {
    let agenda: TimetableAgendaItem
    let interval: TimetableConflictInterval
    let note: String?
    let location: String
    let timeText: String
    var id: String { agenda.id }
    var typeText: String {
        switch agenda.kind {
        case .course: "课程"
        case .cellReminder, .countdown: "日程"
        case .exam: "考试"
        }
    }
}

struct TimetableConflictDayContent {
    let layout: TimetableConflictLayout
    let items: [String: TimetableConflictDisplayItem]
    static let empty = Self(layout: .empty, items: [:])
}

/// Shares the existing snapshot invalidation rules; geometry is not part of the key.
@MainActor
final class TimetableConflictDayCache {
    private var gridSignature: TimetableGridInputSignature?
    private var scheduleSignature: TimetableScheduleProjectionSignature?
    private struct DayKey: Hashable {
        let week: Int
        let day: Int
        let date: Date
    }
    private var language: AppLanguagePreference?
    private var periodCount: Int?
    private var entries: [DayKey: TimetableConflictDayContent] = [:]
    private let agendaCache = TimetableAgendaItemCache()

    func content(metadata: TimetableDayMetadata, snapshot: TimetableGridSnapshot, totalClasses: Int) -> TimetableConflictDayContent {
        if gridSignature != snapshot.signature || scheduleSignature != metadata.projectionSignature || language != .current || periodCount != totalClasses {
            language = .current
            periodCount = totalClasses
            gridSignature = snapshot.signature
            scheduleSignature = metadata.projectionSignature
            entries.removeAll(keepingCapacity: true)
        }
        let key = DayKey(week: metadata.week, day: metadata.day, date: metadata.date)
        if let content = entries[key] { return content }
        let calendar = Calendar.current
        func date(period: Int, end: Bool) -> Date? {
            guard let slot = TimetablePeriodSchedule.slot(for: period) else { return nil }
            return calendar.date(bySettingHour: end ? slot.endHour : slot.startHour,
                                 minute: end ? slot.endMinute : slot.startMinute, second: 0, of: metadata.date)
        }
        guard let dayStart = date(period: 1, end: false), let dayEnd = date(period: totalClasses, end: true) else { return .empty }
        let values = agendaCache.items(metadata: metadata, gridSnapshot: snapshot, totalClasses: totalClasses).compactMap { item -> TimetableConflictDisplayItem? in
            let start: Date?
            let end: Date?
            let note: String?
            let location: String
            var timeText = item.timeText.replacingOccurrences(of: "\n", with: "–")
            switch item.kind {
            case .course(let course):
                start = date(period: course.duration.min() ?? 1, end: false)
                end = date(period: course.duration.max() ?? 1, end: true)
                note = snapshot.note(for: course, week: metadata.week)
                location = course.timetableCardLocationText
            case .cellReminder(let reminder, _):
                start = reminder.resolvedStartDate ?? date(period: reminder.displayStartPeriod, end: false)
                end = reminder.resolvedEndDate ?? date(period: reminder.displayEndPeriod, end: true)
                note = nil
                location = reminder.locationText
            case .countdown(let projection):
                start = projection.startsAt
                end = projection.endsAt
                note = nil
                location = ""
            case .exam(let projection):
                start = projection.startsAt
                // A missing duration keeps a short visual marker, not an invented end time.
                end = projection.endsAt > projection.startsAt ? projection.endsAt : projection.startsAt.addingTimeInterval(20 * 60)
                note = nil
                location = projection.location
            }
            guard let start, let end, end > start else { return nil }
            switch item.kind {
            case .cellReminder, .countdown:
                timeText = "\(DateFormatters.timeOnly.string(from: start))–\(DateFormatters.timeOnly.string(from: end))"
            default: break
            }
            let lower = max(start, dayStart).timeIntervalSinceReferenceDate
            let upper = min(end, dayEnd).timeIntervalSinceReferenceDate
            guard upper > lower else { return nil }
            return .init(agenda: item, interval: .init(id: item.id, start: lower, end: upper), note: note, location: location, timeText: timeText)
        }
        let result = TimetableConflictDayContent(layout: .make(intervals: values.map(\.interval)), items: Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) }))
        entries[key] = result
        return result
    }
}

nonisolated enum TimetableConflictGeometry {
    static func rects(segments: [TimetableConflictSegment], width: CGFloat, metrics: TimetableLayoutMetrics) -> [CGRect] {
        func y(_ timestamp: Double) -> CGFloat {
            TimetableCurrentTimePosition.yPosition(for: Date(timeIntervalSinceReferenceDate: timestamp), metrics: metrics) ?? 0
        }
        return segments.enumerated().compactMap { index, segment in
            let previousJoins = index > 0 && segments[index - 1].end == segment.start
            let nextJoins = index + 1 < segments.count && segments[index + 1].start == segment.end
            let rawTop = y(segment.start)
            let rawBottom = y(segment.end)
            let inset = min(metrics.cardInset, max(rawBottom - rawTop, 0) / 4)
            let top = rawTop + (previousJoins ? 0 : inset)
            let bottom = rawBottom - (nextJoins ? 0 : inset)
            let availableWidth = max(width - metrics.cardInset * 2, 1)
            let left = metrics.cardInset + CGFloat(segment.leading) * availableWidth + (segment.leading > 0 ? metrics.laneSpacing / 2 : 0)
            let right = metrics.cardInset + CGFloat(segment.trailing) * availableWidth - (segment.trailing < 1 ? metrics.laneSpacing / 2 : 0)
            guard bottom > top else { return nil }
            return CGRect(x: left, y: top, width: max(right - left, 1), height: bottom - top)
        }
    }

    /// Maximal inscribed rectangles, including regions spanning a width transition.
    static func textRegion(in rects: [CGRect], minimumHeight: CGFloat) -> CGRect? {
        var candidates: [CGRect] = []
        for start in rects.indices {
            var region = rects[start]
            candidates.append(region)
            for end in rects.indices where end > start {
                let next = rects[end]
                guard abs(region.maxY - next.minY) < 0.5 else { break }
                let left = max(region.minX, next.minX)
                let right = min(region.maxX, next.maxX)
                guard right > left else { break }
                region = CGRect(x: left, y: region.minY, width: right - left, height: next.maxY - region.minY)
                candidates.append(region)
            }
        }
        let eligible = candidates.filter { $0.height >= minimumHeight }
        return (eligible.isEmpty ? candidates : eligible).sorted {
            if $0.width != $1.width { return $0.width > $1.width }
            if $0.minY != $1.minY { return $0.minY < $1.minY }
            return $0.height > $1.height
        }.first
    }
}

struct TimetableConflictShape: Shape {
    let rects: [CGRect]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        var run: [CGRect] = []
        func appendRun() {
            guard let first = run.first, let last = run.last else { return }
            var points = [CGPoint(x: first.minX, y: first.minY), CGPoint(x: first.maxX, y: first.minY)]
            for (index, box) in run.enumerated() {
                points.append(CGPoint(x: box.maxX, y: box.maxY))
                if index + 1 < run.count { points.append(CGPoint(x: run[index + 1].maxX, y: box.maxY)) }
            }
            points.append(CGPoint(x: last.minX, y: last.maxY))
            for index in run.indices.reversed() {
                let box = run[index]
                points.append(CGPoint(x: box.minX, y: box.minY))
                if index > 0 { points.append(CGPoint(x: run[index - 1].minX, y: box.minY)) }
            }
            // Remove duplicate corners before rounding both outer and inner turns.
            var corners: [CGPoint] = []
            for point in points where corners.last != point { corners.append(point) }
            if corners.last == corners.first { corners.removeLast() }
            guard corners.count >= 3 else { return }
            for index in corners.indices {
                let point = corners[index]
                let before = corners[(index + corners.count - 1) % corners.count]
                let after = corners[(index + 1) % corners.count]
                let incoming = hypot(point.x - before.x, point.y - before.y)
                let outgoing = hypot(after.x - point.x, after.y - point.y)
                let radius = min(5, min(incoming, outgoing) / 2)
                guard incoming > 0, outgoing > 0 else { continue }
                let entry = CGPoint(x: point.x + (before.x - point.x) * radius / incoming, y: point.y + (before.y - point.y) * radius / incoming)
                let exit = CGPoint(x: point.x + (after.x - point.x) * radius / outgoing, y: point.y + (after.y - point.y) * radius / outgoing)
                if index == 0 { path.move(to: entry) } else { path.addLine(to: entry) }
                path.addQuadCurve(to: exit, control: point)
            }
            path.closeSubpath()
        }
        for box in rects {
            if let last = run.last, abs(last.maxY - box.minY) >= 0.5 { appendRun(); run.removeAll() }
            run.append(box)
        }
        appendRun()
        return path
    }
}

struct TimetableConflictBlockView: View {
    @Environment(\.leafyControlScale) private var scale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.leafyThemeColorPreference) private var theme
    @Environment(\.leafyLanguage) private var language
    let item: TimetableConflictDisplayItem
    let rects: [CGRect]
    let width: CGFloat
    let height: CGFloat
    let background: Color
    let isTodayCourse: Bool

    var body: some View {
        let shape = TimetableConflictShape(rects: rects)
        ZStack(alignment: .topLeading) {
            shape.fill(background)
            shape.stroke(isTodayCourse ? AppTheme.accentEmphasis(for: theme) : AppTheme.separator, lineWidth: isTodayCourse ? 1.5 : 0.7)
            let primaryRegion = TimetableConflictGeometry.textRegion(in: rects, minimumHeight: 28 * scale)
            ForEach(Array(rects.enumerated()), id: \.offset) { _, box in
                if !isSchedule, let primaryRegion, box.height >= 16 * scale, box.width >= 14 * scale,
                   box.midY < primaryRegion.minY || box.midY > primaryRegion.maxY {
                    Image(systemName: item.agenda.systemImage)
                        .font(.system(size: 8 * scale, weight: .medium))
                        .foregroundStyle(AppTheme.primaryText)
                        .position(x: box.midX, y: box.minY + 8 * scale)
                        .accessibilityHidden(true)
                }
            }
            if let region = primaryRegion {
                blockText(region: region)
                    .frame(width: max(region.width - 8 * scale, 1), height: max(region.height - 8 * scale, 1), alignment: .topLeading)
                    .clipped()
                    .offset(x: region.minX + 4 * scale, y: region.minY + 4 * scale)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([L10n.text(item.typeText, language: language), item.agenda.title, item.note ?? "", item.location, item.timeText].filter { !$0.isEmpty }.joined(separator: "，"))
    }

    private var isSchedule: Bool {
        switch item.agenda.kind {
        case .cellReminder, .countdown: true
        case .course, .exam: false
        }
    }

    private func blockText(region: CGRect) -> some View {
        let availableHeight = max(region.height - 8 * scale, 0)
        let hasSupportingText = availableHeight > 48 * scale && (item.note?.isEmpty == false || !item.location.isEmpty)
        let supportingHeight: CGFloat = hasSupportingText ? (item.note?.isEmpty == false ? 26 : 14) * scale : (!isSchedule && availableHeight > 36 * scale ? 12 * scale : 0)
        let timeHeight: CGFloat = availableHeight > 92 * scale && region.width > 65 * scale ? 14 * scale : 0
        let titleLines = max(1, min(6, Int((availableHeight - supportingHeight - timeHeight) / (12.5 * scale))))
        return VStack(alignment: .leading, spacing: 3 * scale) {
            HStack(alignment: .firstTextBaseline, spacing: 3 * scale) {
                if isSchedule {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 8 * scale, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)
                        .accessibilityHidden(true)
                }
                Text(item.agenda.title)
                    .font(.system(size: 10.5 * scale, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(titleLines)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if availableHeight > 48 * scale {
                if let note = item.note, !note.isEmpty {
                    Text(note).font(.system(size: 9.5 * scale, weight: .medium))
                        .foregroundStyle(AppTheme.primaryText).lineLimit(2)
                } else if !item.location.isEmpty {
                    Text(item.location).font(.system(size: 9 * scale, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText).lineLimit(1)
                }
            }
            if !isSchedule && !hasSupportingText && availableHeight > 36 * scale {
                Image(systemName: item.agenda.systemImage)
                    .font(.system(size: 8 * scale, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryText)
                    .accessibilityHidden(true)
            }
            if availableHeight > 92 * scale && region.width > 65 * scale {
                Text(item.timeText).font(.system(size: 9 * scale))
                    .foregroundStyle(AppTheme.secondaryText).lineLimit(1)
            }
        }
        .overlay(alignment: .leading) {
            Rectangle().fill(item.agenda.tint).frame(width: 2 * scale).offset(x: -4 * scale)
        }
    }
}

struct TimetableConflictSelection: Identifiable {
    let id: String
    let date: Date
    let items: [TimetableConflictDisplayItem]
}

struct TimetableConflictListSheet: View {
    @Environment(\.leafyLanguage) private var language
    let selection: TimetableConflictSelection
    let onSelect: (TimetableAgendaItem) -> Void
    var body: some View {
        NavigationStack {
            List(selection.items) { item in
                Button { onSelect(item.agenda) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(L10n.text(item.typeText, language: language), systemImage: item.agenda.systemImage)
                            .font(.caption).foregroundStyle(item.agenda.tint)
                        Text(item.agenda.title).leafyHeadline().foregroundStyle(AppTheme.primaryText)
                        Text(item.timeText).leafySubheadline().foregroundStyle(AppTheme.secondaryText)
                        if !item.location.isEmpty { Text(item.location).leafyBody().foregroundStyle(AppTheme.secondaryText) }
                        if let note = item.note { Text(note).leafyBody().foregroundStyle(AppTheme.primaryText) }
                    }
                    .fixedSize(horizontal: false, vertical: true).padding(.vertical, 6)
                }
                .listRowBackground(AppTheme.cardBackground)
            }
            .leafyInsetGroupedListStyle()
            .scrollContentBackground(.hidden)
            .background(LeafyPageBackground())
            .navigationTitle(L10n.text("重叠的安排", language: language))
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("关闭", language: language)) { dismiss() }
                }
            }
        }
    }
    @Environment(\.dismiss) private var dismiss
}
