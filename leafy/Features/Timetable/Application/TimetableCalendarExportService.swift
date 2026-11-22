import EventKit
import Foundation

enum TimetableCalendarExportRange: String, CaseIterable, Identifiable {
    case currentWeek
    case remainingSemester
    case fullSemester
    case customWeeks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .currentWeek:
            return L10n.text("当前周")
        case .remainingSemester:
            return L10n.text("剩余学期")
        case .fullSemester:
            return L10n.text("全学期")
        case .customWeeks:
            return L10n.text("自定义")
        }
    }
}

struct TimetableCalendarExportResult: Equatable {
    let created: Int
    let updated: Int
    let removed: Int

    var message: String {
        L10n.text("已导出到系统日历：新增 %d 个，更新 %d 个，移除 %d 个。", created, updated, removed)
    }
}

struct TimetableCalendarClearResult: Equatable {
    let removed: Int

    var message: String {
        if removed == 0 {
            return L10n.text("系统日历中没有所选范围内 %@ 已导出的课表事件。", AppBrand.displayName)
        }
        return L10n.text("已从系统日历清理所选范围内 %@ 课表事件：移除 %d 个。", AppBrand.displayName, removed)
    }
}

struct TimetableCalendarEventDraft: Equatable {
    let occurrenceKey: String
    let title: String
    let location: String
    let notes: String
    let startDate: Date
    let endDate: Date
    let url: URL
}

enum TimetableCalendarExportError: LocalizedError {
    case permissionDenied
    case calendarUnavailable
    case readOnlyEvents
    case legacyEventsRequireConfirmation(Set<String>)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return L10n.text("未获得完整日历访问权限，无法覆盖更新已导出的课表。请在系统设置中允许 %@ 访问日历。", AppBrand.displayName)
        case .readOnlyEvents:
            return L10n.text("部分已导出事件所在日历不可编辑，未作更改。请先在系统日历中恢复编辑权限。")
        case let .legacyEventsRequireConfirmation(identifiers):
            return L10n.text("发现 %d 个旧版导出事件，需确认后才能更新或清理。", identifiers.count)
        case .calendarUnavailable:
            return L10n.text("没有可写入的系统日历。请先在系统日历中启用一个可写日历。")
        }
    }
}

@MainActor
enum TimetableCalendarExportBuilder {
    static let urlHost = "timetable"
    private static let examKeyPrefix = "exam:"
    private static let cellReminderKeyPrefix = "cellReminder:"

    static func weekRange(
        for range: TimetableCalendarExportRange,
        currentWeek: Int,
        referenceDate: Date = Date(),
        totalWeeks: Int? = nil,
        customWeeks: ClosedRange<Int>? = nil
    ) -> ClosedRange<Int> {
        let resolvedTotalWeeks = totalWeeks ?? SemesterConfig.supportedWeeks
        let resolvedCurrentWeek = max(1, min(currentWeek, resolvedTotalWeeks))
        switch range {
        case .currentWeek:
            return resolvedCurrentWeek ... resolvedCurrentWeek
        case .remainingSemester:
            let startWeek = SemesterConfig.currentWeek(date: referenceDate)
            return min(startWeek, resolvedTotalWeeks) ... resolvedTotalWeeks
        case .fullSemester:
            return 1 ... resolvedTotalWeeks
        case .customWeeks:
            let selectedWeeks = customWeeks ?? resolvedCurrentWeek ... resolvedCurrentWeek
            let startWeek = max(1, min(selectedWeeks.lowerBound, resolvedTotalWeeks))
            let endWeek = max(1, min(selectedWeeks.upperBound, resolvedTotalWeeks))
            return min(startWeek, endWeek) ... max(startWeek, endWeek)
        }
    }

