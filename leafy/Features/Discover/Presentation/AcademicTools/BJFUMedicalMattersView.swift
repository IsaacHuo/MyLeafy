import PhotosUI
import SafariServices
import SwiftData
import SwiftUI

struct MedicalMattersSectionView: View {
    let openRoute: (AcademicDetailRoute) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.card) {
            LeafySectionTitle("医疗事项", subtitle: "北林公费医疗政策速查与本地报销台账。")

            AcademicDetailCard {
                HStack(alignment: .top, spacing: AppSpacing.compact) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.accentEmphasis)
                        .frame(width: 24, height: 24)

                    Text("个人台账均只保存在本机，Leafy 只做资料收集并提供参考参考，不上传医疗数据，也不会实时更新政策。")
                        .leafySubheadline()
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ToolEntryCard(title: "政策查询", subtitle: "报销比例、转诊路径、材料清单和校医院信息", icon: "doc.text.magnifyingglass") {
                openRoute(.medicalPolicy)
            }

            ToolEntryCard(title: "情景助手", subtitle: "按就医情景查看步骤、材料和注意事项", icon: "sparkles") {
                openRoute(.medicalScenarioAssistant)
            }

            ToolEntryCard(title: "报销台账", subtitle: "记录票据、材料、照片、截止日和报销状态", icon: "list.clipboard.fill") {
                openRoute(.medicalLedger)
            }
        }
    }
}

struct MedicalPolicyView: View {
    private let snapshot = MedicalPolicySnapshot.current
    @State private var browserItem: MedicalPolicyBrowserItem?

    var body: some View {
        AcademicDetailScrollContainer {
            sourceCard
            beforeCareSection
            reimbursementPreparationSection
            ruleBoundarySection
            AcademicDetailFooterText(text: "政策信息为本地快照，实际报销以校医院和学校最新通知为准。")
        }
        .navigationTitle("政策查询")
        .leafyInlineNavigationTitle()
        .sheet(item: $browserItem) { item in
            MedicalPolicySafariView(url: item.url)
        }
    }

    private var sourceCard: some View {
        AcademicDetailCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Label("本地政策", systemImage: "doc.text.fill")
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)

                Text("来源：\(snapshot.sourceTitle)。政策更新于 \(snapshot.policyUpdatedAt)，校医院基础信息更新于 \(snapshot.hospitalInfoUpdatedAt)。")
                    .leafyBody()
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                MedicalPolicyWebLinkButton(title: "查看原始说明", systemImage: "link") {
                    browserItem = MedicalPolicyBrowserItem(url: snapshot.sourceURL)
                }
            }
        }
    }

    private var beforeCareSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            AcademicDetailSectionHeader(title: "就医前先看")
            reimbursementGrid
            pathSummaryCard
        }
    }

    private var reimbursementGrid: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            AcademicDetailSectionHeader(title: "报销比例速查")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.compact) {
                ForEach(snapshot.reimbursementRates) { rate in
                    MedicalReimbursementRateTile(rate: rate)
                        .aspectRatio(1, contentMode: .fit)
                }
            }
        }
    }

    private var pathSummaryCard: some View {
        AcademicDetailCard {
            MedicalPolicyBulletGroup(
                title: "基础路径",
                rows: [
                    "普通门急诊优先先到校医院；需要转诊时按校医院或合同医院规则办理。",
                    "合同医院、非合同医院及专科医院、住院分别对应不同报销比例，先确认就医类型再留材料。",
                    "急危重症、学期异地急诊和寒暑假所在地急诊按实际类型审核，务必保留急诊材料。"
                ],
                systemImage: "arrow.triangle.branch"
            )
        }
    }

    private var reimbursementPreparationSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            AcademicDetailSectionHeader(title: "报销前准备")
            hospitalCard
            materialsCard
        }
    }

    private var hospitalCard: some View {
        AcademicDetailCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Label(snapshot.hospitalName, systemImage: "cross.case.fill")
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)

                MedicalPolicyInfoLine(title: "地址", value: snapshot.hospitalAddress)
                MedicalPolicyInfoLine(title: "电话", value: snapshot.hospitalPhones)
                MedicalPolicyInfoLine(title: "门诊时间", value: snapshot.outpatientHours)
                MedicalPolicyInfoLine(title: "公费医疗报销", value: snapshot.reimbursementHours)

                MedicalPolicyWebLinkButton(title: "查看北京 12345 服务导图", systemImage: "map.fill") {
                    browserItem = MedicalPolicyBrowserItem(url: snapshot.hospitalInfoURL)
                }
            }
        }
    }

    private var materialsCard: some View {
        AcademicDetailCard {
            MedicalPolicyBulletGroup(
                title: "常见材料",
                rows: [
                    "门急诊通常需要收费票据、费用明细清单、药品处方/底方和门急诊病历。",
                    "转诊就医要留存转诊单；急诊就医要留存急诊诊断证明。",
                    "住院报销通常需要住院收费票据、出院诊断证明、诊断证明书和费用明细。"
                ],
                systemImage: "folder.fill"
            )
        }
    }

    private var ruleBoundarySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            AcademicDetailSectionHeader(title: "规则边界")
            ruleListSection(title: "用药规范", rows: snapshot.medicationRules, icon: "pills.fill")
            ruleListSection(title: "不予报销范围", rows: snapshot.excludedExpenses, icon: "xmark.shield.fill")
            ruleListSection(title: "康复医疗费用", rows: snapshot.rehabRules, icon: "figure.walk.motion")
        }
    }

    private func ruleListSection(title: String, rows: [String], icon: String) -> some View {
        AcademicDetailCard {
            MedicalPolicyBulletGroup(title: title, rows: rows, systemImage: icon)
        }
    }
}

