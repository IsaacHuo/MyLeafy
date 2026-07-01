import SwiftUI

struct CustomCountdownListView: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    @State private var items: [CustomCountdownEvent] = []
    @State private var showingEditor = false
    @State private var editingItem: CustomCountdownEvent?
    @State private var operationAlert: LeafyOperationAlert?

    private var sortedItems: [CustomCountdownEvent] {
        items.sorted { $0.targetDate < $1.targetDate }
    }

    var body: some View {
        AcademicDetailScrollContainer {
            if items.isEmpty {
                AcademicDetailCard {
                    ContentUnavailableView("暂无自定义倒计时", systemImage: "calendar.badge.plus")
                }
            } else {
                ForEach(sortedItems) { item in
                    AcademicDetailCard {
                        HStack(alignment: .top, spacing: AppSpacing.compact) {
                            CountdownEventRow(
                                title: item.title,
                                badge: CountdownEvent.Kind.custom.rawValue,
                                targetDate: item.targetDate
                            )

                            Spacer(minLength: AppSpacing.micro)

                            VStack(spacing: AppSpacing.micro) {
                                Button {
                                    editingItem = item
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(AppTheme.accentEmphasis)
                                        .frame(width: 34, height: 34)
                                        .background(AppTheme.softFill, in: Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("编辑倒计时")

                                Button(role: .destructive) {
                                    delete(item)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(AppTheme.danger)
                                        .frame(width: 34, height: 34)
                                        .background(AppTheme.danger.opacity(0.1), in: Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("删除倒计时")
                            }
                        }
                    }
                }
            }

            AcademicDetailFooterText(text: "自定义倒计时仅保存在当前设备。")
        }
        .navigationTitle("自定义倒计时")
        .leafyInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .leafyTrailing) {
                Button {
                    showingEditor = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            CustomCountdownEditorView(item: nil) { item in
                upsert(item)
            }
        }
        .sheet(item: $editingItem) { item in
            CustomCountdownEditorView(item: item) { item in
                upsert(item)
            }
        }
        .onAppear {
            items = CustomCountdownStore.load()
        }
        .leafyOperationAlert($operationAlert)
    }

    private func upsert(_ item: CustomCountdownEvent) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
            operationAlert = .success(L10n.text("倒计时已保存！", language: leafyLanguage))
        } else {
            items.append(item)
            operationAlert = .success(L10n.text("倒计时已添加！", language: leafyLanguage))
        }
        items.sort { $0.targetDate < $1.targetDate }
        CustomCountdownStore.save(items)
    }

    private func delete(_ item: CustomCountdownEvent) {
        items.removeAll { $0.id == item.id }
        CustomCountdownStore.save(items)
        operationAlert = .success(L10n.text("倒计时已删除！", language: leafyLanguage))
    }
}

private struct CustomCountdownEditorView: View {
    let item: CustomCountdownEvent?
    let onSave: (CustomCountdownEvent) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var targetDate: Date

    private var isSaveDisabled: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(item: CustomCountdownEvent?, onSave: @escaping (CustomCountdownEvent) -> Void) {
        self.item = item
        self.onSave = onSave
        _title = State(initialValue: item?.title ?? "")
        _targetDate = State(initialValue: item?.targetDate ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("倒计时名称", text: $title)
                    DatePicker("目标时间", selection: $targetDate, displayedComponents: [.date, .hourAndMinute])
                }
            }
            .navigationTitle(item == nil ? "添加倒计时" : "编辑倒计时")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(CustomCountdownEvent(id: item?.id ?? UUID().uuidString, title: trimmedTitle, targetDate: targetDate))
                        dismiss()
                    }
                    .disabled(isSaveDisabled)
                }
            }
        }
    }
}

struct CountdownEventRow: View {
    let title: String
    let badge: String
    let targetDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(badge)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.softFill, in: Capsule())
            }
            Text(DateFormatters.headerWithTime.string(from: targetDate))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(Self.countdownDescription(for: targetDate))
                .font(.title3.weight(.bold))
        }
        .padding(.vertical, 6)
    }

    private static func countdownDescription(for targetDate: Date) -> String {
        let seconds = Int(targetDate.timeIntervalSinceNow)
        if seconds <= 0 { return "已开始" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        if days > 0 {
            return "还有 \(days) 天 \(hours) 小时"
        }
        let minutes = (seconds % 3_600) / 60
        return "还有 \(hours) 小时 \(minutes) 分钟"
    }
}
