import AppIntents
import SwiftUI
import WidgetKit

struct LeafyDayWidgetView: View {
    let entry: LeafyTimetableEntry
    let archive: LeafyWidgetSnapshotArchive
    let isSmall: Bool
    let palette: LeafyWidgetPalette

    var body: some View {
        GeometryReader { geometry in
            let snapshot = archive.snapshot(for: entry.selectedDayOffset, relativeTo: entry.date)
            let rowHeight: CGFloat = isSmall ? 30 : 27
            let capacity = min(isSmall ? 3 : 4, max(Int((geometry.size.height - 66) / rowHeight), 1))
            HStack(spacing: isSmall ? 8 : 12) {
                dateRail(date: snapshot.date)
                Rectangle().fill(palette.rule).frame(width: 0.5)
                agenda(snapshot: snapshot, capacity: capacity)
            }
            .padding(isSmall ? 12 : 14)
            .foregroundStyle(palette.primary)
        }
    }

    private func dateRail(date: Date) -> some View {
        VStack(spacing: isSmall ? 5 : 6) {
            Text(date.formatted(.dateTime.month(.abbreviated)
                    .locale(LeafyWidgetLanguagePreference.current.locale)))
                .font(.system(size: isSmall ? 10 : 12, weight: .semibold))
            Text(date.formatted(.dateTime.weekday(.abbreviated)
                    .locale(LeafyWidgetLanguagePreference.current.locale)))
                .font(.system(size: isSmall ? 10 : 12, weight: .medium))
            Text(date.formatted(.dateTime.day()
                    .locale(LeafyWidgetLanguagePreference.current.locale)))
                .font(.system(size: isSmall ? 24 : 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(palette.onAccent)
                .frame(width: isSmall ? 36 : 46, height: isSmall ? 36 : 46)
                .background {
                    Circle().fill(palette.brand.opacity(palette.isFullColor ? 1 : 0.18))
                        .widgetAccentable()
                }
            Text(entry.temperatureText)
                .font(.system(size: isSmall ? 10 : 12, weight: .medium))
                .foregroundStyle(palette.secondary)
        }
        .frame(width: isSmall ? 36 : 48)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(date.formatted(date: .complete, time: .omitted)), \(entry.temperatureText)")
    }

    private func agenda(snapshot: LeafyWidgetDaySnapshot, capacity: Int) -> some View {
        let remaining = snapshot.remainingItems(at: entry.date)
        let displayed = Array(remaining.prefix(capacity))
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                if !isSmall {
                    Text(LeafyWidgetL10n.text(entry.selectedDayOffset == 0 ? "今日安排" : "明日安排"))
                        .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                }
                Spacer(minLength: 0)
                LeafyWidgetDaySwitchControl(selectedDayOffset: entry.selectedDayOffset,
                                            palette: palette, isSmall: isSmall)
            }
            .frame(height: 24)
            if snapshot.status != .ready {
                LeafyWidgetQuietState(status: snapshot.status, palette: palette, isCompact: isSmall)
            } else if remaining.isEmpty {
                endedState(count: snapshot.items.count)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(displayed.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Rectangle().fill(palette.rule).frame(height: 0.5) }
                        Link(destination: item.destination) {
                            LeafyAgendaRow(item: item, now: entry.date, isSmall: isSmall, palette: palette)
                        }
                        .frame(maxHeight: .infinity)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                footer(hiddenCount: remaining.count - displayed.count, snapshot: snapshot)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func endedState(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: "checkmark.circle").foregroundStyle(palette.brand)
            Text(LeafyWidgetL10n.text(entry.selectedDayOffset == 0 ? "今日安排已结束" : "明日安排已结束"))
                .font(.system(size: isSmall ? 11 : 13, weight: .semibold))
            Text(LeafyWidgetL10n.text("全天共 %d 项", count))
                .font(.system(size: 10)).foregroundStyle(palette.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func footer(hiddenCount: Int, snapshot: LeafyWidgetDaySnapshot) -> some View {
        if hiddenCount > 0 {
            Link(destination: LeafyWidgetRoute.schedules.url) {
                HStack(spacing: 3) {
                    Text(LeafyWidgetL10n.text("还有 %d 项安排", hiddenCount))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 7, weight: .semibold))
                }
                .font(.system(size: 9, weight: .medium)).foregroundStyle(palette.secondary)
                .lineLimit(1)
            }
            .frame(height: 12)
        } else if !isSmall, let exam = snapshot.nextExamText {
            Text(exam).font(.system(size: 9)).foregroundStyle(palette.secondary).lineLimit(1)
                .frame(height: 12)
        }
    }
}

private struct LeafyAgendaRow: View {
    let item: LeafyWidgetAgendaItem
    let now: Date
    let isSmall: Bool
    let palette: LeafyWidgetPalette

    private var accent: Color {
        palette.isFullColor && item.kind == .course
            ? palette.courseAccents[item.accentIndex % palette.courseAccents.count] : palette.brand
    }

    var body: some View {
        Group {
            if isSmall {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 3) {
                        Text(item.timeText)
                            .font(.system(size: 9, weight: .medium)).monospacedDigit().lineLimit(1)
                        if item.isActive(at: now) {
                            Image(systemName: "clock.fill").font(.system(size: 8))
                        } else if item.kind == .schedule {
                            Image(systemName: "calendar").font(.system(size: 8))
                        }
                    }
                    .foregroundStyle(item.isActive(at: now) ? palette.brand : palette.secondary)
                    Text(item.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                }
                .padding(.leading, 7)
                .overlay(alignment: .leading) { accentBar }
            } else {
                HStack(spacing: 7) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(LeafyWidgetAgendaItem.time(item.startsAt))
                            .font(.system(size: 11, weight: .medium)).monospacedDigit()
                        if let end = item.endsAt {
                            Text(LeafyWidgetAgendaItem.time(end))
                                .font(.system(size: 9)).monospacedDigit().foregroundStyle(palette.secondary)
                        }
                    }
                    .frame(width: 35, alignment: .leading)
                    accentBar
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 3) {
                            if item.isActive(at: now) {
                                Image(systemName: "clock.fill").font(.system(size: 9)).foregroundStyle(palette.brand)
                            } else if item.kind == .schedule {
                                Image(systemName: "calendar").font(.system(size: 9))
                            }
                            Text(item.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        }
                        if !item.locationText.isEmpty {
                            Text(item.locationText).font(.system(size: 9)).foregroundStyle(palette.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(palette.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.title), \(item.timeText), \(item.locationText)")
        .accessibilityValue(item.isActive(at: now) ? LeafyWidgetL10n.text("进行中") : "")
    }

    private var accentBar: some View {
        Capsule().fill(accent).frame(width: 2.5, height: isSmall ? 23 : 22).widgetAccentable()
    }
}

private struct LeafyWidgetDaySwitchControl: View {
    let selectedDayOffset: Int
    let palette: LeafyWidgetPalette
    let isSmall: Bool

    var body: some View {
        HStack(spacing: 1) {
            dayButton(title: "今", offset: 0)
            dayButton(title: "明", offset: 1)
        }
        .padding(2)
        .background(palette.brand.opacity(palette.isFullColor ? 0.07 : 0.10), in: Capsule())
    }

    private func dayButton(title: String, offset: Int) -> some View {
        Button(intent: LeafySelectWidgetDayIntent(dayOffset: offset)) {
            Text(LeafyWidgetL10n.text(title))
                .font(.system(size: isSmall ? 10 : 11, weight: .semibold))
                .frame(width: isSmall ? 29 : 34, height: 20)
                .foregroundStyle(selectedDayOffset == offset ? palette.onAccent : palette.secondary)
                .background {
                    if selectedDayOffset == offset {
                        Capsule().fill(palette.brand.opacity(palette.isFullColor ? 1 : 0.22)).widgetAccentable()
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(LeafyWidgetL10n.text(offset == 0 ? "显示今天安排" : "显示明天安排"))
        .accessibilityAddTraits(selectedDayOffset == offset ? .isSelected : [])
    }
}