struct MedicalScenarioAssistantView: View {
    private let snapshot = MedicalPolicySnapshot.current
    @State private var selectedScenario: MedicalLedgerScenario = .campusClinic

    private var advice: MedicalPolicyScenarioAdvice {
        snapshot.advice(for: selectedScenario)
    }

    var body: some View {
        AcademicDetailScrollContainer {
            AcademicDetailCard {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    HStack {
                        Label("情景助手", systemImage: "sparkles")
                            .leafyHeadline()
                        Spacer()
                        Picker("就医情景", selection: $selectedScenario) {
                            ForEach(MedicalLedgerScenario.allCases) { scenario in
                                Text(scenario.rawValue)
                                    .lineLimit(1)
                                    .tag(scenario)
                            }
                        }
                        .labelsHidden()
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    }

                    HStack(alignment: .center, spacing: 10) {
                        LeafyIconBadge(systemName: selectedScenario.icon)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(advice.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.primaryText)
                            Text("参考比例：\(advice.rateText)")
                                .microCaption()
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }

                    MedicalPolicyBulletGroup(title: "建议步骤", rows: advice.steps, systemImage: "checklist")
                    MedicalPolicyBulletGroup(title: "材料清单", rows: advice.materials.map(\.rawValue), systemImage: "folder.fill")
                    MedicalPolicyBulletGroup(title: "注意事项", rows: advice.notes, systemImage: "info.circle.fill")
                }
            }

            AcademicDetailFooterText(text: "情景助手根据参考政策整理，实际报销以校医院和学校最新通知为准。")
        }
        .navigationTitle("情景助手")
        .leafyInlineNavigationTitle()
    }
}

private struct MedicalReimbursementRateTile: View {
    let rate: MedicalReimbursementRate

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(rate.category)
                .microCaption()
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(1)

            Text("\(rate.rate)%")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppTheme.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(rate.target)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(3)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 4)

            Text(rate.note)
                .microCaption()
                .foregroundStyle(AppTheme.tertiaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .stroke(AppTheme.separator.opacity(0.35), lineWidth: 1)
        }
    }
}

private struct MedicalPolicyWebLinkButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
        }
        .buttonStyle(.plain)
    }
}