    static func drafts(
        courses: [Course],
        courseNotes: [CourseNote],
        occurrenceNotes: [CourseOccurrenceNote],
        cellReminders: [TimetableCellReminder] = [],
        exams: [ExamArrangement] = [],
        categories: Set<TimetableCalendarExportCategory> = Set(TimetableCalendarExportCategory.allCases),
        range: TimetableCalendarExportRange,
        currentWeek: Int,
        referenceDate: Date = Date(),
        totalWeeks: Int? = nil,
        customWeeks: ClosedRange<Int>? = nil
    ) -> [TimetableCalendarEventDraft] {
        let resolvedTotalWeeks = totalWeeks ?? SemesterConfig.supportedWeeks
        let weekRange = weekRange(
            for: range,
            currentWeek: currentWeek,
            referenceDate: referenceDate,
            totalWeeks: resolvedTotalWeeks,
            customWeeks: customWeeks
        )
        let courseNotesByKey = TimetableNoteResolver.courseNotesByKey(courseNotes)
        let occurrenceNotesByKey = TimetableNoteResolver.occurrenceNotesByKey(occurrenceNotes)

        let courseDrafts = courses.flatMap { course in
            course.weeks
                .filter { weekRange.contains($0) }
                .sorted()
                .compactMap { week in
                    draft(
                        course: course,
                        week: week,
                        courseNotesByKey: courseNotesByKey,
                        occurrenceNotesByKey: occurrenceNotesByKey
                    )
                }
        }

        let reminderDrafts = cellReminders
            .filter { weekRange.contains($0.week) }
            .compactMap(draft(reminder:))

        let examDrafts = exams
            .filter { exam in
                guard let week = exam.timetableProjection?.week else { return false }
                return weekRange.contains(week)
            }
            .compactMap(draft(exam:))

        return (courseDrafts + reminderDrafts + examDrafts)
            .filter { draft in
                TimetableCalendarExportCategory.category(for: draft.occurrenceKey).map(categories.contains) == true
            }
            .sorted { lhs, rhs in
                if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
                return lhs.title < rhs.title
            }
    }

    static func exportInterval(
        for range: TimetableCalendarExportRange,
        currentWeek: Int,
        referenceDate: Date = Date(),
        totalWeeks: Int? = nil,
        customWeeks: ClosedRange<Int>? = nil
    ) -> DateInterval? {
        let resolvedTotalWeeks = totalWeeks ?? SemesterConfig.supportedWeeks
        let weeks = weekRange(
            for: range,
            currentWeek: currentWeek,
            referenceDate: referenceDate,
            totalWeeks: resolvedTotalWeeks,
            customWeeks: customWeeks
        )
        let calendar = UserTimetableSettings.calendar
        let semesterStart = calendar.startOfDay(for: SemesterConfig.startOfSemesterDate)
        guard let start = calendar.date(byAdding: .day, value: (weeks.lowerBound - 1) * 7, to: semesterStart),
              let end = calendar.date(byAdding: .day, value: weeks.upperBound * 7, to: semesterStart),
              end > start
        else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }

    static func occurrenceKey(from url: URL?) -> String? {
        guard let url,
              url.scheme == "leafy",
              url.host == urlHost else {
            return nil
        }

        guard let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath
            .removingPercentEncoding else { return nil }
        let rawValue = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return rawValue.isEmpty ? nil : rawValue
    }

    private static func draft(
        course: Course,
        week: Int,
        courseNotesByKey: [String: String],
        occurrenceNotesByKey: [String: String]
    ) -> TimetableCalendarEventDraft? {
        guard let startDate = TimetablePeriodSchedule.startDate(for: course, week: week),
              let endDate = TimetablePeriodSchedule.endDate(for: course, week: week)
        else {
            return nil
        }

        let occurrenceKey = course.occurrenceKey(week: week)
        let note = TimetableNoteResolver.effectiveNote(
            for: course,
            week: week,
            courseNotesByKey: courseNotesByKey,
            occurrenceNotesByKey: occurrenceNotesByKey
        )
        return TimetableCalendarEventDraft(
            occurrenceKey: occurrenceKey,
            title: displayName(for: course),
            location: "",
            notes: notesText(course: course, week: week, note: note),
            startDate: startDate,
            endDate: endDate,
            url: url(for: occurrenceKey)
        )
    }

