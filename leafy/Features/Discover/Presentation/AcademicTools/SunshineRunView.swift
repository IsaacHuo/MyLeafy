import Combine
import QuickLook
import Supabase
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct SunshineRunView: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    @State private var records = SunshineRunStore.loadRecords()
    @State private var reminderSettings = SunshineRunStore.loadReminderSettings()
    @State private var ruleSettings = SunshineRunStore.loadRuleSettings()
    @State private var showingBackfillSheet = false
    @State private var operationAlert: LeafyOperationAlert?

    private var summary: SunshineRunProgressSummary {
        SunshineRunPlanner.progressSummary(
            records: records,
            excludedWeeks: ruleSettings.excludedWeeks,
            weeksPerPeriod: ruleSettings.weeksPerPeriod,
            totalTarget: ruleSettings.totalTarget
        )
    }

    private var progresses: [SunshineRunPeriodProgress] {
        SunshineRunPlanner.periodProgresses(
            records: records,
            excludedWeeks: ruleSettings.excludedWeeks,
            weeksPerPeriod: ruleSettings.weeksPerPeriod,
            periodTarget: ruleSettings.periodTarget
        )
    }

    private var currentProgress: SunshineRunPeriodProgress? {
        guard let currentPeriod = SunshineRunPlanner.currentPeriod(
            excludedWeeks: ruleSettings.excludedWeeks,
            weeksPerPeriod: ruleSettings.weeksPerPeriod
        ) else { return progresses.first }
        return progresses.first { $0.period.startWeek == currentPeriod.startWeek }
    }

    private var hasTodayRecord: Bool {
        SunshineRunPlanner.containsRecord(on: Date(), in: records)
    }

    var body: some View {
        AcademicDetailScrollContainer {
            SunshineRunSummaryCard(summary: summary, totalTarget: ruleSettings.totalTarget)

            if let currentProgress {
                SunshineRunCurrentPeriodCard(
                    progress: currentProgress,
                    hasTodayRecord: hasTodayRecord,
                    onToggleToday: toggleTodayRecord
                )
            }

            AcademicDetailCard {
                Button {
                    showingBackfillSheet = true
                } label: {
                    Label("补记一次", systemImage: "calendar.badge.plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
            }

            SunshineRunRuleSettingsCard(settings: $ruleSettings) {
                saveRuleSettings()
            }

            SunshineRunReminderCard(
                settings: $reminderSettings,
                onSave: saveReminderSettings
            )

            AcademicDetailSectionHeader(title: "\(ruleSettings.weeksPerPeriod) 周周期")
            ForEach(progresses) { progress in
                AcademicDetailCard {
                    SunshineRunPeriodRow(progress: progress)
                }
            }

            AcademicDetailFooterText(text: "阳光长跑记录、规则和提醒仅保存在当前设备，不会连接学校系统。")
        }
        .navigationTitle("阳光长跑")
        .leafyInlineNavigationTitle()
        .sheet(isPresented: $showingBackfillSheet) {
            SunshineRunBackfillSheet { date in
                addRecord(on: date, successMessage: "已补记阳光长跑。")
            }
        }
        .onAppear {
            records = SunshineRunStore.loadRecords()
            reminderSettings = SunshineRunStore.loadReminderSettings()
            ruleSettings = SunshineRunStore.loadRuleSettings()
        }
        .leafyOperationAlert($operationAlert)
    }

    private func toggleTodayRecord() {
        if hasTodayRecord {
            removeRecord(on: Date(), successMessage: "已撤销今日打卡。")
        } else {
            addRecord(on: Date(), successMessage: "已记录今日阳光长跑。")
        }
    }

    private func addRecord(on date: Date, successMessage: String) {
        let calendar = Calendar.current
        guard !SunshineRunPlanner.isExcludedDate(date, excludedWeeks: ruleSettings.excludedWeeks, calendar: calendar) else {
            operationAlert = .failure("假期周无需打卡，阳光长跑周期已跳过这一周。")
            return
        }
        guard SunshineRunPlanner.period(
            for: date,
            excludedWeeks: ruleSettings.excludedWeeks,
            weeksPerPeriod: ruleSettings.weeksPerPeriod,
            calendar: calendar
        ) != nil else {
            operationAlert = .failure("只能补记本学期内的阳光长跑。")
            return
        }
        guard !SunshineRunPlanner.containsRecord(on: date, in: records, calendar: calendar) else {
            operationAlert = .failure("这一天已经记录过阳光长跑。")
            return
        }

        records.append(SunshineRunRecord(date: date, calendar: calendar))
        persistRecords(successMessage: successMessage)
    }

    private func removeRecord(on date: Date, successMessage: String) {
        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: date)
        records.removeAll { calendar.startOfDay(for: $0.date) == targetDay }
        persistRecords(successMessage: successMessage)
    }

    private func persistRecords(successMessage: String) {
        records = SunshineRunPlanner.normalizedRecords(records)
        SunshineRunStore.saveRecords(records)
        Task { await updateNotifications(successMessage: successMessage) }
    }

    private func saveReminderSettings() {
        reminderSettings.selectedWeekdays = SunshineRunReminderSettings.normalizedWeekdays(reminderSettings.selectedWeekdays)
        SunshineRunStore.saveReminderSettings(reminderSettings)
        Task { await updateNotifications(successMessage: reminderSettings.isEnabled ? "阳光长跑提醒已保存。" : "阳光长跑提醒已关闭。") }
    }

    private func saveRuleSettings() {
        ruleSettings = SunshineRunRuleSettings(
            totalTarget: ruleSettings.totalTarget,
            weeksPerPeriod: ruleSettings.weeksPerPeriod,
            periodTarget: ruleSettings.periodTarget,
            skipsExcludedWeeks: ruleSettings.skipsExcludedWeeks
        )
        SunshineRunStore.saveRuleSettings(ruleSettings)
        Task { await updateNotifications(successMessage: "阳光长跑规则已保存。") }
    }

    @MainActor
    private func updateNotifications(successMessage: String) async {
        do {
            let updatedSettings = try await SunshineRunNotificationManager.updateNotifications(
                settings: reminderSettings,
                records: records,
                rules: ruleSettings
            )
            reminderSettings = updatedSettings
            SunshineRunStore.saveReminderSettings(updatedSettings)
            operationAlert = .success(L10n.text(successMessage, language: leafyLanguage))
        } catch {
            var disabledSettings = reminderSettings
            disabledSettings.isEnabled = false
            disabledSettings.scheduledNotificationIDs = []
            reminderSettings = disabledSettings
            SunshineRunStore.saveReminderSettings(disabledSettings)
            operationAlert = .failure(error.localizedDescription)
        }
    }
}

