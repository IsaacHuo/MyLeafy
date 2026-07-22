import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ManualCourseEditorItem: Identifiable, Hashable {
    let id = UUID()
}

struct ManualCourseEditorSheet: View {
    let item: ManualCourseEditorItem
    let onSave: (Course) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var courseName = ""
    @State private var teacher = ""
    @State private var location = ""
    @State private var classInfo = ""
    @State private var dayOfWeek = 1
    @State private var startWeek = max(1, min(SemesterConfig.currentWeek(), SemesterConfig.supportedWeeks))
    @State private var endWeek = max(1, min(SemesterConfig.currentWeek(), SemesterConfig.supportedWeeks))
    @State private var startPeriod = 1
    @State private var endPeriod = 2

    private var isSaveDisabled: Bool {
        courseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || startWeek > endWeek
            || startPeriod > endPeriod
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("课程名称", text: $courseName)
                    TextField("教师", text: $teacher)
                    TextField("地点", text: $location)
                    TextField("班级或备注", text: $classInfo)
                } footer: {
                    Text("课程只保存在当前通用学校账号的本机课表中。")
                }

                Section("上课时间") {
                    Picker("星期", selection: $dayOfWeek) {
                        ForEach(1...7, id: \.self) { day in
                            Text(dayTitle(day)).tag(day)
                        }
                    }

                    Picker("开始周", selection: $startWeek) {
                        ForEach(1...SemesterConfig.supportedWeeks, id: \.self) { week in
                            Text("第 \(week) 周").tag(week)
                        }
                    }

                    Picker("结束周", selection: $endWeek) {
                        ForEach(1...SemesterConfig.supportedWeeks, id: \.self) { week in
                            Text("第 \(week) 周").tag(week)
                        }
                    }

                    Picker("开始节次", selection: $startPeriod) {
                        ForEach(1...13, id: \.self) { period in
                            Text(periodTitle(period)).tag(period)
                        }
                    }

                    Picker("结束节次", selection: $endPeriod) {
                        ForEach(1...13, id: \.self) { period in
                            Text(periodTitle(period)).tag(period)
                        }
                    }
                }
            }
            .navigationTitle("添加课程")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(isSaveDisabled)
                }
            }
            .onChange(of: startWeek) { _, newValue in
                if endWeek < newValue {
                    endWeek = newValue
                }
            }
            .onChange(of: startPeriod) { _, newValue in
                if endPeriod < newValue {
                    endPeriod = newValue
                }
            }
        }
    }

    private func save() {
        let trimmedName = courseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(
            Course(
                courseName: trimmedName,
                teacher: teacher.trimmingCharacters(in: .whitespacesAndNewlines),
                classInfo: classInfo.trimmingCharacters(in: .whitespacesAndNewlines),
                room: trimmedLocation,
                location: trimmedLocation,
                dayOfWeek: dayOfWeek,
                weeks: Array(startWeek...endWeek),
                duration: Array(startPeriod...endPeriod)
            )
        )
        dismiss()
    }

    private func dayTitle(_ day: Int) -> String {
        let titles = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        guard titles.indices.contains(day - 1) else { return "周\(day)" }
        return titles[day - 1]
    }

    private func periodTitle(_ period: Int) -> String {
        guard let slot = TimetablePeriodSchedule.slot(for: period) else {
            return "第 \(period) 节"
        }
        return "第 \(period) 节 \(slot.startText)-\(slot.endText)"
    }
}

