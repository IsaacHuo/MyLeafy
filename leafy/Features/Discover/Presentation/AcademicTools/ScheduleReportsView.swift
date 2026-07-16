import SwiftData
import SwiftUI

struct ScheduleReportsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var settings = ScheduleReportSettingsStore.load()
    @State private var lastAppliedSettings = ScheduleReportSettingsStore.load()
    @State private var operationAlert: LeafyOperationAlert?
    @State private var isApplying = false
    @State private var applyTask: Task<Void, Never>?

    private var enabledModeCount: Int {
        settings.enabledModes.count
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
            ForEach(ScheduleReportMode.allCases) { mode in
                ScheduleReportModeCard(
                    mode: mode,
                    setting: binding(for: mode),
                    time: dateBinding(for: mode)
                )
            }

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
        .leafyOperationAlert($operationAlert)
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