private struct SunshineRunSummaryCard: View {
    let summary: SunshineRunProgressSummary
    let totalTarget: Int

    private var progressValue: Double {
        Double(summary.cappedTotalCount) / Double(max(totalTarget, 1))
    }

    var body: some View {
        AcademicDetailCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(summary.cappedTotalCount) / \(totalTarget)")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)
                    Spacer()
                    Text(summary.isFullScoreReached ? "满分目标已完成" : "还差 \(summary.remainingForFullScore) 次")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(summary.isFullScoreReached ? AppTheme.accentEmphasis : AppTheme.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.softFill, in: Capsule())
                }

                ProgressView(value: progressValue)
                    .tint(AppTheme.accent)

                Text("有效记录 \(summary.totalCount) 次；目标按当前规则封顶展示。")
                    .leafySubheadline()
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }
}

private struct SunshineRunCurrentPeriodCard: View {
    let progress: SunshineRunPeriodProgress
    let hasTodayRecord: Bool
    let onToggleToday: () -> Void

    var body: some View {
        AcademicDetailCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Text("当前周期")
                    .leafySubheadline()
                    .foregroundStyle(AppTheme.secondaryText)
                Text(progress.period.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.primaryText)
                Text("本组已跑 \(progress.count) 次，目标 \(progress.periodTarget) 次。")
                    .leafyBody()
                    .foregroundStyle(AppTheme.secondaryText)

                Button {
                    onToggleToday()
                } label: {
                    Label(hasTodayRecord ? "撤销今日打卡" : "今天已跑", systemImage: hasTodayRecord ? "arrow.uturn.backward.circle" : "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct SunshineRunRuleSettingsCard: View {
    @Binding var settings: SunshineRunRuleSettings
    let onSave: () -> Void

    var body: some View {
        AcademicDetailCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Text("规则设置")
                    .leafyHeadline()

                Stepper(value: $settings.totalTarget, in: 1...200) {
                    Text("总目标 \(settings.totalTarget) 次")
                }

                Stepper(value: $settings.weeksPerPeriod, in: 1...8) {
                    Text("每 \(settings.weeksPerPeriod) 周为一组")
                }

                Stepper(value: $settings.periodTarget, in: 1...30) {
                    Text("每组目标 \(settings.periodTarget) 次")
                }

                Toggle("跳过学期假期周", isOn: $settings.skipsExcludedWeeks)

                Button("保存规则") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)

                Text("默认规则仍是 34 次、两周一组、每组 4 次；通用学校可按自己的体育要求调整。")
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }
}

private struct SunshineRunReminderCard: View {
    @Binding var settings: SunshineRunReminderSettings
    let onSave: () -> Void

    private let weekdays: [(value: Int, title: String)] = [
        (1, "周一"), (2, "周二"), (3, "周三"), (4, "周四"), (5, "周五"), (6, "周六"), (7, "周日")
    ]

    private var reminderDate: Binding<Date> {
        Binding {
            var components = DateComponents()
            components.hour = settings.hour
            components.minute = settings.minute
            return Calendar.current.date(from: components) ?? Date()
        } set: { newValue in
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            settings.hour = components.hour ?? 20
            settings.minute = components.minute ?? 0
        }
    }

    var body: some View {
        AcademicDetailCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Toggle("开启本地提醒", isOn: $settings.isEnabled)
                    .font(.headline)

                if settings.isEnabled {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Text("提醒星期")
                            .leafySubheadline()
                            .foregroundStyle(AppTheme.secondaryText)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], alignment: .leading, spacing: 8) {
                            ForEach(weekdays, id: \.value) { weekday in
                                Button {
                                    toggleWeekday(weekday.value)
                                } label: {
                                    Text(weekday.title)
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .foregroundStyle(settings.normalizedSelectedWeekdays.contains(weekday.value) ? AppTheme.textOnAccent : AppTheme.primaryText)
                                        .background(
                                            settings.normalizedSelectedWeekdays.contains(weekday.value) ? AppTheme.accent : AppTheme.softFill,
                                            in: Capsule()
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        DatePicker("提醒时间", selection: reminderDate, displayedComponents: .hourAndMinute)
                    }
                } else {
                    Text("默认不提醒。开启后会按你选择的星期和时间安排本地通知。")
                        .leafySubheadline()
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Button("保存提醒设置") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .disabled(settings.isEnabled && settings.normalizedSelectedWeekdays.isEmpty)
            }
        }
    }

    private func toggleWeekday(_ weekday: Int) {
        var selected = Set(settings.normalizedSelectedWeekdays)
        if selected.contains(weekday) {
            selected.remove(weekday)
        } else {
            selected.insert(weekday)
        }
        settings.selectedWeekdays = selected.sorted()
    }
}

private struct SunshineRunPeriodRow: View {
    let progress: SunshineRunPeriodProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(progress.period.title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.primaryText)
                    Text(dateText)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer()

                Text(progress.isCompleted ? "已达成" : "还差 \(progress.remainingCount) 次")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(progress.isCompleted ? AppTheme.accentEmphasis : AppTheme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(AppTheme.softFill, in: Capsule())
            }

            ProgressView(value: min(Double(progress.count), Double(progress.periodTarget)), total: Double(progress.periodTarget))
                .tint(AppTheme.accent)

            Text("本组 \(progress.count) / \(progress.periodTarget) 次")
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(.vertical, 4)
    }

    private var dateText: String {
        let rangeText = "\(DateFormatters.chineseDay.string(from: progress.period.startDate)) - \(DateFormatters.chineseDay.string(from: progress.period.endDate))"
        return progress.period.hasSkippedWeeks ? "\(rangeText)，已跳过假期周" : rangeText
    }
}

private struct SunshineRunBackfillSheet: View {
    let onSave: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()

    private var dateRange: ClosedRange<Date> {
        let start = SemesterConfig.startOfSemesterDate
        let end = Calendar.current.date(byAdding: .day, value: SemesterConfig.supportedWeeks * 7 - 1, to: start) ?? start
        return start...end
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("跑步日期", selection: $date, in: dateRange, displayedComponents: .date)
                } footer: {
                    Text("补记会按日期自动归入对应的两周周期，假期周不会计入。")
                }
            }
            .navigationTitle("补记阳光长跑")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(date)
                        dismiss()
                    }
                }
            }
        }
    }
}
