import SwiftUI
import WidgetKit

struct LeafyWeekWidgetView: View {
    let archive: LeafyWidgetSnapshotArchive
    let now: Date
    let palette: LeafyWidgetPalette

    var body: some View {
        let dates = archive.weekDates(containing: now)
        let days = dates.map { archive.snapshot(on: $0, now: now) }
        let segments = days.map { day in day.items.map { LeafyWidgetDaySegment.make(item: $0, day: day.date) } }
        let allSegments = segments.flatMap { $0 }
        let startMinute = min(Double(archive.defaultStartMinute), allSegments.map(\.startMinute).min() ?? 1440)
        let endMinute = max(Double(archive.defaultEndMinute), allSegments.map(\.endMinute).max() ?? 0)
        let uniqueCount = Set(allSegments.map { $0.item.id }).count
        VStack(alignment: .leading, spacing: 6) {
            header(dates: dates)
            if uniqueCount == 0, days.contains(where: { $0.status == .needsUpdate }) {
                LeafyWidgetQuietState(status: .needsUpdate, palette: palette)
            } else {
                weekGrid(days: days, segments: segments, startMinute: startMinute, endMinute: endMinute)
            }
            Rectangle().fill(palette.rule).frame(height: 0.5)
            nextItemFooter
        }
        .foregroundStyle(palette.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func header(dates: [Date]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(LeafyWidgetL10n.text("本周安排"))
                .font(.system(size: 17, weight: .semibold)).lineLimit(1)
                .layoutPriority(1)
            if let first = dates.first, let last = dates.last {
                Text("\(shortDate(first))–\(shortDate(last))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            let temperature = archive.temperatureText(at: now)
            let condition = archive.weatherConditionText(at: now).map(LeafyWidgetL10n.text)
            Text(condition.map { "\(temperature) \($0)" } ?? temperature)
                .font(.system(size: 11, weight: .medium)).foregroundStyle(palette.secondary)
                .lineLimit(1).layoutPriority(1)
        }
    }

    private var nextItemFooter: some View {
        let today = archive.snapshot(on: now, now: now)
        let next = today.remainingItems(at: now).first
        return Group {
            if let next {
                Link(destination: next.destination) {
                    HStack(spacing: 6) {
                        Text(LeafyWidgetL10n.text(next.isActive(at: now) ? "进行中" : "下一项"))
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(palette.secondary)
                        Text(LeafyWidgetAgendaItem.time(next.startsAt))
                            .font(.system(size: 10, weight: .medium)).monospacedDigit()
                        Text(next.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        if !next.locationText.isEmpty {
                            Text(next.locationText).font(.system(size: 9))
                                .foregroundStyle(palette.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(palette.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "\(LeafyWidgetL10n.text(next.isActive(at: now) ? "进行中" : "下一项")), \(next.title), \(next.timeText), \(next.locationText)"
                    )
                }
            } else {
                Link(destination: today.status == .needsUpdate ? LeafyWidgetRoute.cacheSync.url : LeafyWidgetRoute
                    .schedules.url) {
                        HStack(spacing: 7) {
                            Image(systemName: today.status == .needsUpdate ? "arrow.clockwise" : "checkmark.circle")
                                .foregroundStyle(palette.brand)
                            Text(LeafyWidgetL10n.text(today.status == .needsUpdate ? "打开 App 更新小组件"
                                    : (today.items.isEmpty ? "当天没有安排" : "今日安排已结束")))
                                .font(.system(size: 11, weight: .medium)).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
            }
        }
        .frame(height: 18, alignment: .leading)
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.twoDigits).day(.twoDigits)
            .locale(LeafyWidgetLanguagePreference.current.locale))
    }

    private func weekGrid(days: [LeafyWidgetDaySnapshot], segments: [[LeafyWidgetDaySegment]],
                          startMinute: Double, endMinute: Double) -> some View {
        GeometryReader { geometry in
            let headerHeight: CGFloat = 38
            let height = max(geometry.size.height - headerHeight, 1)
            let range = max(endMinute - startMinute, 1)
            HStack(alignment: .top, spacing: 2) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: headerHeight)
                    timeAxis(start: startMinute, end: endMinute, height: height)
                }
                .frame(width: 29)
                ForEach(Array(days.enumerated()), id: \.element.date) { index, day in
                    let isToday = LeafyWidgetSnapshotArchive.calendar.isDate(day.date, inSameDayAs: now)
                    VStack(spacing: 0) {
                        dayHeader(date: day.date, isToday: isToday).frame(height: headerHeight)
                        LeafyWeekDayColumn(
                            blocks: LeafyWidgetWeekBlock.layout(segments[index], minimumMinutes: 20 / height * range),
                            startMinute: startMinute, endMinute: endMinute, now: now,
                            isToday: isToday, palette: palette
                        )
                        .frame(height: height)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func dayHeader(date: Date, isToday: Bool) -> some View {
        VStack(spacing: 2) {
            Text(date.formatted(.dateTime.weekday(.narrow).locale(LeafyWidgetLanguagePreference.current.locale)))
                .font(.system(size: 10, weight: .medium)).foregroundStyle(palette.secondary)
            Text(String(LeafyWidgetSnapshotArchive.calendar.component(.day, from: date)))
                .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                .foregroundStyle(isToday ? palette.onAccent : palette.primary)
                .frame(width: 23, height: 23)
                .background {
                    if isToday {
                        Circle().fill(palette.brand.opacity(palette.isFullColor ? 1 : 0.22)).widgetAccentable()
                    }
                }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
    }

    private func timeAxis(start: Double, end: Double, height: CGFloat) -> some View {
        let interval = 60.0
        let ticks = [start] + stride(from: (floor(start / interval) + 1) * interval, to: end, by: interval).filter {
            $0 - start >= 40 && end - $0 >= 40
        } + [end]
        return ZStack(alignment: .top) {
            ForEach(ticks, id: \.self) { minute in
                Text(String(format: "%02d:%02d", Int(minute) / 60, Int(minute) % 60))
                    .font(.system(size: 9, weight: .medium)).monospacedDigit()
                    .foregroundStyle(palette.tertiary)
                    .position(
                        x: 14,
                        y: min(max((minute - start) / max(end - start, 1) * height, 5), max(height - 5, 5))
                    )
            }
        }
        .frame(height: height)
    }
}

private struct LeafyWeekDayColumn: View {
    let blocks: [LeafyWidgetWeekBlock]
    let startMinute: Double
    let endMinute: Double
    let now: Date
    let isToday: Bool
    let palette: LeafyWidgetPalette

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.height / max(endMinute - startMinute, 1)
            let tickInterval = 60.0
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(palette.brand.opacity(isToday ? 0.07 : 0.02))
                ForEach(Array(stride(from: ceil(startMinute / tickInterval) * tickInterval,
                                     to: endMinute, by: tickInterval)), id: \.self) { minute in
                    Rectangle().fill(palette.rule).frame(height: 0.5)
                        .offset(y: (minute - startMinute) * scale)
                }
                ForEach(blocks) { block in
                    let width = max((geometry.size.width - CGFloat(block.laneCount - 1) * 2)
                        / CGFloat(block.laneCount), 1)
                    let y = max((block.startMinute - startMinute) * scale, 0)
                    let height = max(min((block.endMinute - block.startMinute) * scale - 1,
                                         geometry.size.height - y), 1)
                    Link(destination: block.hiddenCount > 0 ? LeafyWidgetRoute.schedules.url : block.segment.item
                        .destination) {
                            LeafyWeekBlockLabel(block: block, now: now, height: height,
                                                palette: palette)
                        }
                        .frame(width: width, height: height)
                        .offset(x: CGFloat(block.lane) * (width + 2), y: y)
                }
            }
            .clipped()
        }
    }
}

private struct LeafyWeekBlockLabel: View {
    let block: LeafyWidgetWeekBlock
    let now: Date
    let height: CGFloat
    let palette: LeafyWidgetPalette

    private var item: LeafyWidgetAgendaItem { block.segment.item }
    private var accent: Color {
        palette.isFullColor && item.kind == .course
            ? palette.courseAccents[item.accentIndex % palette.courseAccents.count] : palette.brand
    }

    private var titleLineLimit: Int {
        let iconSpace: CGFloat = item.kind == .schedule && height >= 42 ? 12 : 0
        return max(1, min(4, Int((height - 6 - iconSpace) / 12)))
    }

    private var fillOpacity: Double {
        guard palette.isFullColor else { return item.isActive(at: now) ? 0.18 : 0.10 }
        let normal = palette.isDark ? 0.22 : (item.kind == .course ? 0.64 : 0.18)
        return item.isActive(at: now) ? normal + 0.12 : normal
    }

    var body: some View {
        Group {
            if block.hiddenCount > 0 {
                Text("+\(block.hiddenCount)")
                    .font(.system(size: 10, weight: .semibold)).lineLimit(1)
            } else if item.kind == .course, !item.locationText.isEmpty {
                ViewThatFits(in: .vertical) {
                    roomFirstLabel(titleLines: 4)
                    roomFirstLabel(titleLines: 3)
                    roomFirstLabel(titleLines: 2)
                    roomFirstLabel(titleLines: 1)
                    roomFirstLabel(titleLines: 0)
                }
            } else {
                ViewThatFits(in: .vertical) {
                    itemLabel(showLocation: true).fixedSize(horizontal: false, vertical: true)
                    itemLabel(showLocation: false)
                }
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, height >= 26 ? 2 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(palette.primary)
        .multilineTextAlignment(.leading)
        .background(accent.opacity(fillOpacity),
                    in: RoundedRectangle(cornerRadius: 5))
        .overlay(alignment: .leading) {
            if item.kind == .schedule || item.isActive(at: now) {
                Capsule().fill(accent).frame(width: 2).padding(.vertical, 3).widgetAccentable()
            }
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(block.hiddenCount > 0
            ? LeafyWidgetL10n.text("还有 %d 项安排", block.hiddenCount)
            : "\(item.title), \(item.timeText), \(item.locationText)")
        .accessibilityValue(item.isActive(at: now) ? LeafyWidgetL10n.text("进行中") : "")
    }

    private func roomFirstLabel(titleLines: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if titleLines > 0 {
                Text(item.title).font(.system(size: 10, weight: .semibold))
                    .lineLimit(titleLines).truncationMode(.tail)
            }
            locationLabel
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var locationLabel: some View {
        let text = item.locationText.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return ViewThatFits(in: .horizontal) {
            Text(text).font(.system(size: 9, weight: .medium)).fixedSize()
            Text(text).font(.system(size: 8, weight: .medium)).fixedSize()
            Text(text).font(.system(size: 8, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(palette.secondary)
    }

    private func itemLabel(showLocation: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if item.kind == .schedule, height >= 42 {
                Image(systemName: "calendar").font(.system(size: 8))
            }
            Text(item.title)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(showLocation ? 4 : titleLineLimit)
                .truncationMode(.tail)
            if showLocation, block.laneCount == 1, !item.locationText.isEmpty {
                Text(item.locationText).font(.system(size: 8)).foregroundStyle(palette.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
