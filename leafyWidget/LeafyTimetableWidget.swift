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
            let now = Date()
            let archive = LeafyWidgetSnapshotStore.loadArchive()
            completion(LeafyTimetableEntry(date: now, archive: archive,
                                           selectedDayOffset: LeafyWidgetSnapshotStore.selectedDayOffset,
                                           temperatureText: archive?.temperatureText(at: now) ?? "--°"))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LeafyTimetableEntry>) -> Void) {
        let now = Date()
        let archive = LeafyWidgetSnapshotStore.loadArchive()
        let dayOffset = LeafyWidgetSnapshotStore.selectedDayOffset
        let dates = archive?.timelineDates(from: now) ?? [now]
        let entries = dates.map {
            LeafyTimetableEntry(date: $0, archive: archive, selectedDayOffset: dayOffset,
                                temperatureText: archive?.temperatureText(at: $0) ?? "--°")
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(20 * 60))))
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
                                                   endsAt: start.addingTimeInterval(3600), locationText: "图书馆",
                                                   accentIndex: 2))
        return LeafyTimetableEntry(date: now, archive: archive, selectedDayOffset: 0, temperatureText: "23°")
    }
}

struct LeafyTimetableWidget: Widget {
    static var supportedFamilies: [WidgetFamily] {
        var families: [WidgetFamily] = [.systemSmall, .systemMedium]
        if #available(iOS 27, *) { families.append(.systemExtraLargePortrait) }
        return families
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: LeafyWidgetConstants.widgetKind, provider: LeafyTimetableProvider()) { entry in
            LeafyWidgetEntryView(entry: entry)
                .environment(\.locale, LeafyWidgetLanguagePreference.current.locale)
        }
        .configurationDisplayName(LeafyWidgetL10n.text("MyLeafy 课表"))
        .description(LeafyWidgetL10n.text("查看课程与个人日程，竖向超大号展示本周安排。"))
        .supportedFamilies(Self.supportedFamilies)
        .contentMarginsDisabled()
    }
}

struct LeafyWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: LeafyTimetableEntry

    private var palette: LeafyWidgetPalette {
        LeafyWidgetPalette(theme: LeafyWidgetThemeStore.load(), colorScheme: colorScheme,
                           renderingMode: renderingMode)
    }

    private var isExtraLarge: Bool {
        if #available(iOS 27, *) { return family == .systemExtraLargePortrait }
        return false
    }

    var body: some View {
        Group {
            if let archive = entry.archive, archive.isAuthenticated {
                if isExtraLarge {
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
    var isCompact = false

    var body: some View {
        Link(destination: status == .noEvents ? LeafyWidgetRoute.schedules.url : LeafyWidgetRoute.cacheSync.url) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: status == .needsLogin ? "person.crop.circle.badge.exclamationmark" : "calendar")
                    .font(.system(size: isCompact ? 14 : 20)).foregroundStyle(palette.brand)
                Text(LeafyWidgetL10n.text(title))
                    .font(.system(size: isCompact ? 11 : 13, weight: .semibold)).foregroundStyle(palette.primary)
                    .lineLimit(isCompact ? 2 : 3)
                Text(LeafyWidgetL10n.text(message))
                    .font(.system(size: isCompact ? 9 : 10)).foregroundStyle(palette.secondary)
                    .lineLimit(isCompact ? 2 : 3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
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

@available(iOS 27, *)
#Preview(as: .systemExtraLargePortrait) {
    LeafyTimetableWidget()
} timeline: {
    LeafyTimetableProvider().previewEntry()
}
