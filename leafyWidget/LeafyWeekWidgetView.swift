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
            HStack(alignment: .firstTextBaseline) {
                Text(LeafyWidgetL10n.text("本周安排"))
                    .font(.system(size: 15, weight: .bold))
                Spacer(minLength: 4)
                if let first = dates.first, let last = dates.last {
                    Text("\(shortDate(first))–\(shortDate(last))")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(palette.secondary)
                }
            }
            if uniqueCount == 0, days.contains(where: { $0.status == .needsUpdate }) {
                LeafyWidgetQuietState(status: .needsUpdate, palette: palette)
            } else {
                weekGrid(days: days, segments: segments, startMinute: startMinute, endMinute: endMinute)
            }
            HStack(spacing: 5) {
                Text(LeafyWidgetL10n.text("共 %d 项安排", uniqueCount))
                Spacer(minLength: 2)
                Image(systemName: "calendar")
                Text(LeafyWidgetL10n.text("个人日程"))
            }
            .font(.system(size: 9)).foregroundStyle(palette.secondary).lineLimit(1)
        }
        .foregroundStyle(palette.primary)
        .padding(12)
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.twoDigits).day(.twoDigits)
            .locale(LeafyWidgetLanguagePreference.current.locale))
    }

    private func weekGrid(days: [LeafyWidgetDaySnapshot], segments: [[LeafyWidgetDaySegment]],
                          startMinute: Double, endMinute: Double) -> some View {
        GeometryReader { geometry in
            let headerHeight: CGFloat = 28
            let height = max(geometry.size.height - headerHeight, 1)
            let range = max(endMinute - startMinute, 1)
            HStack(alignment: .top, spacing: 2) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: headerHeight)
                    timeAxis(start: startMinute, end: endMinute, height: height)
                }
                .frame(width: 26)
                ForEach(Array(days.enumerated()), id: \.element.date) { index, day in
                    let isToday = LeafyWidgetSnapshotArchive.calendar.isDate(day.date, inSameDayAs: now)
                    VStack(spacing: 0) {
                        dayHeader(date: day.date, isToday: isToday).frame(height: headerHeight)
                        LeafyWeekDayColumn(
                            blocks: LeafyWidgetWeekBlock.layout(segments[index], minimumMinutes: 16 / height * range),
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
        VStack(spacing: 1) {
            Text(date.formatted(.dateTime.weekday(.narrow).locale(LeafyWidgetLanguagePreference.current.locale)))
                .font(.system(size: 9, weight: .medium))
            Text(date.formatted(.dateTime.day(.twoDigits).locale(LeafyWidgetLanguagePreference.current.locale)))
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(isToday ? palette.brand : palette.secondary)
        .frame(maxWidth: .infinity)
        .background(isToday ? palette.brand.opacity(0.10) : .clear,
                    in: RoundedRectangle(cornerRadius: 5))
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
    }

    private func timeAxis(start: Double, end: Double, height: CGFloat) -> some View {
        let ticks = [start] + stride(from: (floor(start / 120) + 1) * 120, to: end, by: 120).filter {
            $0 - start >= 40 && end - $0 >= 40
        } + [end]
        return ZStack(alignment: .top) {
            ForEach(ticks, id: \.self) { minute in
                Text(String(format: "%02d:%02d", Int(minute) / 60, Int(minute) % 60))
                    .font(.system(size: 7, weight: .medium)).monospacedDigit()
                    .foregroundStyle(palette.tertiary)
                    .position(x: 13, y: min(max((minute - start) / (end - start) * height, 5), max(height - 5, 5)))
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
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(palette.brand.opacity(isToday ? 0.08 : 0.025))
                ForEach(Array(stride(from: ceil(startMinute / 120) * 120, to: endMinute, by: 120)), id: \.self) { minute in
                    Rectangle().fill(palette.tertiary.opacity(0.12)).frame(height: 0.5)
                        .offset(y: (minute - startMinute) * scale)
                }
                ForEach(blocks) { block in
                    let width = max((geometry.size.width - CGFloat(block.laneCount - 1) * 1.5) / CGFloat(block.laneCount), 1)
                    let y = max((block.startMinute - startMinute) * scale, 0)
                    let height = max(min((block.endMinute - block.startMinute) * scale - 1,
                                         geometry.size.height - y), 1)
                    Link(destination: block.hiddenCount > 0 ? LeafyWidgetRoute.schedules.url : block.segment.item.destination) {
                        LeafyWeekBlockLabel(block: block, now: now, height: height, palette: palette)
                    }
                    .frame(width: width, height: height)
                    .offset(x: CGFloat(block.lane) * (width + 1.5), y: y)
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
        item.kind == .schedule ? palette.brand : palette.courseAccents[item.accentIndex % palette.courseAccents.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if block.hiddenCount > 0 {
                Text("+\(block.hiddenCount)")
                    .font(.system(size: 10, weight: .bold)).lineLimit(1)
            } else {
                if item.kind == .schedule, height >= 28 {
                    Image(systemName: "calendar").font(.system(size: 7))
                }
                Text(item.title)
                    .font(.system(size: 8, weight: .semibold))
                    .lineLimit(height >= 30 ? 3 : (height >= 22 ? 2 : 1))
                    .truncationMode(.tail)
                if height >= 54, block.laneCount == 1, !item.locationText.isEmpty {
                    Text(item.locationText).font(.system(size: 7)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, height >= 20 ? 3 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(palette.primary)
        .background(accent.opacity(item.isActive(at: now) ? 0.36 : 0.19),
                    in: RoundedRectangle(cornerRadius: 3))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1).fill(accent).frame(width: 1.5).widgetAccentable()
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(block.hiddenCount > 0
            ? LeafyWidgetL10n.text("还有 %d 项安排", block.hiddenCount)
            : "\(item.title), \(item.timeText), \(item.locationText)")
    }
}
