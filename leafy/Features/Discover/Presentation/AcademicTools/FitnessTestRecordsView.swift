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

struct FitnessTestShareSnapshot: Equatable {
    struct Group: Identifiable, Equatable {
        let item: FitnessTestItem
        let records: [Record]

        var id: String { item.rawValue }
    }

    struct Record: Identifiable, Equatable {
        let id: UUID
        let testedAt: Date
        let displayValue: String
        let note: String
    }

    let recordCount: Int
    let latestTestDate: Date?
    let groups: [Group]

    init(records: [FitnessTestRecord]) {
        let sortedRecords = FitnessTestRecordFormatter.sortedRecords(records)
        recordCount = sortedRecords.count
        latestTestDate = sortedRecords.first?.testedAt
        groups = FitnessTestItem.allCases.compactMap { item in
            let itemRecords = sortedRecords
                .filter { $0.item == item }
                .map {
                    Record(
                        id: $0.id,
                        testedAt: $0.testedAt,
                        displayValue: $0.displayValue,
                        note: $0.note.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
            return itemRecords.isEmpty ? nil : Group(item: item, records: itemRecords)
        }
    }

    var itemCount: Int { groups.count }
}

struct FitnessTestRecordsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference
    @Query(sort: \FitnessTestRecord.testedAt, order: .reverse) private var records: [FitnessTestRecord]

    @State private var selectedItem: FitnessTestItem?
    @State private var showingEditor = false
    @State private var editingRecord: FitnessTestRecord?
    @State private var operationAlert: LeafyOperationAlert?
    @State private var sharePreviewImage: UIImage?

    private var sortedRecords: [FitnessTestRecord] {
        FitnessTestRecordFormatter.sortedRecords(records)
    }

    private var filteredRecords: [FitnessTestRecord] {
        guard let selectedItem else { return sortedRecords }
        return sortedRecords.filter { $0.item == selectedItem }
    }

    private var itemFilters: [FitnessTestItem?] {
        [nil] + FitnessTestItem.allCases.map(Optional.some)
    }

    private var latestTestDate: Date? {
        sortedRecords.first?.testedAt
    }

    private var recordedItemCount: Int {
        Set(records.map(\.itemRawValue)).count
    }

    var body: some View {
        AcademicDetailScrollContainer {
            FitnessTestSummaryCard(
                recordCount: records.count,
                latestTestDate: latestTestDate,
                itemCount: recordedItemCount
            )

            HStack {
                AcademicDetailSectionHeader(title: "体测记录")
                Spacer()
                CareerSectionAddButton(title: "添加记录", systemName: "plus") {
                    showingEditor = true
                }
            }

            itemFilter

            if filteredRecords.isEmpty {
                emptyState
            } else {
                AcademicDetailCard {
                    VStack(spacing: 0) {
                        ForEach(Array(filteredRecords.enumerated()), id: \.element.id) { index, record in
                            if index > 0 {
                                AcademicDetailDivider()
                            }
                            FitnessTestRecordRow(
                                record: record,
                                editAction: { editingRecord = record },
                                deleteAction: { delete(record) }
                            )
                        }
                    }
                }
            }

            AcademicDetailFooterText(text: "体测记录仅保存在当前设备，暂不计算体测标准分，也不会连接学校系统。")
        }
        .navigationTitle("体测记录")
        .leafyInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .leafyTrailing) {
                Button {
                    generateSharePreview()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(records.isEmpty)
                .accessibilityLabel(L10n.text("分享全部体测记录", language: leafyLanguage))
            }
        }
        .sheet(isPresented: $showingEditor) {
            FitnessTestRecordEditorView(record: nil) { draft in
                insert(draft)
            }
        }
        .sheet(item: $editingRecord) { record in
            FitnessTestRecordEditorView(record: record) { draft in
                update(record, with: draft)
            }
        }
        .sheet(isPresented: Binding(
            get: { sharePreviewImage != nil },
            set: { if !$0 { sharePreviewImage = nil } }
        )) {
            if let sharePreviewImage {
                FitnessTestSharePreviewSheet(image: sharePreviewImage)
            }
        }
        .leafyOperationAlert($operationAlert)
    }

