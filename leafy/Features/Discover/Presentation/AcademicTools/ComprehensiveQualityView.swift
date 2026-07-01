import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ComprehensiveQualityView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    @Query(sort: \ComprehensiveQualityRecord.updatedAt, order: .reverse) private var records: [ComprehensiveQualityRecord]
    @Query(sort: \ComprehensiveQualityComponentEntry.updatedAt, order: .reverse) private var componentEntries: [ComprehensiveQualityComponentEntry]
    @Query(sort: \ComprehensiveQualityEvidenceDocument.updatedAt, order: .reverse) private var evidenceDocuments: [ComprehensiveQualityEvidenceDocument]

    @State private var selectedCollege = "园林学院"
    @State private var draft = ComprehensiveQualityDraft()
    @State private var displayedCalculationResult: ComprehensiveQualityCalculationResult?
    @State private var didLoadInitialRecord = false
    @State private var importingComponentKind: ComprehensiveQualityComponentKind?
    @State private var isImporterPresented = false
    @State private var documentPendingDeletion: ComprehensiveQualityEvidenceDocument?
    @State private var alertMessage: String?
    @State private var csvShareItem: ComprehensiveQualityCSVShareItem?
    @State private var sharePreviewImage: UIImage?
    @FocusState private var focusedInput: ComprehensiveQualityInputField?

    private var isUnavailableCampus: Bool {
        ActiveCampusContext.identity?.isCustom == true || ActiveCampusContext.descriptor.id != .bjfu
    }

    private var currentRule: ComprehensiveQualityCollegeRule {
        ComprehensiveQualityRuleCatalog.rule(for: selectedCollege)
    }

    private var draftCalculationResult: ComprehensiveQualityCalculationResult {
        ComprehensiveQualityCalculator.calculate(
            rule: currentRule,
            academicStandardScore: draft.academicStandardScoreValue,
            inputs: draft.componentInputs(for: currentRule)
        )
    }

    var body: some View {
        AcademicDetailScrollContainer {
            if isUnavailableCampus {
                AcademicDetailCard {
                    ContentUnavailableView(
                        "综素测算暂不可用",
                        systemImage: "function",
                        description: Text("该功能只适用于北京林业大学官方学院规则，通用入口不会套用北林细则。")
                    )
                    .padding(.vertical, AppSpacing.compact)
                }
            } else {
                selectorCard
                ruleSourceCard
                resultCard
                scoreInputCard
                componentInputSection
                officialResultCard
                AcademicDetailFooterText(text: "综素测算只保存在当前设备；结果按统一四项权重本地估算，最终以学院官方公示为准。")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("综素测算")
        .leafyInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .leafyTrailing) {
                Menu {
                    Button {
                        exportCSV()
                    } label: {
                        Label("导出 CSV 表格", systemImage: "tablecells")
                    }
                    Button {
                        generateSharePreview()
                    } label: {
                        Label("导出结果图片", systemImage: "photo")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(isUnavailableCampus)
                .accessibilityLabel(L10n.text("导出综素测算", language: leafyLanguage))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if focusedInput != nil {
                keyboardAccessoryBar
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: ComprehensiveQualityEvidenceFileStore.allowedContentTypes,
            allowsMultipleSelection: true,
            onCompletion: handleEvidenceImport
        )
        .alert("综素测算", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .alert("删除这份材料？", isPresented: Binding(
            get: { documentPendingDeletion != nil },
            set: { if !$0 { documentPendingDeletion = nil } }
        )) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let document = documentPendingDeletion {
                    delete(document)
                }
                documentPendingDeletion = nil
            }
        } message: {
            Text("删除后会同时移除本地文件，无法恢复。")
        }
        .sheet(item: $csvShareItem) { item in
            ShareSheet(activityItems: [item.url])
        }
        .sheet(isPresented: Binding(
            get: { sharePreviewImage != nil },
            set: { if !$0 { sharePreviewImage = nil } }
        )) {
            if let sharePreviewImage {
                ComprehensiveQualityImagePreviewSheet(image: sharePreviewImage)
            }
        }
        .onAppear {
            loadInitialRecordIfNeeded()
        }
        .onChange(of: selectedCollege) { _, _ in
            focusedInput = nil
            loadDraftFromStorage()
        }
    }

    private var keyboardAccessoryBar: some View {
        HStack {
            Button("清空") {
                clearFocusedInput()
            }
            .disabled(focusedInput == nil)

            Spacer()

            Button("完成") {
                focusedInput = nil
            }
            .fontWeight(.semibold)
        }
        .font(.body)
        .padding(.horizontal, AppSpacing.page)
        .frame(height: 46)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.separator)
                .frame(height: 1)
        }
    }

    private var selectorCard: some View {
        AcademicDetailCard {
            HStack(alignment: .center, spacing: AppSpacing.compact) {
                Label("测算对象", systemImage: "person.text.rectangle")
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)

                Spacer(minLength: AppSpacing.compact)

                Picker("学院", selection: $selectedCollege) {
                    ForEach(ComprehensiveQualityRuleCatalog.allRules) { rule in
                        Text(rule.collegeName).tag(rule.collegeName)
                    }
                }
                .pickerStyle(.menu)
                .lineLimit(1)
            }
        }
    }

    private var ruleSourceCard: some View {
        AcademicDetailCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Label(currentRule.status.title, systemImage: statusIcon)
                        .leafyHeadline()
                        .foregroundStyle(statusColor)
                    Spacer()
                    Text(currentRule.updatedAtText)
                        .microCaption()
                        .foregroundStyle(AppTheme.tertiaryText)
                }

                Text(currentRule.sourceTitle)
                    .leafySubheadline()
                    .foregroundStyle(AppTheme.primaryText)

                Text(currentRule.applicableText)
                    .leafyBody()
                    .foregroundStyle(AppTheme.secondaryText)

                Text(currentRule.calculationNote)
                    .microCaption()
                    .foregroundStyle(AppTheme.tertiaryText)

                HStack(spacing: 10) {
                    if let url = currentRule.sourceURL {
                        Link(destination: url) {
                            Label("规则网页", systemImage: "safari")
                        }
                    }
                    if let url = currentRule.attachmentURL {
                        Link(destination: url) {
                            Label("附件", systemImage: "paperclip")
                        }
                    }
                }
                .font(.caption.weight(.semibold))
            }
        }
    }

    private var resultCard: some View {
        AcademicDetailCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("估算结果", systemImage: "function")
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)
                    Spacer()
                    Text(resultStatusText)
                        .microCaption()
                        .foregroundStyle(statusColor)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                    metricTile("学业标准分", draft.academicStandardScoreValue.map(formatScore) ?? "--", "手动填写")
                    metricTile("综素贡献", displayedCalculationResult?.qualityContribution.map(formatScore) ?? "--", "最多 5 分")
                    metricTile("综合成绩", displayedCalculationResult?.compositeScore.map(formatScore) ?? "--", "估算值")
                    metricTile("材料状态", materialReadyText, "本地记录")
                }

                Button {
                    startEstimation()
                } label: {
                    Label("开始估算", systemImage: "function")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent(for: themeColorPreference))
            }
        }
    }

    private var scoreInputCard: some View {
        AcademicDetailCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Label("学业部分", systemImage: "chart.bar.doc.horizontal")
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)

                ComprehensiveQualityNumberField(
                    title: "全学程学分积标准分",
                    text: draftBinding(for: \.academicStandardScore, invalidatesEstimation: true),
                    placeholder: "0-100",
                    focusedInput: $focusedInput,
                    field: .academicStandardScore
                )

                AcademicDetailFooterText(text: "该值需要按学院/专业公示口径手动填写；成绩页的 GPA、均分和排名只能作为参考。")
            }
        }
    }

    private var componentInputSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            AcademicDetailSectionHeader(title: "综素项目")
            ForEach(currentRule.components) { componentRule in
                componentCard(componentRule)
            }
        }
    }

    private func componentCard(_ componentRule: ComprehensiveQualityComponentRule) -> some View {
        let kind = componentRule.kind
        let result = displayedCalculationResult?.componentResults.first { $0.kind == kind }
        let documents = evidenceDocuments(for: kind)

        return AcademicDetailCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Label(kind.title, systemImage: kind.icon)
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)
                    Spacer()
                    Text("\(formatPercent(componentRule.weightPercent))")
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Text(componentRule.detail)
                    .microCaption()
                    .foregroundStyle(AppTheme.tertiaryText)

                ComprehensiveQualityNumberField(
                    title: "官方标准分",
                    text: componentBinding(for: kind, keyPath: \.officialStandardScore, invalidatesEstimation: true),
                    placeholder: "优先使用",
                    focusedInput: $focusedInput,
                    field: .componentOfficialStandardScore(kind)
                )
                ComprehensiveQualityNumberField(
                    title: "原始分",
                    text: componentBinding(for: kind, keyPath: \.rawScore, invalidatesEstimation: true),
                    placeholder: "可选",
                    focusedInput: $focusedInput,
                    field: .componentRawScore(kind)
                )
                ComprehensiveQualityNumberField(
                    title: "专业最高分",
                    text: componentBinding(for: kind, keyPath: \.peerMaxScore, invalidatesEstimation: true),
                    placeholder: "可选",
                    focusedInput: $focusedInput,
                    field: .componentPeerMaxScore(kind)
                )

                Toggle("材料已准备", isOn: componentBoolBinding(for: kind, keyPath: \.materialReady))
                    .leafyBody()

                TextField("备注", text: componentBinding(for: kind, keyPath: \.note), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .focused($focusedInput, equals: .componentNote(kind))

                HStack {
                    Text("标准分 \(result?.standardScore.map(formatScore) ?? "--")")
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                    Spacer()
                    Text("贡献 \(result?.contribution.map(formatScore) ?? "--")")
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                }

                if !documents.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(documents.enumerated()), id: \.element.id) { index, document in
                            if index > 0 {
                                AcademicDetailDivider()
                            }
                            evidenceRow(document)
                        }
                    }
                }

                Button {
                    importingComponentKind = kind
                    isImporterPresented = true
                } label: {
                    Label("添加材料", systemImage: "paperclip")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var officialResultCard: some View {
        AcademicDetailCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Label("官方结果", systemImage: "checkmark.seal")
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)

                ComprehensiveQualityNumberField(
                    title: "官方综素分",
                    text: draftBinding(for: \.officialQualityScore),
                    placeholder: "可选",
                    focusedInput: $focusedInput,
                    field: .officialQualityScore
                )
                ComprehensiveQualityNumberField(
                    title: "官方综合成绩",
                    text: draftBinding(for: \.officialCompositeScore),
                    placeholder: "可选",
                    focusedInput: $focusedInput,
                    field: .officialCompositeScore
                )
                TextField("备注", text: draftBinding(for: \.note), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...5)
                    .focused($focusedInput, equals: .officialNote)

                Button {
                    saveDraft()
                } label: {
                    Label("确认记录", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent(for: themeColorPreference))
            }
        }
    }

    private func clearFocusedInput() {
        guard let focusedInput else { return }

        switch focusedInput {
        case .academicStandardScore:
            draft.academicStandardScore = ""
            invalidateEstimation()
        case .componentOfficialStandardScore(let kind):
            clearComponentInput(kind, keyPath: \.officialStandardScore, invalidatesEstimation: true)
        case .componentRawScore(let kind):
            clearComponentInput(kind, keyPath: \.rawScore, invalidatesEstimation: true)
        case .componentPeerMaxScore(let kind):
            clearComponentInput(kind, keyPath: \.peerMaxScore, invalidatesEstimation: true)
        case .componentNote(let kind):
            clearComponentInput(kind, keyPath: \.note)
        case .officialQualityScore:
            draft.officialQualityScore = ""
        case .officialCompositeScore:
            draft.officialCompositeScore = ""
        case .officialNote:
            draft.note = ""
        }
    }

    private func clearComponentInput(
        _ kind: ComprehensiveQualityComponentKind,
        keyPath: WritableKeyPath<ComprehensiveQualityComponentDraft, String>,
        invalidatesEstimation: Bool = false
    ) {
        var component = componentDraft(for: kind)
        component[keyPath: keyPath] = ""
        draft.components[kind] = component
        if invalidatesEstimation {
            invalidateEstimation()
        }
    }

    private var statusIcon: String {
        switch currentRule.status {
        case .ready:
            return "checkmark.seal.fill"
        case .manualOnly:
            return "square.and.pencil"
        case .needsRuleSource:
            return "exclamationmark.triangle.fill"
        case .notApplicable:
            return "nosign"
        }
    }

    private var statusColor: Color {
        switch currentRule.status {
        case .ready:
            return AppTheme.accent(for: themeColorPreference)
        case .manualOnly:
            return .orange
        case .needsRuleSource:
            return .secondary
        case .notApplicable:
            return .red
        }
    }

    private var resultStatusText: String {
        switch currentRule.status {
        case .ready:
            return displayedCalculationResult?.compositeScore == nil ? "待开始估算" : "本地估算"
        case .manualOnly:
            return "仅记录"
        case .needsRuleSource:
            return "待补齐规则"
        case .notApplicable:
            return "不可用"
        }
    }

    private var materialReadyText: String {
        let drafts = currentRule.components.map { componentDraft(for: $0.kind) }
        let readyCount = drafts.filter(\.materialReady).count
        return "\(readyCount) / \(currentRule.components.count)"
    }

    private func metricTile(_ title: String, _ value: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .microCaption()
                .foregroundStyle(AppTheme.secondaryText)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(subtitle)
                .microCaption()
                .foregroundStyle(AppTheme.tertiaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.softFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func evidenceRow(_ document: ComprehensiveQualityEvidenceDocument) -> some View {
        HStack(spacing: 10) {
            Image(systemName: document.displayIcon)
                .foregroundStyle(AppTheme.accent(for: themeColorPreference))
                .frame(width: 28, height: 28)
                .background(AppTheme.softFill, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(document.title)
                    .leafySubheadline()
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                Text(document.displayType)
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer()

            Menu {
                Button(role: .destructive) {
                    documentPendingDeletion = document
                } label: {
                    Label("删除", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(width: 30, height: 30)
                    .background(AppTheme.softFill, in: Circle())
            }
        }
        .padding(.vertical, 6)
    }

    private func loadInitialRecordIfNeeded() {
        guard !didLoadInitialRecord else { return }
        didLoadInitialRecord = true
        loadDraftFromStorage()
    }

    private func loadDraftFromStorage() {
        let cleanCohort = normalizedCohort
        let record = records.first { $0.collegeName == selectedCollege && $0.cohort == cleanCohort }
        let entries = componentEntries.filter { $0.collegeName == selectedCollege && $0.cohort == cleanCohort }
        draft = ComprehensiveQualityDraft(record: record, entries: entries)
        displayedCalculationResult = nil
    }

    @discardableResult
    private func saveDraft(showConfirmation: Bool = true) -> Bool {
        let cleanCohort = normalizedCohort
        let now = Date()
        let record: ComprehensiveQualityRecord
        if let existing = records.first(where: { $0.collegeName == selectedCollege && $0.cohort == cleanCohort }) {
            record = existing
        } else {
            record = ComprehensiveQualityRecord(collegeName: selectedCollege, cohort: cleanCohort)
            modelContext.insert(record)
        }
        record.collegeName = selectedCollege
        record.cohort = cleanCohort
        record.academicStandardScore = draft.academicStandardScoreValue
        record.officialQualityScore = draft.officialQualityScoreValue
        record.officialCompositeScore = draft.officialCompositeScoreValue
        record.note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        record.updatedAt = now

        for componentRule in currentRule.components {
            let kind = componentRule.kind
            let componentDraft = componentDraft(for: kind)
            let entry: ComprehensiveQualityComponentEntry
            if let existing = componentEntries.first(where: {
                $0.collegeName == selectedCollege
                    && $0.cohort == cleanCohort
                    && $0.componentRawValue == kind.rawValue
            }) {
                entry = existing
            } else {
                entry = ComprehensiveQualityComponentEntry(
                    collegeName: selectedCollege,
                    cohort: cleanCohort,
                    componentRawValue: kind.rawValue
                )
                modelContext.insert(entry)
            }
            entry.collegeName = selectedCollege
            entry.cohort = cleanCohort
            entry.componentRawValue = kind.rawValue
            entry.rawScore = componentDraft.rawScoreValue
            entry.peerMaxScore = componentDraft.peerMaxScoreValue
            entry.officialStandardScore = componentDraft.officialStandardScoreValue
            entry.materialReady = componentDraft.materialReady
            entry.note = componentDraft.note.trimmingCharacters(in: .whitespacesAndNewlines)
            entry.updatedAt = now
        }

        do {
            try modelContext.save()
            if showConfirmation {
                alertMessage = L10n.text("已确认记录：分数、官方结果、备注和材料记录都会留在当前设备。", language: leafyLanguage)
            }
            return true
        } catch {
            alertMessage = error.localizedDescription
            return false
        }
    }

    private func startEstimation() {
        let missingItems = missingEstimationItems()
        guard missingItems.isEmpty else {
            alertMessage = "请补齐：\(missingItems.joined(separator: "、"))；没有该项目请填写 0。"
            displayedCalculationResult = nil
            return
        }

        guard saveDraft(showConfirmation: false) else { return }
        displayedCalculationResult = draftCalculationResult
    }

    private func missingEstimationItems() -> [String] {
        var items: [String] = []
        if draft.academicStandardScoreValue == nil {
            items.append("学业标准分")
        }

        for componentRule in currentRule.components {
            let componentDraft = componentDraft(for: componentRule.kind)
            let hasOfficial = componentDraft.officialStandardScoreValue != nil
            let hasRawPair = componentDraft.rawScoreValue.map { $0 >= 0 } == true
                && componentDraft.peerMaxScoreValue.map { $0 > 0 } == true
            if !hasOfficial && !hasRawPair {
                items.append(componentRule.kind.title)
            }
        }
        return items
    }

    private func invalidateEstimation() {
        displayedCalculationResult = nil
    }

    @MainActor
    private func generateSharePreview() {
        let result = displayedCalculationResult ?? draftCalculationResult
        let content = ComprehensiveQualityShareCard(
            summary: exportSummary(result: result),
            materialReadyText: materialReadyText
        )
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
            alertMessage = L10n.text("请稍后重试，或先截图保存当前页面。", language: leafyLanguage)
            return
        }

        sharePreviewImage = image
    }

    private func exportCSV() {
        let result = displayedCalculationResult ?? draftCalculationResult
        do {
            let url = try ComprehensiveQualityExportBuilder.makeCSVFile(summary: exportSummary(result: result))
            csvShareItem = ComprehensiveQualityCSVShareItem(url: url)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func exportSummary(result: ComprehensiveQualityCalculationResult) -> ComprehensiveQualityExportSummary {
        ComprehensiveQualityExportSummary(
            collegeName: selectedCollege,
            cohort: normalizedCohort,
            rule: currentRule,
            academicStandardScore: draft.academicStandardScoreValue,
            componentDrafts: currentRule.components.map { componentRule in
                let componentDraft = componentDraft(for: componentRule.kind)
                let documents = evidenceDocuments(for: componentRule.kind)
                return ComprehensiveQualityComponentExportSummary(
                    kind: componentRule.kind,
                    weightPercent: componentRule.weightPercent,
                    rawScore: componentDraft.rawScoreValue,
                    peerMaxScore: componentDraft.peerMaxScoreValue,
                    officialStandardScore: componentDraft.officialStandardScoreValue,
                    standardScore: result.componentResults.first { $0.kind == componentRule.kind }?.standardScore,
                    contribution: result.componentResults.first { $0.kind == componentRule.kind }?.contribution,
                    materialReady: componentDraft.materialReady,
                    evidenceCount: documents.count,
                    note: componentDraft.note
                )
            },
            qualityContribution: result.qualityContribution,
            compositeScore: result.compositeScore,
            officialQualityScore: draft.officialQualityScoreValue,
            officialCompositeScore: draft.officialCompositeScoreValue,
            note: draft.note
        )
    }

    private func handleEvidenceImport(_ result: Result<[URL], Error>) {
        guard let componentKind = importingComponentKind else { return }
        importingComponentKind = nil

        do {
            let urls = try result.get()
            for url in urls {
                let stored = try ComprehensiveQualityEvidenceFileStore.importFile(from: url)
                let title = url.deletingPathExtension().lastPathComponent
                modelContext.insert(ComprehensiveQualityEvidenceDocument(
                    collegeName: selectedCollege,
                    cohort: normalizedCohort,
                    componentRawValue: componentKind.rawValue,
                    title: title.isEmpty ? "综素材料" : title,
                    originalFilename: url.lastPathComponent,
                    localFilename: stored.localFilename,
                    contentTypeIdentifier: stored.contentTypeIdentifier
                ))
            }
            try modelContext.save()
            alertMessage = L10n.text("材料已保存到本机。", language: leafyLanguage)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func delete(_ document: ComprehensiveQualityEvidenceDocument) {
        try? ComprehensiveQualityEvidenceFileStore.deleteFile(named: document.localFilename)
        modelContext.delete(document)
        try? modelContext.save()
    }

    private var normalizedCohort: String {
        "2026届"
    }

    private func componentDraft(for kind: ComprehensiveQualityComponentKind) -> ComprehensiveQualityComponentDraft {
        draft.components[kind] ?? ComprehensiveQualityComponentDraft()
    }

    private func componentBinding(
        for kind: ComprehensiveQualityComponentKind,
        keyPath: WritableKeyPath<ComprehensiveQualityComponentDraft, String>,
        invalidatesEstimation: Bool = false
    ) -> Binding<String> {
        Binding {
            componentDraft(for: kind)[keyPath: keyPath]
        } set: { newValue in
            var component = componentDraft(for: kind)
            component[keyPath: keyPath] = newValue
            draft.components[kind] = component
            if invalidatesEstimation {
                invalidateEstimation()
            }
        }
    }

    private func draftBinding(
        for keyPath: WritableKeyPath<ComprehensiveQualityDraft, String>,
        invalidatesEstimation: Bool = false
    ) -> Binding<String> {
        Binding {
            draft[keyPath: keyPath]
        } set: { newValue in
            draft[keyPath: keyPath] = newValue
            if invalidatesEstimation {
                invalidateEstimation()
            }
        }
    }

    private func componentBoolBinding(
        for kind: ComprehensiveQualityComponentKind,
        keyPath: WritableKeyPath<ComprehensiveQualityComponentDraft, Bool>
    ) -> Binding<Bool> {
        Binding {
            componentDraft(for: kind)[keyPath: keyPath]
        } set: { newValue in
            var component = componentDraft(for: kind)
            component[keyPath: keyPath] = newValue
            draft.components[kind] = component
        }
    }

    private func evidenceDocuments(for kind: ComprehensiveQualityComponentKind) -> [ComprehensiveQualityEvidenceDocument] {
        evidenceDocuments.filter {
            $0.collegeName == selectedCollege
                && $0.cohort == normalizedCohort
                && $0.componentRawValue == kind.rawValue
        }
    }

    private func formatScore(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func formatPercent(_ value: Double) -> String {
        value == floor(value) ? String(format: "%.0f%%", value) : String(format: "%.1f%%", value)
    }
}

private enum ComprehensiveQualityInputField: Hashable {
    case academicStandardScore
    case componentOfficialStandardScore(ComprehensiveQualityComponentKind)
    case componentRawScore(ComprehensiveQualityComponentKind)
    case componentPeerMaxScore(ComprehensiveQualityComponentKind)
    case componentNote(ComprehensiveQualityComponentKind)
    case officialQualityScore
    case officialCompositeScore
    case officialNote
}

private struct ComprehensiveQualityNumberField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    let focusedInput: FocusState<ComprehensiveQualityInputField?>.Binding
    let field: ComprehensiveQualityInputField

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(AppTheme.secondaryText)
            Spacer()
            TextField(placeholder, text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused(focusedInput, equals: field)
                .padding(.horizontal, 10)
                .frame(width: 132, height: 38)
                .background(AppTheme.softFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppTheme.separator, lineWidth: 1)
                }
        }
        .leafyBody()
    }
}

private struct ComprehensiveQualityDraft {
    var academicStandardScore = ""
    var officialQualityScore = ""
    var officialCompositeScore = ""
    var note = ""
    var components: [ComprehensiveQualityComponentKind: ComprehensiveQualityComponentDraft] = [:]

    init() {}

    init(record: ComprehensiveQualityRecord?, entries: [ComprehensiveQualityComponentEntry]) {
        academicStandardScore = Self.text(from: record?.academicStandardScore)
        officialQualityScore = Self.text(from: record?.officialQualityScore)
        officialCompositeScore = Self.text(from: record?.officialCompositeScore)
        note = record?.note ?? ""
        for entry in entries {
            components[ComprehensiveQualityComponentKind.normalized(entry.componentRawValue)] = ComprehensiveQualityComponentDraft(entry: entry)
        }
    }

    var academicStandardScoreValue: Double? { Self.double(from: academicStandardScore) }
    var officialQualityScoreValue: Double? { Self.double(from: officialQualityScore) }
    var officialCompositeScoreValue: Double? { Self.double(from: officialCompositeScore) }

    func componentInputs(for rule: ComprehensiveQualityCollegeRule) -> [ComprehensiveQualityComponentInput] {
        rule.components.map { componentRule in
            let draft = components[componentRule.kind] ?? ComprehensiveQualityComponentDraft()
            return ComprehensiveQualityComponentInput(
                kind: componentRule.kind,
                rawScore: draft.rawScoreValue,
                peerMaxScore: draft.peerMaxScoreValue,
                officialStandardScore: draft.officialStandardScoreValue
            )
        }
    }

    private static func double(from text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "，", with: ".")
        guard !normalized.isEmpty, let value = Double(normalized), value.isFinite else { return nil }
        return value
    }

    private static func text(from value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.2f", value)
    }
}

private struct ComprehensiveQualityComponentDraft {
    var rawScore = ""
    var peerMaxScore = ""
    var officialStandardScore = ""
    var materialReady = false
    var note = ""

    init() {}

    init(entry: ComprehensiveQualityComponentEntry) {
        rawScore = Self.text(from: entry.rawScore)
        peerMaxScore = Self.text(from: entry.peerMaxScore)
        officialStandardScore = Self.text(from: entry.officialStandardScore)
        materialReady = entry.materialReady
        note = entry.note
    }

    var rawScoreValue: Double? { Self.double(from: rawScore) }
    var peerMaxScoreValue: Double? { Self.double(from: peerMaxScore) }
    var officialStandardScoreValue: Double? { Self.double(from: officialStandardScore) }

    private static func double(from text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "，", with: ".")
        guard !normalized.isEmpty, let value = Double(normalized), value.isFinite else { return nil }
        return value
    }

    private static func text(from value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.2f", value)
    }
}

private struct ComprehensiveQualityCSVShareItem: Identifiable {
    let url: URL

    var id: URL { url }
}

private struct ComprehensiveQualityShareCard: View {
    let summary: ComprehensiveQualityExportSummary
    let materialReadyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(AppBrand.displayName) 综素测算")
                        .font(.system(size: 22, weight: .semibold))
                    Text(summary.collegeName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "function")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                shareMetric("学业标准分", scoreText(summary.academicStandardScore), "按 95% 折算")
                shareMetric("综素贡献", scoreText(summary.qualityContribution), "最多 5 分")
                shareMetric("综合成绩", scoreText(summary.compositeScore), "本地估算")
                shareMetric("材料状态", materialReadyText, "当前设备记录")
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(summary.componentDrafts, id: \.kind) { component in
                    HStack {
                        Text(component.kind.title)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text("\(scoreText(component.standardScore)) / \(scoreText(component.contribution))")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
            }
            .padding(12)
            .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))

            Text(summary.rule.sourceTitle)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(2)
        }
        .padding(18)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
    }

    private func shareMetric(_ title: String, _ value: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryText)
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }

    private func scoreText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.2f", value)
    }
}