    static func cellReminderKey(_ reminder: TimetableCellReminder) -> String {
        cellReminderKeyPrefix + reminder.id.uuidString.lowercased()
    }

    private static func draft(reminder: TimetableCellReminder) -> TimetableCalendarEventDraft? {
        guard let startDate = reminder.resolvedStartDate
        else {
            return nil
        }

        let endDate = reminder.resolvedEndDate.flatMap { $0 > startDate ? $0 : nil }
            ?? startDate.addingTimeInterval(45 * 60)
        let occurrenceKey = cellReminderKey(reminder)
        return TimetableCalendarEventDraft(
            occurrenceKey: occurrenceKey,
            title: reminder.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? L10n.text("日程") : reminder
                .title,
            location: "",
            notes: notesText(reminder: reminder),
            startDate: startDate,
            endDate: endDate,
            url: url(for: occurrenceKey)
        )
    }

    private static func draft(exam: ExamArrangement) -> TimetableCalendarEventDraft? {
        guard let startDate = exam.startsAt else { return nil }
        let endDate = exam.endsAt.flatMap { $0 > startDate ? $0 : nil }
            ?? startDate.addingTimeInterval(90 * 60)
        let occurrenceKey = examKeyPrefix + String(exam.id)
        return TimetableCalendarEventDraft(
            occurrenceKey: occurrenceKey,
            title: L10n.text("考试：%@", exam.name),
            location: "",
            notes: notesText(exam: exam),
            startDate: startDate,
            endDate: endDate,
            url: url(for: occurrenceKey)
        )
    }

    private static func notesText(course: Course, week: Int, note: String?) -> String {
        var lines = [
            L10n.text("教师：%@", course.teacher.isEmpty ? L10n.text("未填写") : course.teacher),
            L10n.text("节次：%@", course.durationTextForShare),
            L10n.text("周次：第 %d 周", week)
        ]

        if let note {
            lines.append(L10n.text("备注：%@", note))
        }

        lines.append(L10n.text("由 %@ 导出", AppBrand.displayName))
        return lines.joined(separator: "\n")
    }

    private static func notesText(reminder: TimetableCellReminder) -> String {
        var lines = [
            L10n.text("类型：日程"),
            L10n.text("周次：第 %d 周", reminder.week),
            reminder.displayStartPeriod == reminder.displayEndPeriod
                ? L10n.text("节次：第 %d 节", reminder.displayStartPeriod)
                : L10n.text("节次：第 %d-%d 节", reminder.displayStartPeriod, reminder.displayEndPeriod)
        ]

        if !reminder.noteText.isEmpty {
            lines.append(L10n.text("备注：%@", reminder.noteText))
        }

        lines.append(L10n.text("由 %@ 导出", AppBrand.displayName))
        return lines.joined(separator: "\n")
    }

    private static func notesText(exam: ExamArrangement) -> String {
        [
            L10n.text("类型：考试"),
            L10n.text("课程编号：%@", exam.courseID.isEmpty ? L10n.text("未填写") : exam.courseID),
            L10n.text("时间：%@ %@-%@", exam.date, exam.start, exam.end),
            L10n.text("由 %@ 导出", AppBrand.displayName)
        ].joined(separator: "\n")
    }