private struct MedicalPolicyBulletGroup: View {
    let title: String
    let rows: [String]
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(AppTheme.accent.opacity(0.72))
                        .frame(width: 6, height: 6)
                        .padding(.top, 7)
                    Text(row)
                        .leafyBody()
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct MedicalPolicyInfoLine: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .microCaption()
                .foregroundStyle(AppTheme.tertiaryText)
            Text(value)
                .leafyBody()
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if canImport(UIKit)
private struct MedicalPolicySafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
#else
private typealias MedicalPolicySafariView = LeafyExternalBrowserView
#endif

private struct MedicalPolicyBrowserItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct MedicalLedgerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.leafyLanguage) private var leafyLanguage

    @Query(sort: \MedicalLedgerEntry.visitDate, order: .reverse) private var entries: [MedicalLedgerEntry]
    @Query(sort: \MedicalLedgerPhoto.importedAt, order: .reverse) private var photos: [MedicalLedgerPhoto]

    @State private var filter: MedicalLedgerFilter = .active
    @State private var editorState: MedicalLedgerEditorState?
    @State private var entryPendingDeletion: MedicalLedgerEntry?
    @State private var showingDeleteAllConfirmation = false
    @State private var shareItem: MedicalLedgerArchiveShareItem?
    @State private var alertMessage: String?

    private var visibleEntries: [MedicalLedgerEntry] {
        entries.filter { entry in
            switch filter {
            case .all:
                return true
            case .active:
                return !entry.status.isClosed
            case .attention:
                switch entry.deadlineState() {
                case .dueSoon, .overdue:
                    return true
                case .none, .normal, .closed:
                    return false
                }
            case .closed:
                return entry.status.isClosed
            }
        }
    }

    var body: some View {
        AcademicDetailScrollContainer {
            privacyCard
            summaryCard
            filterPicker

            if visibleEntries.isEmpty {
                AcademicDetailCard {
                    ContentUnavailableView(
                        filter.emptyTitle,
                        systemImage: "list.clipboard",
                        description: Text(filter.emptyDescription)
                    )
                    .padding(.vertical, AppSpacing.page)
                }
            } else {
                ledgerList
            }

            AcademicDetailFooterText(text: "台账、照片和导出文件均在本机处理；删除台账会同步删除本地照片。")
        }
        .navigationTitle("报销台账")
        .leafyInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .leafyLeading) {
                if !entries.isEmpty {
                    Button(role: .destructive) {
                        showingDeleteAllConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("清空医疗台账")
                }
            }

            ToolbarItem(placement: .leafyTrailing) {
                Menu {
                    Button {
                        editorState = MedicalLedgerEditorState(entry: nil)
                    } label: {
                        Label("新增台账", systemImage: "plus")
                    }

                    Button {
                        exportArchive()
                    } label: {
                        Label("完整打包导出", systemImage: "square.and.arrow.up")
                    }
                    .disabled(entries.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("医疗台账操作")
            }
        }
        .sheet(item: $editorState) { state in
            MedicalLedgerEditorSheet(
                entry: state.entry,
                existingPhotos: state.entry.map { photos(for: $0) } ?? [],
                saveAction: saveEntry,
                deletePhotoAction: deletePhoto
            )
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: [item.url])
        }
        .alert("删除这条台账？", isPresented: Binding(
            get: { entryPendingDeletion != nil },
            set: { if !$0 { entryPendingDeletion = nil } }
        )) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let entry = entryPendingDeletion {
                    deleteEntry(entry)
                }
                entryPendingDeletion = nil
            }
        } message: {
            Text("删除后会同时移除本地照片，无法恢复。")
        }
        .alert("清空全部医疗台账？", isPresented: $showingDeleteAllConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive, action: deleteAllEntries)
        } message: {
            Text("这会删除所有医疗台账和本地照片，无法恢复。")
        }
        .alert("医疗台账", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var privacyCard: some View {
        AcademicDetailCard {
            HStack(alignment: .top, spacing: AppSpacing.compact) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.accentEmphasis)
                    .frame(width: 24, height: 24)

                Text("台账和票据照片只保存在当前设备。建议不要记录不必要的敏感细节，导出压缩包后请自行保管。")
                    .leafySubheadline()
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var summaryCard: some View {
        AcademicDetailCard {
            HStack(spacing: AppSpacing.compact) {
                MedicalLedgerMetric(title: "台账", value: "\(entries.count)", subtitle: "全部记录")
                MedicalLedgerMetric(title: "待处理", value: "\(entries.filter { !$0.status.isClosed }.count)", subtitle: "未归档")
                MedicalLedgerMetric(title: "需关注", value: "\(attentionCount)", subtitle: "临近/逾期")
            }
        }
    }

    private var filterPicker: some View {
        Picker("筛选", selection: $filter) {
            ForEach(MedicalLedgerFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("医疗台账筛选")
    }

    private var ledgerList: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            AcademicDetailSectionHeader(title: filter.title)
            AcademicDetailCard {
                VStack(spacing: 0) {
                    ForEach(Array(visibleEntries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            AcademicDetailDivider()
                        }
                        MedicalLedgerEntryRow(
                            entry: entry,
                            photoCount: photos(for: entry).count,
                            editAction: { editorState = MedicalLedgerEditorState(entry: entry) },
                            deleteAction: { entryPendingDeletion = entry }
                        )
                    }
                }
            }
        }
    }

    private var attentionCount: Int {
        entries.filter { entry in
            switch entry.deadlineState() {
            case .dueSoon, .overdue:
                return true
            case .none, .normal, .closed:
                return false
            }
        }.count
    }

    private func photos(for entry: MedicalLedgerEntry) -> [MedicalLedgerPhoto] {
        photos
            .filter { $0.entryID == entry.id.uuidString }
            .sorted { $0.importedAt < $1.importedAt }
    }

    private func saveEntry(draft: MedicalLedgerDraft, pendingPhotos: [MedicalLedgerPendingPhoto], existingEntry: MedicalLedgerEntry?) {
        do {
            let entry = existingEntry ?? MedicalLedgerEntry()
            draft.apply(to: entry)
            if existingEntry == nil {
                modelContext.insert(entry)
            }

            for pendingPhoto in pendingPhotos {
                let stored = try MedicalLedgerPhotoStore.importImageData(
                    pendingPhoto.jpegData,
                    originalFilename: pendingPhoto.originalFilename
                )
                modelContext.insert(MedicalLedgerPhoto(
                    entryID: entry.id.uuidString,
                    originalFilename: pendingPhoto.originalFilename,
                    localFilename: stored.localFilename
                ))
            }

            try modelContext.save()
            alertMessage = "台账已保存。"
        } catch {
            alertMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    private func deletePhoto(_ photo: MedicalLedgerPhoto) {
        try? MedicalLedgerPhotoStore.deleteFile(named: photo.localFilename)
        modelContext.delete(photo)
        try? modelContext.save()
    }

    private func deleteEntry(_ entry: MedicalLedgerEntry) {
        for photo in photos(for: entry) {
            try? MedicalLedgerPhotoStore.deleteFile(named: photo.localFilename)
            modelContext.delete(photo)
        }
        modelContext.delete(entry)
        try? modelContext.save()
    }

    private func deleteAllEntries() {
        for photo in photos {
            try? MedicalLedgerPhotoStore.deleteFile(named: photo.localFilename)
            modelContext.delete(photo)
        }
        for entry in entries {
            modelContext.delete(entry)
        }
        try? modelContext.save()
    }

    private func exportArchive() {
        do {
            let url = try MedicalLedgerExporter.exportArchive(entries: entries, photos: photos)
            shareItem = MedicalLedgerArchiveShareItem(url: url)
        } catch {
            alertMessage = "导出失败：\(error.localizedDescription)"
        }
    }
}

private struct MedicalLedgerMetric: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .microCaption()
                .foregroundStyle(AppTheme.secondaryText)
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AppTheme.primaryText)
            Text(subtitle)
                .microCaption()
                .foregroundStyle(AppTheme.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MedicalLedgerEntryRow: View {
    let entry: MedicalLedgerEntry
    let photoCount: Int
    let editAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: editAction) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.displayTitle)
                            .leafyHeadline()
                            .foregroundStyle(AppTheme.primaryText)
                            .lineLimit(1)
                        MedicalLedgerStatusBadge(text: entry.status.rawValue, tint: statusTint)
                    }

                    Text("\(entry.visitDate, format: .dateTime.year().month().day()) · \(entry.scenario.rawValue)")
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        MedicalLedgerCompactInfo(systemImage: "yensign.circle", text: reimbursementText)
                        MedicalLedgerCompactInfo(systemImage: "photo", text: "\(photoCount) 张")
                        MedicalLedgerDeadlineBadge(state: entry.deadlineState())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button(action: editAction) {
                    Label("编辑", systemImage: "pencil")
                }
                Button(role: .destructive, action: deleteAction) {
                    Label("删除", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(width: 30, height: 30)
                    .background(AppTheme.softFill, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }

    private var reimbursementText: String {
        if let actual = entry.actualReimbursement {
            return "实报 \(Self.amountText(actual))"
        }
        if let estimate = entry.estimatedOrCalculatedReimbursement {
            return "预计 \(Self.amountText(estimate))"
        }
        return "未估算"
    }

    private var statusTint: Color {
        switch entry.status {
        case .organizing, .readyToSubmit:
            return AppTheme.warning
        case .submitted:
            return AppTheme.accent
        case .reimbursed, .archived:
            return AppTheme.accentEmphasis
        case .returned:
            return AppTheme.danger
        }
    }

    private static func amountText(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

private struct MedicalLedgerCompactInfo: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(AppTheme.secondaryText)
            .lineLimit(1)
    }
}

private struct MedicalLedgerStatusBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct MedicalLedgerDeadlineBadge: View {
    let state: MedicalLedgerDeadlineState

    var body: some View {
        switch state {
        case .none:
            MedicalLedgerCompactInfo(systemImage: "calendar", text: "无截止")
        case .normal(let days):
            MedicalLedgerCompactInfo(systemImage: "calendar", text: "\(days) 天")
        case .dueSoon(let days):
            Label(days == 0 ? "今天截止" : "\(days) 天截止", systemImage: "exclamationmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.warning)
        case .overdue(let days):
            Label("逾期 \(days) 天", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.danger)
        case .closed:
            MedicalLedgerCompactInfo(systemImage: "checkmark.circle", text: "已结束")
        }
    }
}

private struct MedicalLedgerEditorSheet: View {
    let entry: MedicalLedgerEntry?
    let saveAction: (MedicalLedgerDraft, [MedicalLedgerPendingPhoto], MedicalLedgerEntry?) -> Void
    let deletePhotoAction: (MedicalLedgerPhoto) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: MedicalLedgerDraft
    @State private var existingPhotos: [MedicalLedgerPhoto]
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var pendingPhotos: [MedicalLedgerPendingPhoto] = []
    @State private var photoLoadError: String?

    init(
        entry: MedicalLedgerEntry?,
        existingPhotos: [MedicalLedgerPhoto],
        saveAction: @escaping (MedicalLedgerDraft, [MedicalLedgerPendingPhoto], MedicalLedgerEntry?) -> Void,
        deletePhotoAction: @escaping (MedicalLedgerPhoto) -> Void
    ) {
        self.entry = entry
        self.saveAction = saveAction
        self.deletePhotoAction = deletePhotoAction
        _draft = State(initialValue: MedicalLedgerDraft(entry: entry))
        _existingPhotos = State(initialValue: existingPhotos)
    }

    var body: some View {
        NavigationStack {
            Form {
                basicSection
                amountSection
                statusSection
                materialsSection
                photoSection
                noteSection
            }
            .navigationTitle(entry == nil ? "新增台账" : "编辑台账")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .leafyTrailing) {
                    Button("保存") {
                        saveAction(draft, pendingPhotos, entry)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onChange(of: selectedPhotoItems) { _, items in
                Task {
                    await loadSelectedPhotos(items)
                }
            }
        }
    }

    private var basicSection: some View {
        Section("基本信息") {
            DatePicker("就诊日期", selection: $draft.visitDate, displayedComponents: .date)
            TextField("医院", text: $draft.hospitalName)
            TextField("科室", text: $draft.department)
            TextField("诊断或病情备注", text: $draft.diagnosisNote, axis: .vertical)
                .lineLimit(2...4)
            MedicalLedgerScenarioPicker(selection: $draft.scenario)
        }
    }

    private var amountSection: some View {
        Section("金额") {
            TextField("总费用", text: $draft.totalExpenseText)
                .keyboardType(.decimalPad)
            TextField("预计报销", text: $draft.estimatedReimbursementText)
                .keyboardType(.decimalPad)
            TextField("实际报销", text: $draft.actualReimbursementText)
                .keyboardType(.decimalPad)
            if let calculated = draft.calculatedReimbursement {
                LabeledContent("按场景估算", value: String(format: "%.2f", calculated))
            }
        }
    }

    private var statusSection: some View {
        Section("状态与截止日") {
            MedicalLedgerStatusPicker(selection: $draft.status)
            Toggle("设置报销截止日", isOn: $draft.hasDeadline)
            if draft.hasDeadline {
                DatePicker("截止日", selection: $draft.reimbursementDeadline, displayedComponents: .date)
            }
        }
    }

    private var materialsSection: some View {
        Section("材料") {
            ForEach(MedicalLedgerMaterial.allCases) { material in
                MedicalLedgerMaterialRow(material: material, materials: $draft.materials)
            }
        }
    }

    private var photoSection: some View {
        Section {
            PhotosPicker(selection: $selectedPhotoItems, matching: .images) {
                Label("选择票据照片", systemImage: "photo.on.rectangle.angled")
            }

            if !existingPhotos.isEmpty {
                MedicalLedgerPhotoStrip(photos: existingPhotos, deleteAction: removeExistingPhoto)
            }

            if !pendingPhotos.isEmpty {
                MedicalLedgerPendingPhotoStrip(photos: pendingPhotos, deleteAction: removePendingPhoto)
            }

            if let photoLoadError {
                MedicalLedgerPhotoErrorText(message: photoLoadError)
            }
        } header: {
            Text("照片")
        } footer: {
            Text("仅保存照片，不保存 PDF；图片会转换为本机私有目录中的 JPEG。")
        }
    }

    private var noteSection: some View {
        Section("备注") {
            TextField("补充说明", text: $draft.note, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    @MainActor
    private func loadSelectedPhotos(_ items: [PhotosPickerItem]) async {
        photoLoadError = nil
        var loaded: [MedicalLedgerPendingPhoto] = pendingPhotos
        for (index, item) in items.enumerated() {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let jpegData = try MedicalLedgerPhotoStore.normalizedJPEGData(from: data)
                guard let image = LeafyPlatformImage(data: jpegData) else { continue }
                loaded.append(MedicalLedgerPendingPhoto(
                    originalFilename: "票据照片-\(index + 1).jpg",
                    jpegData: jpegData,
                    image: image
                ))
            } catch {
                photoLoadError = "加载照片失败：\(error.localizedDescription)"
            }
        }
        pendingPhotos = loaded
        selectedPhotoItems = []
    }

    private func removePendingPhoto(_ photo: MedicalLedgerPendingPhoto) {
        pendingPhotos.removeAll { $0.id == photo.id }
    }

    private func removeExistingPhoto(_ photo: MedicalLedgerPhoto) {
        deletePhotoAction(photo)
        existingPhotos.removeAll { $0.id == photo.id }
    }
}

private struct MedicalLedgerMaterialRow: View {
    let material: MedicalLedgerMaterial
    @Binding var materials: Set<MedicalLedgerMaterial>

    var body: some View {
        Toggle(material.rawValue, isOn: isSelected)
    }

    private var isSelected: Binding<Bool> {
        Binding {
            materials.contains(material)
        } set: { selected in
            if selected {
                materials.insert(material)
            } else {
                materials.remove(material)
            }
        }
    }
}

private struct MedicalLedgerScenarioPicker: View {
    @Binding var selection: MedicalLedgerScenario

    var body: some View {
        Picker("就医场景", selection: $selection) {
            ForEach(MedicalLedgerScenario.allCases) { scenario in
                Text(scenario.rawValue).tag(scenario)
            }
        }
    }
}

private struct MedicalLedgerStatusPicker: View {
    @Binding var selection: MedicalLedgerStatus

    var body: some View {
        Picker("状态", selection: $selection) {
            ForEach(MedicalLedgerStatus.allCases) { status in
                Text(status.rawValue).tag(status)
            }
        }
    }
}

private struct MedicalLedgerPhotoErrorText: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(AppTheme.danger)
    }
}

private struct MedicalLedgerPhotoStrip: View {
    let photos: [MedicalLedgerPhoto]
    let deleteAction: (MedicalLedgerPhoto) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(photos, id: \.id) { photo in
                    ZStack(alignment: .topTrailing) {
                        if let image = MedicalLedgerPhotoStore.image(for: photo) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(AppTheme.tertiaryText)
                        }
                    }
                    .frame(width: 82, height: 82)
                    .background(AppTheme.softFill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        Button {
                            deleteAction(photo)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white, .black.opacity(0.55))
                        }
                        .offset(x: 6, y: -6)
                    }
                }
            }
        }
    }
}