private struct ComprehensiveQualityImagePreviewSheet: View {
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
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .leafyTrailing) {
                    Button("分享") {
                        isSharing = true
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $isSharing) {
                ShareSheet(activityItems: [image])
            }
        }
    }
}

private enum ComprehensiveQualityEvidenceFileStore {
    struct StoredFile {
        let localFilename: String
        let contentTypeIdentifier: String
    }

    static let allowedContentTypes: [UTType] = [.pdf, .image, .plainText, .data]

    static func importFile(from sourceURL: URL) throws -> StoredFile {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let extensionText = sourceURL.pathExtension
        let localFilename = extensionText.isEmpty
            ? UUID().uuidString
            : "\(UUID().uuidString).\(extensionText)"
        let destinationURL = directoryURL.appendingPathComponent(localFilename)

        if fileManager.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        let contentType = UTType(filenameExtension: extensionText)
            ?? sourceURL.resourceContentType
            ?? .data
        return StoredFile(
            localFilename: localFilename,
            contentTypeIdentifier: contentType.identifier
        )
    }

    static func deleteFile(named filename: String) throws {
        let url = directoryURL.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ComprehensiveQualityEvidence", isDirectory: true)
    }
}

private extension URL {
    var resourceContentType: UTType? {
        (try? resourceValues(forKeys: [.contentTypeKey]))?.contentType
    }
}

private extension ComprehensiveQualityEvidenceDocument {
    var displayType: String {
        LearningMaterialDocument.displayType(
            contentTypeIdentifier: contentTypeIdentifier,
            originalFilename: originalFilename
        )
    }

    var displayIcon: String {
        let type = UTType(contentTypeIdentifier)
        if type?.conforms(to: .pdf) == true { return "doc.richtext" }
        if type?.conforms(to: .image) == true { return "photo" }
        return "doc"
    }
}

#Preview {
    NavigationStack {
        ComprehensiveQualityView()
    }
}
