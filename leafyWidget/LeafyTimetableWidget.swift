import AppIntents
import SwiftUI
import WidgetKit

struct LeafyTimetableEntry: TimelineEntry {
    let date: Date
    let archive: LeafyWidgetSnapshotArchive?
    let selectedDayOffset: Int
    let temperatureText: String
}

struct LeafyTimetableProvider: TimelineProvider {
    func placeholder(in context: Context) -> LeafyTimetableEntry { previewEntry() }

    func getSnapshot(in context: Context, completion: @escaping (LeafyTimetableEntry) -> Void) {
        if context.isPreview {
            completion(previewEntry())
        } else {
            completion(LeafyTimetableEntry(date: Date(), archive: LeafyWidgetSnapshotStore.loadArchive(),
                selectedDayOffset: LeafyWidgetSnapshotStore.selectedDayOffset, temperatureText: "--°"))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LeafyTimetableEntry>) -> Void) {
        let now = Date()
        let archive = LeafyWidgetSnapshotStore.loadArchive()
        let dayOffset = LeafyWidgetSnapshotStore.selectedDayOffset
        Task {
            let temperature = context.family == .systemSmall
                ? await LeafyWidgetWeatherService.currentTemperatureText() : ""
            let dates = archive?.timelineDates(from: now) ?? [now]
            let entries = dates.map {
                LeafyTimetableEntry(date: $0, archive: archive, selectedDayOffset: dayOffset,
                                   temperatureText: temperature)
            }
            // Reload periodically for weather; the supplied boundaries remain usable if the
            // system defers the reload. Dates and active items never depend on app foregrounding.
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(20 * 60))))
        }
    }

    func previewEntry() -> LeafyTimetableEntry {
        let now = Date()
        let calendar = LeafyWidgetSnapshotArchive.calendar
        let day = calendar.startOfDay(for: now)
        var archive = LeafyWidgetSnapshotArchive(
            generatedAt: now, isAuthenticated: true, semesters: [], items: [], exams: [],
            defaultStartMinute: 480, defaultEndMinute: 1305, syncText: nil, lastFailureText: nil
        )
        let weekdays = archive.weekDates(containing: now)
        for (index, date) in weekdays.enumerated() where index < 5 {
            let start = calendar.date(byAdding: .minute, value: 480 + (index % 3) * 120, to: date) ?? date
            archive.items.append(LeafyWidgetAgendaItem(
                id: "preview-\(index)", kind: .course, sourceID: UUID().uuidString,
                title: ["数据结构", "大学英语", "高等数学", "森林生态学", "体育"][index],
                startsAt: start, endsAt: start.addingTimeInterval(95 * 60), locationText: "二教 205",
                accentIndex: index
            ))
        }
        let start = max(now.addingTimeInterval(1800), day.addingTimeInterval(9 * 3600))
        archive.items.append(LeafyWidgetAgendaItem(id: "preview-schedule", kind: .schedule,
            sourceID: "preview", title: "图书馆自习", startsAt: start,
            endsAt: start.addingTimeInterval(3600), locationText: "图书馆", accentIndex: 2))
        return LeafyTimetableEntry(date: now, archive: archive, selectedDayOffset: 0, temperatureText: "23°")
    }
}