    private var itemFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(itemFilters, id: \.self) { item in
                    Button {
                        withAnimation(.snappy) {
                            selectedItem = item
                        }
                    } label: {
                        Text(filterTitle(for: item))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectedItem == item ? AppTheme.accentEmphasis(for: themeColorPreference) : AppTheme.secondaryText)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .leafyCapsuleChipSurface(isSelected: selectedItem == item)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(filterTitle(for: item))
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var emptyState: some View {
        AcademicDetailCard {
            ContentUnavailableView {
                Label(emptyTitle, systemImage: "figure.strengthtraining.traditional")
            } description: {
                Text(emptyDescription)
            } actions: {
                Button {
                    showingEditor = true
                } label: {
                    Label("添加记录", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .tint(AppTheme.accent(for: themeColorPreference))
            .padding(.vertical, AppSpacing.compact)
        }
    }

    private var emptyTitle: String {
        selectedItem.map { "还没有\($0.rawValue)记录" } ?? "还没有体测记录"
    }

    private var emptyDescription: String {
        selectedItem == nil ? "添加一次体测项目后，会在这里看到最近成绩和项目趋势。" : "换一个项目筛选，或添加这个项目的新成绩。"
    }

    private func filterTitle(for item: FitnessTestItem?) -> String {
        item?.rawValue ?? "全部"
    }

    private func insert(_ draft: FitnessTestRecordDraft) {
        let now = Date()
        modelContext.insert(FitnessTestRecord(
            testedAt: draft.testedAt,
            itemRawValue: draft.item.rawValue,
            value: draft.value,
            unitRawValue: draft.unit.rawValue,
            note: draft.note,
            createdAt: now,
            updatedAt: now
        ))
        save(successMessage: "体测记录已添加！")
    }

    private func update(_ record: FitnessTestRecord, with draft: FitnessTestRecordDraft) {
        record.testedAt = draft.testedAt
        record.itemRawValue = draft.item.rawValue
        record.value = draft.value
        record.unitRawValue = draft.unit.rawValue
        record.note = draft.note
        record.updatedAt = Date()
        save(successMessage: "体测记录已保存！")
    }

    private func delete(_ record: FitnessTestRecord) {
        modelContext.delete(record)
        save(successMessage: "体测记录已删除！")
    }

    private func save(successMessage: String) {
        do {
            try modelContext.save()
            operationAlert = .success(L10n.text(successMessage, language: leafyLanguage))
        } catch {
            operationAlert = .failure(error.localizedDescription)
        }
    }

    @MainActor
    private func generateSharePreview() {
        let snapshot = FitnessTestShareSnapshot(records: records)
        guard snapshot.recordCount > 0 else { return }

        let content = FitnessTestShareCard(snapshot: snapshot)
            .frame(width: 390)
            .padding(18)
            .background(
                LinearGradient(
                    colors: [
                        AppTheme.background,
                        AppTheme.accentSoft.opacity(0.42),
                        AppTheme.background
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

        let renderer = ImageRenderer(content: content)
        renderer.scale = LeafyImageCodec.displayScale

        guard let image = renderer.leafyPlatformImage else {
            operationAlert = .failure(
                L10n.text("分享图片生成失败，请稍后重试。", language: leafyLanguage)
            )
            return
        }
        sharePreviewImage = image
    }
}

private struct FitnessTestSummaryCard: View {
    let recordCount: Int
    let latestTestDate: Date?
    let itemCount: Int

    var body: some View {
        AcademicDetailCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Label("体测记录", systemImage: "figure.strengthtraining.traditional")
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 10)], alignment: .leading, spacing: 10) {
                    FitnessTestSummaryMetric(title: "记录数", value: "\(recordCount)")
                    FitnessTestSummaryMetric(title: "最近测试", value: latestTestText)
                    FitnessTestSummaryMetric(title: "项目数", value: "\(itemCount)")
                }
            }
        }
    }

    private var latestTestText: String {
        latestTestDate.map { DateFormatters.chineseDay.string(from: $0) } ?? "暂无"
    }
}

private struct FitnessTestSummaryMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .microCaption()
                .foregroundStyle(AppTheme.secondaryText)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.softFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct FitnessTestShareCard: View {
    let snapshot: FitnessTestShareSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(AppTheme.accentEmphasis)
                    .frame(width: 48, height: 48)
                    .background(AppTheme.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("体测记录")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(AppTheme.primaryText)
                    Text("全部本地记录")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            HStack(spacing: 10) {
                summaryMetric(title: "记录数", value: "\(snapshot.recordCount)")
                summaryMetric(title: "项目数", value: "\(snapshot.itemCount)")
                summaryMetric(title: "最近测试", value: latestTestText)
            }

            ForEach(snapshot.groups) { group in
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(group.item.rawValue)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(AppTheme.primaryText)
                        Spacer()
                        Text("\(group.records.count) 条")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .padding(.bottom, 10)

                    ForEach(Array(group.records.enumerated()), id: \.element.id) { index, record in
                        if index > 0 {
                            Divider()
                                .overlay(AppTheme.separator)
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(record.displayValue)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(AppTheme.accentEmphasis)
                                Spacer()
                                Text(DateFormatters.header.string(from: record.testedAt))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(AppTheme.secondaryText)
                            }

                            if !record.note.isEmpty {
                                Text(record.note)
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppTheme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 9)
                    }
                }
                .padding(14)
                .background(
                    AppTheme.cardBackground,
                    in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                )
            }

            Text("记录仅保存在当前设备 · 由 Leafy 生成")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppTheme.tertiaryText)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var latestTestText: String {
        snapshot.latestTestDate.map { DateFormatters.chineseDay.string(from: $0) } ?? "暂无"
    }

    private func summaryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.secondaryText)
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }
}

private struct FitnessTestSharePreviewSheet: View {
    let image: UIImage

    @Environment(\.dismiss) private var dismiss
    @State private var isSharing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.card) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
                        .shadow(color: Color.black.opacity(0.10), radius: 18, x: 0, y: 10)

                    Text("点击右上角分享，可发送到聊天、动态或保存到相册。")
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle("分享预览")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .leafyTrailing) {
                    Button("分享") { isSharing = true }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $isSharing) {
                ShareSheet(activityItems: [image])
            }
        }
    }
}

