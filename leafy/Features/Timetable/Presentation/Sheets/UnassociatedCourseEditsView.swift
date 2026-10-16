import SwiftData
import SwiftUI

struct UnassociatedCourseEditsView: View {
    @Query private var notes: [CourseNote]
    @Query private var occurrences: [CourseOccurrenceNote]
    @Query private var reminders: [CourseReminderSetting]
    var body: some View {
        List {
            Section("课程备注") {
                ForEach(notes.filter(\.isUnassociated)) { note in
                    NavigationLink(note.sourceCourseTitle.isEmpty ? "课程备注" : note.sourceCourseTitle) {
                        CourseEditRelinkingView(edit: .note(note))
                    }
                }
            }
            Section("课次备注") {
                ForEach(occurrences.filter(\.isUnassociated)) { note in
                    NavigationLink("\(note.sourceCourseTitle) · 第 \(note.week) 周") {
                        CourseEditRelinkingView(edit: .occurrence(note))
                    }
                }
            }
            Section("课程提醒") {
                ForEach(reminders.filter(\.isUnassociated)) { setting in
                    NavigationLink(setting.sourceCourseTitle.isEmpty ? "课程提醒" : setting.sourceCourseTitle) {
                        CourseEditRelinkingView(edit: .reminder(setting))
                    }
                }
            }
            Text("这些个人记录仍保留在本机。重新关联到课程后，提醒才会按最新排课恢复。")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle("待关联备注与提醒")
        .leafyInlineNavigationTitle()
    }
}

private enum CoursePersonalEdit {
    case note(CourseNote), occurrence(CourseOccurrenceNote), reminder(CourseReminderSetting)
    var text: String {
        switch self { case .note(let n): n.text; case .occurrence(let n): n.text; case .reminder: "" }
    }
}

private struct CourseEditRelinkingView: View {
    let edit: CoursePersonalEdit
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var courses: [Course]
    @State private var text: String
    @State private var target = ""
    @State private var week: Int
    @State private var minutes: Int
    @State private var message: String?
    init(edit: CoursePersonalEdit) {
        self.edit = edit
        _text = State(initialValue: edit.text)
        if case .occurrence(let note) = edit { _week = State(initialValue: note.week) } else { _week = State(initialValue: 1) }
        if case .reminder(let setting) = edit { _minutes = State(initialValue: setting.minutesBefore) } else { _minutes = State(initialValue: 0) }
    }
    private var targets: [Course] {
        Dictionary(grouping: courses, by: \.stableCourseKey).compactMap { $0.value.first }
            .sorted { $0.courseName < $1.courseName }
    }
    private func availableWeeks(for key: String) -> [Int] {
        Array(Set(courses.filter { $0.stableCourseKey == key }.flatMap(\.weeks))).sorted()
    }
    var body: some View {
        Form {
            if case .reminder = edit {
                Stepper("提前 \(minutes) 分钟提醒", value: $minutes, in: 0...120, step: 5)
            } else { TextEditor(text: $text).frame(minHeight: 160) }
            Picker("关联课程", selection: $target) {
                Text("暂不关联").tag("")
                ForEach(targets) { course in
                    Text("\(course.courseName) · 周\(course.dayOfWeek) · \(course.duration.map(String.init).joined(separator: ","))节 · \(course.teacher)")
                        .tag(course.stableCourseKey)
                }
            }
            if case .occurrence = edit, let course = targets.first(where: { $0.stableCourseKey == target }) {
                Picker("课次", selection: $week) {
                    ForEach(availableWeeks(for: course.stableCourseKey), id: \.self) { Text("第 \($0) 周").tag($0) }
                }
            }
        }
        .navigationTitle("编辑个人记录")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) } }
        .onChange(of: target) { _, _ in
            if let course = targets.first(where: { $0.stableCourseKey == target }), !availableWeeks(for: course.stableCourseKey).contains(week) { week = availableWeeks(for: course.stableCourseKey).first ?? 1 }
        }
        .alert("无法保存", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("知道了", role: .cancel) {}
        } message: { Text(message ?? "") }
    }
    private func save() {
        let course = targets.first { $0.stableCourseKey == target }
        var undo: () -> Void = {}
        do {
            switch edit {
            case .note(let note):
                if let course, try context.fetch(FetchDescriptor<CourseNote>()).contains(where: { $0.id != note.id && !$0.isUnassociated && $0.courseKey == course.stableCourseKey }) { throw TimetableLocalDataConflict.conflictingRecords(course.courseName) }
                let previous = (note.text, note.updatedAt, note.courseKey, note.isUnassociated)
                undo = { note.text = previous.0; note.updatedAt = previous.1; note.courseKey = previous.2; note.isUnassociated = previous.3 }
                note.text = text; note.updatedAt = Date()
                if let course { note.courseKey = course.stableCourseKey; note.isUnassociated = false }
            case .occurrence(let note):
                if let course, try context.fetch(FetchDescriptor<CourseOccurrenceNote>()).contains(where: { $0.id != note.id && !$0.isUnassociated && $0.courseKey == course.stableCourseKey && $0.week == week }) { throw TimetableLocalDataConflict.conflictingRecords(course.courseName) }
                let previous = (note.text, note.updatedAt, note.courseKey, note.week, note.dayOfWeek, note.occurrenceKey, note.isUnassociated)
                undo = { note.text = previous.0; note.updatedAt = previous.1; note.courseKey = previous.2; note.week = previous.3; note.dayOfWeek = previous.4; note.occurrenceKey = previous.5; note.isUnassociated = previous.6 }
                note.text = text; note.updatedAt = Date()
                if let course {
                    note.courseKey = course.stableCourseKey; note.week = week; note.dayOfWeek = course.dayOfWeek
                    note.occurrenceKey = course.occurrenceKey(week: week); note.isUnassociated = false
                }
            case .reminder(let setting):
                if let course, try context.fetch(FetchDescriptor<CourseReminderSetting>()).contains(where: { $0.id != setting.id && !$0.isUnassociated && $0.courseKey == course.stableCourseKey }) { throw TimetableLocalDataConflict.conflictingRecords(course.courseName) }
                let previous = (setting.minutesBefore, setting.updatedAt, setting.courseKey, setting.anchorPeriod, setting.isUnassociated)
                undo = { setting.minutesBefore = previous.0; setting.updatedAt = previous.1; setting.courseKey = previous.2; setting.anchorPeriod = previous.3; setting.isUnassociated = previous.4 }
                setting.minutesBefore = minutes; setting.updatedAt = Date()
                if let course { setting.courseKey = course.stableCourseKey; setting.anchorPeriod = course.duration.min(); setting.isUnassociated = false }
            }
            try LocalModelSave.save(context, undo: undo)
            NotificationCenter.default.post(name: .semesterRuntimeConfigDidChange, object: nil)
            dismiss()
        } catch { message = error.localizedDescription }
    }
}
