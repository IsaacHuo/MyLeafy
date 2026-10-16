import SwiftData
import SwiftUI

struct TimetableSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var courses: [Course]
    @Query private var reminders: [TimetableCellReminder]
    @State private var pendingImport: TimetablePendingImport?
    @State private var draft = UserTimetableSettingsStore.load()
    @State private var chosenDate = UserTimetableSettingsStore.load().firstMonday
    @State private var periodCount = UserTimetableSettingsStore.load().periods.count
    @State private var confirmsMonday = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("学期与开学日期") {
                Stepper("\(draft.academicYear)–\(draft.academicYear + 1) 学年", value: $draft.academicYear, in: 1900...2200)
                Picker("学期", selection: $draft.term) {
                    Text("第一学期").tag(1)
                    Text("第二学期").tag(2)
                }
                DatePicker("第一周的星期一", selection: $chosenDate, displayedComponents: .date)
                Text("固定 20 周。学年和学期用于显示，拉取课表不受这些设置限制。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("节次与作息") {
                if let pendingImport {
                    Text("已暂存最新课表，请补全到第 \(pendingImport.requiredPeriods) 节的作息，保存后导入。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Stepper("每天 \(periodCount) 节", value: $periodCount, in: 1...24)
                ForEach(draft.periods.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 10) {
                        Text("第 \(index + 1) 节")
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) {
                                periodTimeControl(index, end: false)
                                Spacer(minLength: 0)
                                periodTimeControl(index, end: true)
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                periodTimeControl(index, end: false)
                                periodTimeControl(index, end: true)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Text("开始时间须早于结束时间，各节时间不能重叠。新增节次后请核对作息。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .environment(\.calendar, UserTimetableSettings.calendar)
        .environment(\.timeZone, UserTimetableSettings.calendar.timeZone)
        .navigationTitle("课表设置")
        .leafyInlineNavigationTitle()
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("保存", action: prepareSave) } }
        .onAppear {
            if ActiveCampusContext.identity != nil {
                do {
                    pendingImport = try TimetablePendingImportStore.load()
                    periodCount = max(periodCount, pendingImport?.requiredPeriods ?? periodCount)
                } catch { message = error.localizedDescription }
            }
        }
        .onChange(of: periodCount) { _, count in
            if count < draft.periods.count { draft.periods = Array(draft.periods.prefix(count)) }
            while draft.periods.count < count {
                let index = draft.periods.count
                if index < TimetablePeriodSchedule.defaultSlots.count {
                    draft.periods.append(TimetablePeriodSchedule.defaultSlots[index])
                } else {
                    let previous = draft.periods.last!
                    let start = min(previous.endHour * 60 + previous.endMinute + 5, 23 * 60)
                    let end = min(start + 45, 1439)
                    draft.periods.append(.init(period: index + 1, startHour: start / 60, startMinute: start % 60, endHour: end / 60, endMinute: end % 60))
                }
            }
        }
        .confirmationDialog("将以下日期作为第一周的星期一？", isPresented: $confirmsMonday, titleVisibility: .visible) {
            Button(UserTimetableSettings.monday(containing: chosenDate).formatted(date: .abbreviated, time: .omitted)) { save() }
            Button("取消", role: .cancel) {}
        }
        .alert("课表设置", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("知道了", role: .cancel) {}
        } message: { Text(message ?? "") }
    }

    private func periodTimeControl(_ index: Int, end: Bool) -> some View {
        let title: LocalizedStringKey = end ? "结束" : "开始"
        return HStack(spacing: 8) {
            Text(title).fixedSize()
            DatePicker(title, selection: timeBinding(index, end: end), displayedComponents: .hourAndMinute)
                .datePickerStyle(.compact)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel(end ? Text("第 \(index + 1) 节结束时间") : Text("第 \(index + 1) 节开始时间"))
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func timeBinding(_ index: Int, end: Bool) -> Binding<Date> {
        Binding(get: {
            let slot = draft.periods.indices.contains(index) ? draft.periods[index] : TimetablePeriodSchedule.defaultSlots[0]
            return UserTimetableSettings.calendar.date(bySettingHour: end ? slot.endHour : slot.startHour,
                minute: end ? slot.endMinute : slot.startMinute, second: 0, of: draft.firstMonday)!
        }, set: { date in
            guard draft.periods.indices.contains(index) else { return }
            let hour = UserTimetableSettings.calendar.component(.hour, from: date)
            let minute = UserTimetableSettings.calendar.component(.minute, from: date)
            let old = draft.periods[index]
            draft.periods[index] = .init(period: index + 1, startHour: end ? old.startHour : hour,
                startMinute: end ? old.startMinute : minute, endHour: end ? hour : old.endHour,
                endMinute: end ? minute : old.endMinute)
        })
    }
    private func prepareSave() {
        if UserTimetableSettings.calendar.startOfDay(for: chosenDate) != UserTimetableSettings.monday(containing: chosenDate) {
            confirmsMonday = true
        } else { save() }
    }
    private func save() {
        draft.firstMonday = UserTimetableSettings.monday(containing: chosenDate)
        guard draft.isValid else { message = "请检查节次时间：开始须早于结束，各节时间不能重叠。"; return }
        guard !courses.contains(where: { ($0.duration.max() ?? 0) > periodCount }) else {
            message = "已有课程使用了更晚的节次，请保留这些节次。"; return
        }
        guard !reminders.contains(where: { $0.startsAt == nil && ($0.endPeriod ?? $0.period) > periodCount }) else {
            message = "已有格子日程使用了更晚的节次，请保留这些节次。"; return
        }
        let scope = CampusOperationScope()
        do {
            try UserTimetableSettingsStore.save(draft)
            if let pendingImport {
                let saved = try TimetableRefreshUseCase().persist(records: pendingImport.records,
                    existingCourses: courses, modelContext: context, semesterID: pendingImport.sourceSemesterID)
                TimetableCacheMetadata.lastSyncAt = Date()
                TimetableCacheMetadata.lastSyncedSemesterID = pendingImport.sourceSemesterID
                try TimetablePendingImportStore.clear()
                SchoolDataRefreshNotifier.post(.timetable)
                LeafyWidgetSnapshotBuilder.publish(from: context, isAuthenticated: true)
                Task { @MainActor in
                    let warning = await saved.reminders.restore()
                    guard scope.isCurrent else { return }
                    if let warning { TimetableCacheMetadata.lastFailureMessage = warning }
                    if ActiveCampusContext.descriptor.supports(.community), !ReviewDemoMode.isEnabled {
                        _ = await TimetableSharingService.shared.publishExistingSnapshotIfNeeded(courses: saved.sharedCourses)
                    }
                }
            }
            dismiss()
        } catch { message = error.localizedDescription }

    }
}

struct TimetableConfigurationLink: View {
    @State private var settings = UserTimetableSettingsStore.load()

    var body: some View {
        NavigationLink {
            TimetableSettingsView()
        } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text("学期与开学日期")
                            .font(.headline).foregroundStyle(AppTheme.primaryText)
                    } icon: {
                        Image(systemName: "calendar.badge.clock").foregroundStyle(AppTheme.accent)
                    }
                    Text(settings.summary)
                        .font(.subheadline.weight(.medium)).foregroundStyle(AppTheme.secondaryText)
                    Text(settings.firstMonday, format: .dateTime.year().month().day())
                        .font(.subheadline.weight(.medium)).foregroundStyle(AppTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .leafyCardStyle()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("调整学年、学期和第一周的星期一")
        .onReceive(NotificationCenter.default.publisher(for: .semesterRuntimeConfigDidChange)) { _ in
            settings = UserTimetableSettingsStore.load()
        }
    }
}