    private static func displayName(for course: Course) -> String {
        let name = course.courseName
            .replacingOccurrences(of: "（必修）", with: "")
            .replacingOccurrences(of: "(必修)", with: "")
            .replacingOccurrences(of: "（辅修）", with: "")
            .replacingOccurrences(of: "(辅修)", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? L10n.text("未命名课程") : name
    }

    static func url(for occurrenceKey: String) -> URL {
        var components = URLComponents()
        components.scheme = "leafy"
        components.host = urlHost
        components.path = "/" + occurrenceKey
        if let identity = ActiveCampusContext.identity {
            components.queryItems = [URLQueryItem(name: "scope", value: identity.scopeKey)]
        }
        return components.url ?? URL(string: "leafy://\(urlHost)")!
    }
}

@MainActor
final class TimetableCalendarExportService {
    private let eventStore: EKEventStore
    private var ledgerKey: String { CampusScopedDefaults.key("calendar.exportedEvents.v1") }

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    func writableCalendars(requestAccess: Bool) async throws -> [TimetableCalendarDestination] {
        let scope = CampusOperationScope()
        if requestAccess {
            try await ensureFullCalendarAccess()
            try scope.check()
        } else {
            let status = EKEventStore.authorizationStatus(for: .event)
            guard status == .fullAccess else { return [] }
        }
        let defaultID = eventStore.defaultCalendarForNewEvents?.calendarIdentifier
        return eventStore.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .map { TimetableCalendarDestination(id: $0.calendarIdentifier, title: $0.title,
                                                source: $0.source.title, isDefault: $0.calendarIdentifier == defaultID)
            }
            .sorted { ($0.source, $0.title, $0.id) < ($1.source, $1.title, $1.id) }
    }

