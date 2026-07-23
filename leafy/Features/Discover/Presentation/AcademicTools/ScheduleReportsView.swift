import SwiftData
import SwiftUI

struct ScheduleReportsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var settings = ScheduleReportSettingsStore.load()
    @State private var lastAppliedSettings = ScheduleReportSettingsStore.load()
    @State private var operationAlert: LeafyOperationAlert?
    @State private var isApplying = false
    @State private var applyTask: Task<Void, Never>?
    @State private var customEditor: ScheduleReportCustomSetting?

    private var enabledModeCount: Int {
        settings.enabledModes.count + (settings.customReminder.isEnabled ? 1 : 0)
    }

    var body: some View {
        AcademicDetailScrollContainer {
            AcademicDetailCard {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Label("推送", systemImage: "bell.badge")
                        .leafyHeadline()
                    Text("按你选择的时间发送本机报告。首版只使用本地通知，不上传课表、考试或本地日程。")
                        .leafyBody()
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            AcademicDetailSectionHeader(title: "提醒模式")
            ForEach(ScheduleReportMode.builtInCases) { mode in
                ScheduleReportModeCard(
                    mode: mode,
                    setting: binding(for: mode),
                    time: dateBinding(for: mode)
                )
            }

            AcademicDetailSectionHeader(title: "自定义")
            ScheduleReportCustomCard(
                setting: settings.customReminder,
                onToggle: toggleCustomReminder,
                onEdit: openCustomEditor
            )

            AcademicDetailCard {
                Label(
                    isApplying ? "正在更新推送" : "已开启 \(enabledModeCount) 个提醒",
                    systemImage: isApplying ? "arrow.triangle.2.circlepath" : "checkmark.circle"
                )
                .leafySubheadline()
                .foregroundStyle(AppTheme.secondaryText)
            }

            AcademicDetailFooterText(text: "天气服务将切换到 WeatherKit，但首版报告通知暂不展示天气。")
        }
        .navigationTitle("推送")
        .leafyInlineNavigationTitle()
        .onAppear {
            settings = ScheduleReportSettingsStore.load()
            settings.deriveEnabledState()
            lastAppliedSettings = settings
        }
        .onDisappear { applyTask?.cancel() }
        .task(id: customExpirationTaskID) {
            await expireCustomReminderWhenNeeded()
        }
        .sheet(item: $customEditor) { setting in
            ScheduleReportCustomEditor(setting: setting) { savedSetting in
                var updated = settings
                updated.customReminder = savedSetting
                updated.deriveEnabledState()
                apply(updated, debounce: false)
            }
        }
        .leafyOperationAlert($operationAlert)
    }

    private var customExpirationTaskID: String {
        let timestamp = settings.customReminder.fireDate?.timeIntervalSinceReferenceDate ?? 0
        return "\(settings.customReminder.isEnabled)-\(timestamp)"
    }

    private func openCustomEditor() {
        customEditor = settings.customReminder
    }

    private func toggleCustomReminder(_ isEnabled: Bool) {
        let reminder = settings.customReminder
        guard reminder.isConfigured,
              let fireDate = reminder.fireDate,
              fireDate > Date()
        else {
            if isEnabled {
                openCustomEditor()
            }
            return
        }

        var updated = settings
        updated.customReminder.isEnabled = isEnabled
        updated.deriveEnabledState()
        apply(updated, debounce: false)
    }

    @MainActor
    private func expireCustomReminderWhenNeeded() async {
        guard settings.customReminder.isEnabled,
              let fireDate = settings.customReminder.fireDate
        else { return }

        let delay = fireDate.timeIntervalSinceNow
        if delay > 0 {
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
        }
        guard !Task.isCancelled,
              settings.customReminder.fireDate == fireDate,
              fireDate <= Date()
        else { return }

        var updated = settings
        updated.customReminder.isEnabled = false
        updated.deriveEnabledState()
        apply(updated, debounce: false)
    }

    private func binding(for mode: ScheduleReportMode) -> Binding<ScheduleReportModeSetting> {
        Binding {
            settings.setting(for: mode)
        } set: { newValue in
            var updated = settings
            updated.set(newValue, for: mode)
            updated.deriveEnabledState()
            apply(updated, debounce: false)
        }
    }

    private func dateBinding(for mode: ScheduleReportMode) -> Binding<Date> {
        Binding {
            let setting = settings.setting(for: mode)
            var components = DateComponents()
            components.hour = setting.hour
            components.minute = setting.minute
            return Calendar.current.date(from: components) ?? Date()
        } set: { newValue in
            var updated = settings
            var setting = updated.setting(for: mode)
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            setting.hour = components.hour ?? mode.defaultHour
            setting.minute = components.minute ?? mode.defaultMinute
            updated.set(setting, for: mode)
            updated.deriveEnabledState()
            apply(updated, debounce: true)
        }
    }

    @MainActor
    private func apply(_ updatedSettings: ScheduleReportSettings, debounce: Bool) {
        settings = updatedSettings
        applyTask?.cancel()
        applyTask = Task { @MainActor in
            if debounce {
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            isApplying = true
            do {
                let input = ScheduleReportDataSource.input(modelContext: modelContext)
                let applied = try await ScheduleReportNotificationManager.updateNotifications(
                    settings: updatedSettings,
                    input: input
                )
                guard !Task.isCancelled else { return }
                settings = applied
                lastAppliedSettings = applied
                ScheduleReportSettingsStore.save(applied)
            } catch is CancellationError {
                return
            } catch {
                settings = lastAppliedSettings
                if let restored = try? await ScheduleReportNotificationManager.updateNotifications(
                    settings: lastAppliedSettings,
                    input: ScheduleReportDataSource.input(modelContext: modelContext)
                ) {
                    lastAppliedSettings = restored
                    settings = restored
                    ScheduleReportSettingsStore.save(restored)
                } else {
                    ScheduleReportSettingsStore.save(lastAppliedSettings)
                }
                operationAlert = .failure(error.localizedDescription)
            }
            isApplying = false
        }
    }
}

private struct ScheduleReportCustomCard: View {
    let setting: ScheduleReportCustomSetting
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void

    var body: some View {
        AcademicDetailCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Toggle(
                    isOn: Binding(
                        get: { setting.isEnabled },
                        set: onToggle
                    )
                ) {
                    Label("自定义提醒", systemImage: "bell.and.waves.left.and.right")
                        .font(.headline)
                }

                if setting.isConfigured {
                    Text(setting.trimmedTitle)
                        .leafyHeadline()
                    Text(setting.resolvedBody)
                        .leafySubheadline()
                        .foregroundStyle(AppTheme.secondaryText)
                    if let fireDate = setting.fireDate {
                        Label(
                            fireDate.formatted(date: .abbreviated, time: .shortened),
                            systemImage: "calendar.badge.clock"
                        )
                        .leafySubheadline()
                        .foregroundStyle(AppTheme.secondaryText)

                        if fireDate <= Date() {
                            Text("提醒时间已过，请编辑后重新开启。")
                                .font(.caption)
                                .foregroundStyle(AppTheme.warning)
                        }
                    }
                } else {
                    Text("设置想提醒的事项和任意未来时间，只提醒一次。")
                        .leafySubheadline()
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Button(action: onEdit) {
                    Label(setting.isConfigured ? "编辑提醒" : "添加提醒", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

private struct ScheduleReportCustomEditor: View {
    @Environment(\.dismiss) private var dismiss

    let setting: ScheduleReportCustomSetting
    let onSave: (ScheduleReportCustomSetting) -> Void

    @State private var title: String
    @State private var bodyText: String
    @State private var fireDate: Date

    init(
        setting: ScheduleReportCustomSetting,
        onSave: @escaping (ScheduleReportCustomSetting) -> Void
    ) {
        self.setting = setting
        self.onSave = onSave
        let earliestDate = Date().addingTimeInterval(60)
        _title = State(initialValue: setting.title)
        _bodyText = State(initialValue: setting.body)
        _fireDate = State(initialValue: max(setting.fireDate ?? earliestDate, earliestDate))
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && fireDate > Date()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("标题（必填）", text: $title)
                    TextField("正文（可选）", text: $bodyText, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("提醒内容")
                }

                Section {
                    DatePicker(
                        "日期与时间",
                        selection: $fireDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                } header: {
                    Text("提醒时间")
                } footer: {
                    Text("自定义提醒只发送一次。正文留空时将使用默认提示。")
                }
            }
            .navigationTitle(setting.isConfigured ? "编辑自定义提醒" : "添加自定义提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存并开启") {
                        onSave(
                            ScheduleReportCustomSetting(
                                isEnabled: true,
                                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                body: bodyText.trimmingCharacters(in: .whitespacesAndNewlines),
                                fireDate: fireDate
                            )
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

private struct ScheduleReportModeCard: View {
    let mode: ScheduleReportMode
    @Binding var setting: ScheduleReportModeSetting
    @Binding var time: Date

    var body: some View {
        AcademicDetailCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Toggle(isOn: $setting.isEnabled) {
                    HStack(spacing: 8) {
                        Image(systemName: mode.systemImage)
                            .frame(width: 28, alignment: .leading)
                        Text(mode.title)
                    }
                    .font(.headline)
                }
                Text(mode.subtitle)
                    .leafySubheadline()
                    .foregroundStyle(AppTheme.secondaryText)

                if setting.isEnabled {
                    DatePicker("推送时间", selection: $time, displayedComponents: .hourAndMinute)
                }
            }
        }
    }
}