private struct MedicalLedgerPendingPhotoStrip: View {
    let photos: [MedicalLedgerPendingPhoto]
    let deleteAction: (MedicalLedgerPendingPhoto) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(photos) { photo in
                    MedicalLedgerPendingPhotoThumbnail(photo: photo, deleteAction: deleteAction)
                }
            }
        }
    }
}

private struct MedicalLedgerPendingPhotoThumbnail: View {
    let photo: MedicalLedgerPendingPhoto
    let deleteAction: (MedicalLedgerPendingPhoto) -> Void

    var body: some View {
        Image(uiImage: photo.image)
            .resizable()
            .scaledToFill()
            .frame(width: 82, height: 82)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button {
                    deleteAction(photo)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white, .black.opacity(0.55))
                }
                .offset(x: 6, y: -6)
            }
    }
}

private enum MedicalLedgerFilter: String, CaseIterable, Identifiable {
    case active = "待处理"
    case attention = "需关注"
    case closed = "已结束"
    case all = "全部"

    var id: String { rawValue }
    var title: String { rawValue }

    var emptyTitle: String {
        switch self {
        case .active: return "没有待处理台账"
        case .attention: return "没有临近或逾期台账"
        case .closed: return "没有已结束台账"
        case .all: return "还没有医疗台账"
        }
    }