    func export(
        courses: [Course],
        courseNotes: [CourseNote],
        occurrenceNotes: [CourseOccurrenceNote],
        cellReminders: [TimetableCellReminder] = [],
        exams: [ExamArrangement] = [],
        categories: Set<TimetableCalendarExportCategory>,
        calendarIdentifier: String,
        range: TimetableCalendarExportRange,
        currentWeek: Int,
        customWeeks: ClosedRange<Int>? = nil,
        confirmedLegacyEventIDs: Set<String> = []
    ) async throws -> TimetableCalendarExportResult {
        let scope = CampusOperationScope()
        let referenceDate = Date()
        // Snapshot SwiftData values before requesting permission; a school refresh can replace models.
        let drafts = TimetableCalendarExportBuilder.drafts(
            courses: courses, courseNotes: courseNotes, occurrenceNotes: occurrenceNotes,
            cellReminders: cellReminders, exams: exams, categories: categories,
            range: range, currentWeek: currentWeek, referenceDate: referenceDate, customWeeks: customWeeks
        )
        guard let selection = selection(categories: categories, range: range, currentWeek: currentWeek,
                                        referenceDate: referenceDate, customWeeks: customWeeks,
                                        draftKeys: Set(drafts.map(\.occurrenceKey))) else {
            return TimetableCalendarExportResult(created: 0, updated: 0, removed: 0)
        }
        try await ensureFullCalendarAccess()
        try scope.check()
        guard let calendar = eventStore.calendar(withIdentifier: calendarIdentifier),
              calendar.allowsContentModifications else { throw TimetableCalendarExportError.calendarUnavailable }
        var ledger = UserDefaults.standard.dictionary(forKey: ledgerKey) as? [String: String] ?? [:]
        let events = existingEvents(selection: selection, ledger: ledger)
        let plan = try TimetableCalendarReconciliation.plan(
            events: events.map(snapshot), selection: selection, scopeKey: ActiveCampusContext.identity?.scopeKey,
            confirmedLegacyEventIDs: confirmedLegacyEventIDs
        )
        let byIdentifier = Dictionary(
            events.map { ($0.calendarItemIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var saved: [(String, EKEvent)] = []
        var created = 0, updated = 0
        do {
            for draft in drafts {
                let existing = plan.retainedByKey[draft.occurrenceKey].flatMap { byIdentifier[$0] }
                let event = existing ?? EKEvent(eventStore: eventStore)
                if existing == nil { created += 1 } else { updated += 1 }
                Self.apply(draft, to: event, calendar: calendar)
                try eventStore.save(event, span: .thisEvent, commit: false)
                saved.append((draft.occurrenceKey, event))
            }
            for identifier in plan.removedIdentifiers {
                guard let event = byIdentifier[identifier] else { continue }
                try eventStore.remove(event, span: .thisEvent, commit: false)
                if let key = TimetableCalendarExportBuilder.occurrenceKey(from: event.url) {
                    ledger.removeValue(forKey: key)
                }
            }
            try scope.check()
            try eventStore.commit()
            for (key, event) in saved { if let identifier = event.eventIdentifier { ledger[key] = identifier } }
            UserDefaults.standard.set(ledger, forKey: ledgerKey)
            return TimetableCalendarExportResult(
                created: created,
                updated: updated,
                removed: plan.removedIdentifiers.count
            )
        } catch { eventStore.reset(); throw error }
    }

    func exportPersonalSchedules(_ items: [PersonalScheduleExportItem]) async throws -> TimetableCalendarExportResult {
        let scope = CampusOperationScope()
        try await ensureFullCalendarAccess()
        try scope.check()
        guard let calendar = eventStore.defaultCalendarForNewEvents, calendar.allowsContentModifications else {
            throw TimetableCalendarExportError.calendarUnavailable
        }
        let previous = UserDefaults.standard.dictionary(forKey: ledgerKey) as? [String: String] ?? [:]
        var ledger = previous
        var created = 0, updated = 0
        var savedEvents: [(String, EKEvent)] = []
        do {
            for item in items {
                let url = TimetableCalendarExportBuilder.url(for: item.key)
                var existing = previous[item.key].flatMap { eventStore.event(withIdentifier: $0) }
                if existing?.url != url { existing = nil }
                if existing == nil {
                    existing = query(
                        start: item.start.addingTimeInterval(-86400),
                        end: item.start.addingTimeInterval(86400)
                    )
                    .first { $0.url == url }
                }
                if let existing, existing.calendar?.allowsContentModifications != true {
                    throw TimetableCalendarExportError.readOnlyEvents
                }
                let event = existing ?? EKEvent(eventStore: eventStore)
                if existing == nil { created += 1 } else { updated += 1 }
                // Preserve an existing personal schedule's calendar; timetable export has its own explicit destination.
                Self.apply(TimetableCalendarEventDraft(occurrenceKey: item.key, title: item.title,
                                                       location: "", notes: item.note, startDate: item.start,
                                                       endDate: item.end ?? item.start.addingTimeInterval(45 * 60),
                                                       url: url),
                           to: event, calendar: existing?.calendar ?? calendar)
                try eventStore.save(event, span: .thisEvent, commit: false)
                savedEvents.append((item.key, event))
            }
            try scope.check()
            try eventStore.commit()
            for (key, event) in savedEvents { if let identifier = event.eventIdentifier { ledger[key] = identifier } }
            UserDefaults.standard.set(ledger, forKey: ledgerKey)
            return TimetableCalendarExportResult(created: created, updated: updated, removed: 0)
        } catch { eventStore.reset(); throw error }
    }

    func clearExportedCourses(
        cellReminders: [TimetableCellReminder],
        exams: [ExamArrangement],
        categories: Set<TimetableCalendarExportCategory>,
        range: TimetableCalendarExportRange,
        currentWeek: Int,
        customWeeks: ClosedRange<Int>? = nil,
        confirmedLegacyEventIDs: Set<String> = []
    ) async throws -> TimetableCalendarClearResult {
        let scope = CampusOperationScope()
        let referenceDate = Date()
        let drafts = TimetableCalendarExportBuilder.drafts(
            courses: [], courseNotes: [], occurrenceNotes: [], cellReminders: cellReminders, exams: exams,
            categories: categories, range: range, currentWeek: currentWeek,
            referenceDate: referenceDate, customWeeks: customWeeks
        )
        guard let selection = selection(categories: categories, range: range, currentWeek: currentWeek,
                                        referenceDate: referenceDate, customWeeks: customWeeks,
                                        draftKeys: Set(drafts.map(\.occurrenceKey))) else {
            return TimetableCalendarClearResult(removed: 0)
        }
        try await ensureFullCalendarAccess()
        try scope.check()
        var ledger = UserDefaults.standard.dictionary(forKey: ledgerKey) as? [String: String] ?? [:]
        let events = existingEvents(selection: selection, ledger: ledger)
        let plan = try TimetableCalendarReconciliation.plan(
            events: events.map(snapshot), selection: selection, scopeKey: ActiveCampusContext.identity?.scopeKey,
            confirmedLegacyEventIDs: confirmedLegacyEventIDs, clearing: true
        )
        do {
            for event in events where plan.removedIdentifiers.contains(event.calendarItemIdentifier) {
                try eventStore.remove(event, span: .thisEvent, commit: false)
                if let key = TimetableCalendarExportBuilder.occurrenceKey(from: event.url) {
                    ledger.removeValue(forKey: key)
                }
            }
            try scope.check()
            if !plan.removedIdentifiers.isEmpty { try eventStore.commit() }
            UserDefaults.standard.set(ledger, forKey: ledgerKey)
            return TimetableCalendarClearResult(removed: plan.removedIdentifiers.count)
        } catch { eventStore.reset(); throw error }
    }

    private func selection(categories: Set<TimetableCalendarExportCategory>, range: TimetableCalendarExportRange,
                           currentWeek: Int, referenceDate: Date, customWeeks: ClosedRange<Int>?,
                           draftKeys: Set<String>) -> TimetableCalendarSelection? {
        guard !categories.isEmpty,
              let interval = TimetableCalendarExportBuilder.exportInterval(
                  for: range, currentWeek: currentWeek, referenceDate: referenceDate, customWeeks: customWeeks
              ) else { return nil }
        return TimetableCalendarSelection(categories: categories,
                                          weeks: TimetableCalendarExportBuilder.weekRange(
                                              for: range, currentWeek: currentWeek, referenceDate: referenceDate,
                                              customWeeks: customWeeks
                                          ), interval: interval, draftKeys: draftKeys)
    }

    private func snapshot(_ event: EKEvent) -> TimetableCalendarExistingEvent {
        TimetableCalendarExistingEvent(identifier: event.calendarItemIdentifier, url: event.url,
                                       startDate: event.startDate,
                                       isWritable: event.calendar?.allowsContentModifications == true)
    }

    private func existingEvents(selection: TimetableCalendarSelection, ledger: [String: String]) -> [EKEvent] {
        var byIdentifier: [String: EKEvent] = [:]
        func collect(_ events: [EKEvent]) {
            for event in events { byIdentifier[event.calendarItemIdentifier] = event }
        }
        collect(query(start: selection.interval.start, end: selection.interval.end))
        // The ledger also finds selected occurrences that moved outside the new date range.
        var searchedDays = Set<Date>()
        for (key, identifier) in ledger {
            guard let event = eventStore.event(withIdentifier: identifier),
                  TimetableCalendarExportBuilder.occurrenceKey(from: event.url) == key,
                  selection.contains(key: key, startDate: event.startDate) else { continue }
            collect([event])
            if !selection.interval.contains(event.startDate) {
                let day = UserTimetableSettings.calendar.startOfDay(for: event.startDate)
                if searchedDays.insert(day).inserted,
                   let end = UserTimetableSettings.calendar.date(byAdding: .day, value: 1, to: day) {
                    collect(query(start: day, end: end))
                }
            }
        }
        return Array(byIdentifier.values)
    }

    private func query(start: Date, end: Date) -> [EKEvent] {
        eventStore.events(matching: eventStore.predicateForEvents(withStart: start, end: end, calendars: nil))
    }

    private func ensureFullCalendarAccess() async throws {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return
        case .notDetermined:
            let granted = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<
                Bool,
                Error
            >) in
                eventStore.requestFullAccessToEvents { granted, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: granted) }
                }
            }
            guard granted else { throw TimetableCalendarExportError.permissionDenied }
        case .denied, .restricted, .writeOnly:
            throw TimetableCalendarExportError.permissionDenied
        @unknown default:
            throw TimetableCalendarExportError.permissionDenied
        }
    }

    static func apply(_ draft: TimetableCalendarEventDraft, to event: EKEvent, calendar: EKCalendar) {
        event.calendar = calendar
        event.title = draft.title
        event.structuredLocation = nil
        event.location = nil
        event.notes = draft.notes
        event.startDate = draft.startDate
        event.endDate = draft.endDate
        event.url = draft.url
        event.availability = .busy
        event.alarms = nil
    }
}