struct LeafyTimetableWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: LeafyWidgetConstants.widgetKind, provider: LeafyTimetableProvider()) { entry in
            LeafyWidgetEntryView(entry: entry)
                .environment(\.locale, LeafyWidgetLanguagePreference.current.locale)
        }
        .configurationDisplayName(LeafyWidgetL10n.text("MyLeafy 课表"))
        .description(LeafyWidgetL10n.text("查看课程与个人日程，大号小组件展示本周安排。"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

private struct LeafyWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: LeafyTimetableEntry

    private var palette: LeafyWidgetPalette {
        LeafyWidgetPalette(theme: LeafyWidgetThemeStore.load(), colorScheme: colorScheme)
    }

    var body: some View {
        Group {
            if let archive = entry.archive, archive.isAuthenticated {
                if family == .systemLarge {
                    LeafyWeekWidgetView(archive: archive, now: entry.date, palette: palette)
                } else {
                    LeafyDayWidgetView(entry: entry, archive: archive,
                                       isSmall: family == .systemSmall, palette: palette)
                }
            } else {
                LeafyWidgetQuietState(
                    status: entry.archive == nil ? .needsUpdate : .needsLogin,
                    palette: palette
                )
                .padding(16)
            }
        }
        .invalidatableContent()
        .containerBackground(for: .widget) { LeafyWidgetBackground(palette: palette) }
        .widgetURL(entry.archive?.isAuthenticated == true
                   ? LeafyWidgetRoute.timetable.url : LeafyWidgetRoute.cacheSync.url)
    }
}

struct LeafyWidgetQuietState: View {
    let status: LeafyWidgetDaySnapshot.Status
    let palette: LeafyWidgetPalette

    var body: some View {
        Link(destination: status == .noEvents ? LeafyWidgetRoute.schedules.url : LeafyWidgetRoute.cacheSync.url) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: status == .needsLogin ? "person.crop.circle.badge.exclamationmark" : "calendar")
                    .font(.title3).foregroundStyle(palette.brand)
                Text(LeafyWidgetL10n.text(title))
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.primary)
                Text(LeafyWidgetL10n.text(message))
                    .font(.system(size: 10)).foregroundStyle(palette.secondary)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var title: String {
        switch status {
        case .needsLogin: "需要重新登录"
        case .needsUpdate: "打开 App 更新小组件"
        default: "当天没有安排"
        }
    }

    private var message: String {
        switch status {
        case .needsLogin: "登录后查看课程与个人日程。"
        case .needsUpdate: "打开 App，读取本机课程与日程。"
        default: "课程和个人日程会显示在这里。"
        }
    }
}

private struct LeafyDayWidgetView: View {
    let entry: LeafyTimetableEntry
    let archive: LeafyWidgetSnapshotArchive
    let isSmall: Bool
    let palette: LeafyWidgetPalette

    var body: some View {
        GeometryReader { geometry in
            let rowStride: CGFloat = isSmall ? 27 : 23
            let available = geometry.size.height - 20 - 31 - 10 - 12
            let capacity = min(isSmall ? 3 : 4, max(Int((available + 3) / rowStride), 1))
            content(capacity: capacity)
        }
    }