private struct FitnessTestRecordRow: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let record: FitnessTestRecord
    let editAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.compact) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(L10n.text(record.item.rawValue, language: leafyLanguage))
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)

                    Text(record.displayValue)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.accentEmphasis)
                }

                Text(DateFormatters.header.string(from: record.testedAt))
                    .leafySubheadline()
                    .foregroundStyle(AppTheme.secondaryText)

                if !record.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(record.note)
                        .leafySubheadline()
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: AppSpacing.micro)

            HStack(spacing: AppSpacing.micro) {
                Button(action: editAction) {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.accentEmphasis)
                        .frame(width: 34, height: 34)
                        .background(AppTheme.softFill, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("编辑记录", language: leafyLanguage))

                Button(role: .destructive, action: deleteAction) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.danger)
                        .frame(width: 34, height: 34)
                        .background(AppTheme.danger.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("删除记录", language: leafyLanguage))
            }
        }
        .padding(.vertical, 4)
    }
}

private struct FitnessTestRecordDraft {
    var testedAt: Date
    var item: FitnessTestItem
    var value: Double
    var unit: FitnessTestUnit
    var note: String
}

private struct FitnessTestRecordEditorView: View {
    let record: FitnessTestRecord?
    let onSave: (FitnessTestRecordDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyLanguage) private var leafyLanguage
    @State private var testedAt: Date
    @State private var item: FitnessTestItem
    @State private var valueText: String
    @State private var minutes: Int
    @State private var seconds: Int
    @State private var note: String

    private var unit: FitnessTestUnit {
        item.defaultUnit
    }

    private var trimmedNote: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var numericValue: Double? {
        if unit == .minuteSecond {
            return Double(minutes * 60 + seconds)
        }
        return Double(valueText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var isSaveDisabled: Bool {
        guard let numericValue else { return true }
        return numericValue <= 0
    }

    init(record: FitnessTestRecord?, onSave: @escaping (FitnessTestRecordDraft) -> Void) {
        let normalizedItem = record.map { FitnessTestItem.normalized($0.itemRawValue) } ?? .height
        let normalizedUnit = normalizedItem.defaultUnit
        let value = record?.value ?? 0

        self.record = record
        self.onSave = onSave
        _testedAt = State(initialValue: record?.testedAt ?? Date())
        _item = State(initialValue: normalizedItem)
        _valueText = State(initialValue: normalizedUnit == .minuteSecond || value <= 0 ? "" : Self.inputText(for: value, unit: normalizedUnit))
        _minutes = State(initialValue: normalizedUnit == .minuteSecond ? max(Int(value.rounded()), 0) / 60 : 3)
        _seconds = State(initialValue: normalizedUnit == .minuteSecond ? max(Int(value.rounded()), 0) % 60 : 0)
        _note = State(initialValue: record?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("测试日期", selection: $testedAt, displayedComponents: .date)
                    Picker("项目", selection: $item) {
                        ForEach(FitnessTestItem.allCases) { testItem in
                            Text(L10n.text(testItem.rawValue, language: leafyLanguage)).tag(testItem)
                        }
                    }
                    .onChange(of: item) { _, newItem in
                        valueText = ""
                        if newItem.defaultUnit == .minuteSecond {
                            minutes = 3
                            seconds = 0
                        }
                    }
                }

                Section("成绩") {
                    if unit == .minuteSecond {
                        Stepper("分钟：\(minutes)", value: $minutes, in: 0...20)
                        Stepper("秒：\(seconds)", value: $seconds, in: 0...59)
                    } else {
                        TextField(valuePlaceholder, text: $valueText)
                            .keyboardType(.decimalPad)
                    }

                    Text("单位：\(unit.rawValue)")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Section {
                    TextField("备注", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(record == nil ? "添加体测记录" : "编辑体测记录")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard let numericValue else { return }
                        onSave(FitnessTestRecordDraft(
                            testedAt: testedAt,
                            item: item,
                            value: numericValue,
                            unit: unit,
                            note: trimmedNote
                        ))
                        dismiss()
                    }
                    .disabled(isSaveDisabled)
                }
            }
        }
    }

    private var valuePlaceholder: String {
        switch unit {
        case .centimeter:
            return "例如：175.5"
        case .kilogram:
            return "例如：62.5"
        case .milliliter:
            return "例如：3200"
        case .second:
            return "例如：8.2"
        case .count:
            return "例如：20"
        case .minuteSecond:
            return ""
        }
    }

    private static func inputText(for value: Double, unit: FitnessTestUnit) -> String {
        switch unit {
        case .milliliter, .count:
            return String(Int(value.rounded()))
        case .centimeter, .kilogram, .second:
            let rounded = (value * 10).rounded() / 10
            if rounded.truncatingRemainder(dividingBy: 1) == 0 {
                return String(Int(rounded))
            }
            return String(format: "%.1f", rounded)
        case .minuteSecond:
            return ""
        }
    }
}