    var emptyDescription: String {
        switch self {
        case .active: return "新增台账后，可在这里跟踪材料和报销状态。"
        case .attention: return "设置报销截止日后，临近 14 天和逾期记录会出现在这里。"
        case .closed: return "已报销或已归档的记录会出现在这里。"
        case .all: return "点击右上角新增第一条就医和报销记录。"
        }
    }
}

private struct MedicalLedgerEditorState: Identifiable {
    let id = UUID()
    let entry: MedicalLedgerEntry?
}

private struct MedicalLedgerArchiveShareItem: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct MedicalLedgerPendingPhoto: Identifiable {
    let id = UUID()
    let originalFilename: String
    let jpegData: Data
    let image: LeafyPlatformImage
}

private struct MedicalLedgerDraft {
    var visitDate: Date
    var hospitalName: String
    var department: String
    var diagnosisNote: String
    var scenario: MedicalLedgerScenario
    var totalExpenseText: String
    var estimatedReimbursementText: String
    var actualReimbursementText: String
    var status: MedicalLedgerStatus
    var hasDeadline: Bool
    var reimbursementDeadline: Date
    var materials: Set<MedicalLedgerMaterial>
    var note: String

    init(entry: MedicalLedgerEntry?) {
        visitDate = entry?.visitDate ?? Date()
        hospitalName = entry?.hospitalName ?? ""
        department = entry?.department ?? ""
        diagnosisNote = entry?.diagnosisNote ?? ""
        scenario = entry?.scenario ?? .campusClinic
        totalExpenseText = Self.text(from: entry?.totalExpense ?? 0)
        estimatedReimbursementText = Self.optionalText(from: entry?.estimatedReimbursement)
        actualReimbursementText = Self.optionalText(from: entry?.actualReimbursement)
        status = entry?.status ?? .organizing
        hasDeadline = entry?.reimbursementDeadline != nil
        reimbursementDeadline = entry?.reimbursementDeadline ?? Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
        materials = entry?.materials ?? Set(MedicalPolicySnapshot.current.advice(for: scenario).materials)
        note = entry?.note ?? ""
    }