    private func content(capacity: Int) -> some View {
        let snapshot = archive.snapshot(for: entry.selectedDayOffset, relativeTo: entry.date)
        let remaining = snapshot.remainingItems(at: entry.date)
        let displayed = Array(remaining.prefix(capacity))
        return VStack(alignment: .leading, spacing: 5) {
            header(date: snapshot.date)
            if snapshot.status == .ready {
                if remaining.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Image(systemName: "checkmark.circle").foregroundStyle(palette.brand)
                        Text(LeafyWidgetL10n.text("今日安排已结束"))
                            .font(.system(size: 13, weight: .semibold))
                        Text(LeafyWidgetL10n.text("全天共 %d 项", snapshot.items.count))
                            .font(.system(size: 10)).foregroundStyle(palette.secondary)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(displayed) { item in
                            Link(destination: item.destination) {
                                LeafyAgendaRow(item: item, now: entry.date, isSmall: isSmall, palette: palette)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    footer(hiddenCount: remaining.count - displayed.count, snapshot: snapshot)
                }
            } else {
                LeafyWidgetQuietState(status: snapshot.status, palette: palette)
            }
        }
        .foregroundStyle(palette.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func header(date: Date) -> some View {
        HStack(alignment: .center, spacing: 4) {
            VStack(alignment: .leading, spacing: 1) {
                Text(LeafyWidgetL10n.text(entry.selectedDayOffset == 0 ? "今日安排" : "明日安排"))
                    .font(.system(size: isSmall ? 13 : 15, weight: .bold))
                    .lineLimit(1).minimumScaleFactor(0.85)
                HStack(spacing: 4) {
                    Text(date.formatted(.dateTime.month(.twoDigits).day(.twoDigits)
                        .locale(LeafyWidgetLanguagePreference.current.locale)))
                    if isSmall { Text(entry.temperatureText) }
                }
                .font(.system(size: 9, weight: .medium)).foregroundStyle(palette.secondary)
            }
            Spacer(minLength: 0)
            LeafyWidgetDaySwitchControl(selectedDayOffset: entry.selectedDayOffset, palette: palette,
                                       isSmall: isSmall)
        }
        .frame(height: 31)
    }

    @ViewBuilder
    private func footer(hiddenCount: Int, snapshot: LeafyWidgetDaySnapshot) -> some View {
        if hiddenCount > 0 {
            Link(destination: LeafyWidgetRoute.schedules.url) {
                Text(LeafyWidgetL10n.text("还有 %d 项安排", hiddenCount))
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
        } else if !isSmall, let exam = snapshot.nextExamText {
            Text(exam).font(.system(size: 9)).foregroundStyle(palette.secondary).lineLimit(1)
        }
    }
}

private struct LeafyAgendaRow: View {
    let item: LeafyWidgetAgendaItem
    let now: Date
    let isSmall: Bool
    let palette: LeafyWidgetPalette

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(item.kind == .schedule ? palette.brand : palette.courseAccents[item.accentIndex % palette.courseAccents.count])
                .frame(width: 3)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    if item.kind == .schedule {
                        Image(systemName: "calendar").font(.system(size: 8))
                    }
                    if !isSmall, item.isActive(at: now) {
                        Image(systemName: "clock.fill").font(.system(size: 8)).foregroundStyle(palette.brand)
                    }
                    Text(item.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    if !isSmall {
                        if !item.locationText.isEmpty {
                            Text(item.locationText).font(.system(size: 9))
                                .foregroundStyle(palette.secondary).lineLimit(1)
                                .layoutPriority(-1)
                        }
                        Spacer(minLength: 2)
                        Text(item.timeText).font(.system(size: 10, weight: .medium))
                            .foregroundStyle(palette.secondary).lineLimit(1).layoutPriority(1)
                    }
                }
                if isSmall {
                    HStack(spacing: 4) {
                        if item.isActive(at: now) {
                            Text(LeafyWidgetL10n.text("进行中")).foregroundStyle(palette.brand)
                        }
                        Text(item.timeText)
                    }
                    .font(.system(size: 9)).foregroundStyle(palette.secondary).lineLimit(1)
                }

            }
        }
        .frame(height: isSmall ? 24 : 20, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.title), \(item.timeText), \(item.locationText)")
        .accessibilityValue(item.isActive(at: now) ? LeafyWidgetL10n.text("进行中") : "")
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
        .background(palette.surface.opacity(0.58), in: Capsule())
    }

    private func dayButton(title: String, offset: Int) -> some View {
        Button(intent: LeafySelectWidgetDayIntent(dayOffset: offset)) {
            Text(LeafyWidgetL10n.text(title))
                .font(.system(size: isSmall ? 9 : 11, weight: .bold))
                .frame(width: isSmall ? 19 : 26, height: 22)
                .foregroundStyle(selectedDayOffset == offset ? palette.surface : palette.secondary)
                .background(selectedDayOffset == offset ? palette.brand : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(LeafyWidgetL10n.text(offset == 0 ? "显示今天安排" : "显示明天安排"))
        .accessibilityAddTraits(selectedDayOffset == offset ? .isSelected : [])
    }
}

#Preview(as: .systemSmall) {
    LeafyTimetableWidget()
} timeline: {
    LeafyTimetableProvider().previewEntry()
}

#Preview(as: .systemMedium) {
    LeafyTimetableWidget()
} timeline: {
    LeafyTimetableProvider().previewEntry()
}

#Preview(as: .systemLarge) {
    LeafyTimetableWidget()
} timeline: {
    LeafyTimetableProvider().previewEntry()
}