struct TimetableProcessingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference
    @Query private var courses: [Course]
    @Query private var cellReminders: [TimetableCellReminder]
    @Query private var courseNotes: [CourseNote]
    @Query private var occurrenceNotes: [CourseOccurrenceNote]
    @Query private var courseReminderSettings: [CourseReminderSetting]

    @State private var editingManualCourse: ManualCourseEditorItem?
    @State private var isTimetableImportPresented = false
    @State private var isTimetableImportGuidePresented = false
    @State private var isClearConfirmationPresented = false
    @State private var operationAlert: LeafyOperationAlert?

    private var isCustomCampus: Bool {
        ActiveCampusContext.identity?.isCustom == true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.card) {
                AcademicDetailCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("课表处理", systemImage: "slider.horizontal.3")
                            .leafyHeadline()
                        Text(isCustomCampus ? "在这里集中完成手动添加课程、CSV 导入，以及清空当前通用入口本机课表数据。" : "此页面只处理通用入口的本机课表。北京林业大学入口请继续使用课表页右上角刷新教务课表。")
                            .leafyBody()
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }

                if isCustomCampus {
                    AcademicDetailSectionHeader(title: "添加课程")
                    AcademicDetailCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("手动补录一两门课时更快。")
                                .leafyBody()
                                .foregroundStyle(AppTheme.secondaryText)

                            Button {
                                editingManualCourse = ManualCourseEditorItem()
                            } label: {
                                Label("添加课程", systemImage: "plus")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.accent(for: themeColorPreference))
                        }
                    }

                    AcademicDetailSectionHeader(title: "导入文件")
                    AcademicDetailCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("适合已有 CSV 表格的情况。导入会替换当前通用入口本机课表。")
                                .leafyBody()
                                .foregroundStyle(AppTheme.secondaryText)

                            Button {
                                isTimetableImportGuidePresented = true
                            } label: {
                                Label("导入 CSV", systemImage: "tray.and.arrow.down")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    AcademicDetailSectionHeader(title: "清空课表")
                    AcademicDetailCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("会清空当前通用入口本机课表、备注、提醒和相关缓存；不影响北京林业大学入口。")
                                .leafyBody()
                                .foregroundStyle(AppTheme.secondaryText)

                            Button(role: .destructive) {
                                isClearConfirmationPresented = true
                            } label: {
                                Label("清空当前本机课表数据", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } else {
                    AcademicDetailCard {
                        Text("为了避免误操作，这里的添加、导入和清空操作已关闭。")
                            .leafyBody()
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }

                AcademicDetailFooterText(text: "北京林业大学入口不受影响；这里仅处理通用入口的本机课表数据。")
            }
            .padding(AppSpacing.page)
        }
        .background(LeafyPageBackground())
        .navigationTitle("课表处理")
        .leafyInlineNavigationTitle()
        .sheet(item: $editingManualCourse) { item in
            ManualCourseEditorSheet(item: item) { course in
                saveManualCourse(course)
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $isTimetableImportGuidePresented) {
            TimetableCSVImportGuideSheet {
                isTimetableImportGuidePresented = false
                isTimetableImportPresented = true
            }
            .presentationDetents([.medium, .large])
        }
        .fileImporter(
            isPresented: $isTimetableImportPresented,
            allowedContentTypes: [.commaSeparatedText, .plainText, .text]
        ) { result in
            handleTimetableImport(result)
        }
        .confirmationDialog(
            "清空当前通用入口本机课表？",
            isPresented: $isClearConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("清空本机课表数据", role: .destructive) {
                clearCurrentCustomTimetableData()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会清空当前通用入口本机课表、备注、提醒和相关缓存；不会影响北京林业大学入口。")
        }
        .leafyOperationAlert($operationAlert)
    }

    @MainActor
    private func saveManualCourse(_ course: Course) {
        guard isCustomCampus else {
            operationAlert = .failure("此操作仅用于通用入口。")
            return
        }

        modelContext.insert(course)
        do {
            try modelContext.save()
            TimetableCacheMetadata.lastSyncAt = Date()
            TimetableCacheMetadata.lastFailureMessage = nil
            SchoolDataRefreshNotifier.post(.timetable)
            publishWidgetSnapshot()
            operationAlert = .success(L10n.text("课程已添加。", language: leafyLanguage))
        } catch {
            operationAlert = .failure(error.localizedDescription)
        }
    }

    @MainActor
    private func handleTimetableImport(_ result: Result<URL, Error>) {
        guard isCustomCampus else {
            operationAlert = .failure("此操作仅用于通用入口。")
            return
        }

        do {
            let url = try result.get()
            let count = try CustomCampusImportService.importTimetable(
                from: url,
                existingCourses: courses,
                modelContext: modelContext
            )
            TimetableCacheMetadata.lastFailureMessage = nil
            SchoolDataRefreshNotifier.post(.timetable)
            publishWidgetSnapshot()
            operationAlert = .success(L10n.text("已导入 %d 门课程。", language: leafyLanguage, count))
        } catch {
            operationAlert = .failure(error.localizedDescription)
        }
    }

    @MainActor
    private func clearCurrentCustomTimetableData() {
        guard isCustomCampus else {
            operationAlert = .failure("此操作仅用于通用入口。")
            return
        }

        TimetableNotificationManager.cancelAllCourseReminders(courses: courses)
        TimetableNotificationManager.cancelAllCellReminders(cellReminders)
        ScheduleReportNotificationManager.clearScheduledNotifications()

        for course in courses {
            modelContext.delete(course)
        }
        for note in courseNotes {
            modelContext.delete(note)
        }
        for note in occurrenceNotes {
            modelContext.delete(note)
        }
        for reminder in courseReminderSettings {
            modelContext.delete(reminder)
        }
        for reminder in cellReminders {
            modelContext.delete(reminder)
        }

        do {
            try modelContext.save()
            SchoolDataCache.clearDiscoverCaches()
            TimetableCacheMetadata.clear()
            CustomScheduleStore.clear()
            SchoolDataRefreshNotifier.post(.all)
            publishWidgetSnapshot()
            operationAlert = .success("当前通用入口本机课表数据已清空。")
        } catch {
            operationAlert = .failure(error.localizedDescription)
        }
    }

    private func publishWidgetSnapshot() {
        LeafyWidgetSnapshotBuilder.publish(
            courses: courses,
            notes: courseNotes,
            occurrenceNotes: occurrenceNotes,
            reminders: courseReminderSettings,
            cellReminders: cellReminders,
            isAuthenticated: true
        )
    }
}

struct TimetableCSVImportGuideSheet: View {
    let onImport: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    AcademicDetailCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("批量导入课表", systemImage: "tray.and.arrow.down")
                                .leafyHeadline()
                            Text("适合已经从学校系统整理出表格的情况。导入会替换当前课表；如果只是补一两门课，直接手动添加更快。")
                                .leafyBody()
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }

                    AcademicDetailCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("CSV 字段")
                                .leafyHeadline()
                            Text(CustomCampusCSVParser.timetableColumns.joined(separator: ", "))
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                            Text("dayOfWeek 使用 1-7 表示周一到周日；weeks 和 duration 支持 1-16、1,3,5 这类写法。")
                                .microCaption()
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }

                    AcademicDetailCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("示例")
                                .leafyHeadline()
                            Text(Self.sampleCSV)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                        }
                    }
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle("导入说明")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("选择文件") {
                        onImport()
                    }
                }
            }
        }
    }

    private static let sampleCSV = """
courseName,teacher,classInfo,room,location,dayOfWeek,weeks,duration
高等数学,王老师,1班,A101,A101,1,1-16,1-2
"""
}