    var calculatedReimbursement: Double? {
        MedicalLedgerCalculator.estimatedReimbursement(totalExpense: totalExpenseValue ?? 0, scenario: scenario)
    }

    func apply(to entry: MedicalLedgerEntry) {
        entry.visitDate = visitDate
        entry.hospitalName = hospitalName.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.department = department.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.diagnosisNote = diagnosisNote.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.scenario = scenario
        entry.totalExpense = totalExpenseValue ?? 0
        entry.estimatedReimbursement = optionalDouble(from: estimatedReimbursementText)
        entry.actualReimbursement = optionalDouble(from: actualReimbursementText)
        entry.status = status
        entry.reimbursementDeadline = hasDeadline ? reimbursementDeadline : nil
        entry.materials = materials
        entry.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.updatedAt = Date()
    }

    private var totalExpenseValue: Double? {
        optionalDouble(from: totalExpenseText)
    }

    private func optionalDouble(from text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "，", with: ".")
        guard !normalized.isEmpty, let value = Double(normalized), value.isFinite else { return nil }
        return value
    }

    private static func text(from value: Double) -> String {
        guard value > 0 else { return "" }
        return String(format: "%.2f", value)
    }

    private static func optionalText(from value: Double?) -> String {
        guard let value else { return "" }
        return text(from: value)
    }
}

#Preview {
    NavigationStack {
        MedicalMattersSectionView { _ in }
    }
}
