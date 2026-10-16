import Foundation
import SwiftData
import SwiftUI

nonisolated struct PersonalScheduleExportItem: Equatable, Sendable {
    let key: String
    let title: String
    let start: Date
    let end: Date?
    let location: String
    let note: String
    let minutesBefore: Int
}

@MainActor
enum PersonalScheduleExport {
    static func items(reminders: [TimetableCellReminder], events: [CustomScheduleEvent]) throws -> [PersonalScheduleExportItem] {
        let cells = try reminders.map { reminder in
            guard let start = reminder.resolvedStartDate else { throw CocoaError(.fileReadCorruptFile) }
            return PersonalScheduleExportItem(key: "cellReminder:" + reminder.cellKey, title: reminder.title,
                start: start, end: reminder.endsAt ?? (reminder.startsAt == nil ? reminder.resolvedEndDate : nil),
                location: reminder.locationText, note: reminder.noteText, minutesBefore: reminder.minutesBefore)
        }
        return (cells + events.map {
            PersonalScheduleExportItem(key: "personalSchedule:" + $0.id, title: $0.title,
                start: $0.startsAt, end: $0.endsAt, location: $0.locationText, note: $0.noteText, minutesBefore: $0.minutesBefore)
        }).sorted { ($0.start, $0.key) < ($1.start, $1.key) }
    }
    static func text(_ items: [PersonalScheduleExportItem]) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = UserTimetableSettings.calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "MyLeafy 个人日程（当地时间）\n\n" + items.map { item in
            var lines = [item.title, "开始：" + formatter.string(from: item.start)]
            if let end = item.end { lines.append("结束：" + formatter.string(from: end)) }
            if !item.location.isEmpty { lines.append("地点：" + item.location) }
            if !item.note.isEmpty { lines.append("备注：" + item.note) }
            lines.append(item.minutesBefore > 0 ? "提醒：提前 \(item.minutesBefore) 分钟" : "提醒：关闭")
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n") + "\n"
    }
}

struct PersonalScheduleExportView: View {
    @Query private var reminders: [TimetableCellReminder]
    @State private var busy = false
    @State private var message: String?
    @State private var file: ExportFile?
    private struct ExportFile: Identifiable { let id = UUID(); let url: URL }
    var body: some View {
        List {
            Section {
                Button("导出到 Apple 日历") { export(calendar: true) }
                Button("导出 TXT") { export(calendar: false) }
            }.disabled(busy)
            Section {
                Text("导出全部现存个人日程，包含过去和未来。学校课程、考试和随记不包含在内。")
                Text("没有结束时间的日程在 Apple 日历中按 45 分钟安排；TXT 保留原始信息。再次导出可更新已导出的事件。")
            }.font(.footnote).foregroundStyle(.secondary)
            if busy { ProgressView("正在导出") }
        }
        .navigationTitle("导出日程")
        .leafySheet(item: $file) { item in ShareSheet(activityItems: [item.url]) }
        .alert("导出日程", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("知道了", role: .cancel) {}
        } message: { Text(message ?? "") }
    }
    private func export(calendar: Bool) {
        guard !busy else { return }
        let scope = CampusOperationScope()
        do {
            let items = try PersonalScheduleExport.items(reminders: reminders, events: CustomScheduleStore.load())
            guard !items.isEmpty else { message = "暂无可导出的日程。"; return }
            if calendar {
                busy = true
                Task { @MainActor in
                    defer { busy = false }
                    do {
                        try scope.check()
                        let result = try await TimetableCalendarExportService().exportPersonalSchedules(items)
                        try scope.check()
                        message = result.message
                    } catch { if scope.isCurrent { message = error.localizedDescription } }
                }
            } else {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ScheduleExport-" + UUID().uuidString)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appendingPathComponent("MyLeafy-日程.txt")
                try PersonalScheduleExport.text(items).write(to: url, atomically: true, encoding: .utf8)
                file = ExportFile(url: url)
            }
        } catch { message = error.localizedDescription }
    }
}
