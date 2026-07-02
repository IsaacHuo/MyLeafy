import SwiftData
import SwiftUI

struct ExternalLearningMaterialImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.leafyLanguage) private var leafyLanguage
    @ObservedObject private var coordinator: ExternalLearningMaterialImportCoordinator
    @ObservedObject private var appNavigation: AppNavigationCoordinator

    let batch: ExternalLearningMaterialImportManifest

    @Query(sort: \LearningProject.updatedAt, order: .reverse) private var projects: [LearningProject]
    @State private var destination = LearningWorkspaceDestination.fixed(.courseware)
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        batch: ExternalLearningMaterialImportManifest,
        coordinator: ExternalLearningMaterialImportCoordinator,
        appNavigation: AppNavigationCoordinator
    ) {
        self.batch = batch
        self._coordinator = ObservedObject(initialValue: coordinator)
        self._appNavigation = ObservedObject(initialValue: appNavigation)
    }

    private var activeProjects: [LearningProject] {
        projects.filter { !$0.isArchived }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("保存位置") {
                    Picker("学习空间", selection: $destination) {
                        ForEach(LearningMaterialCategory.fixedSpaceOrder) { category in
                            Label(category.rawValue, systemImage: icon(for: category))
                                .tag(LearningWorkspaceDestination.fixed(category))
                        }

                        if !activeProjects.isEmpty {
                            Divider()
                            ForEach(activeProjects) { project in
                                Label(project.title, systemImage: project.kind.icon)
                                    .tag(LearningWorkspaceDestination.project(project.id))
                            }
                        }
                    }
                }

                Section("待保存文件") {
                    ForEach(batch.items) { item in
                        HStack(spacing: AppSpacing.compact) {
                            LeafyIconBadge(systemName: icon(for: item))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.originalFilename)
                                    .leafySubheadline(weight: .semibold)
                                    .foregroundStyle(AppTheme.primaryText)
                                    .lineLimit(2)
                                Text(fileSubtitle(for: item))
                                    .leafyCaption()
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    Text("文件会保存到本机学习空间，不会上传到云端。")
                        .leafyFootnote()
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .navigationTitle("保存到学习空间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        coordinator.cancel(batch)
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中" : "保存") {
                        save()
                    }
                    .disabled(isSaving)
                }
            }
            .alert("保存失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        isSaving = true
        do {
            _ = try coordinator.importBatch(
                batch,
                to: destination,
                modelContext: modelContext,
                appNavigation: appNavigation
            )
            isSaving = false
            dismiss()
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
        }
    }

    private func fileSubtitle(for item: ExternalLearningMaterialImportItem) -> String {
        let displayType = LearningMaterialDocument.displayType(
            contentTypeIdentifier: item.contentTypeIdentifier,
            originalFilename: item.originalFilename
        )
        guard item.byteCount > 0 else { return displayType }
        return "\(displayType) · \(ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file))"
    }

    private func icon(for item: ExternalLearningMaterialImportItem) -> String {
        let displayType = LearningMaterialDocument.displayType(
            contentTypeIdentifier: item.contentTypeIdentifier,
            originalFilename: item.originalFilename
        )
        switch displayType {
        case "PDF":
            return "doc.richtext"
        case "图片":
            return "photo"
        case "Word":
            return "doc.text"
        case "PPT":
            return "rectangle.on.rectangle.angled"
        default:
            return "doc"
        }
    }

    private func icon(for category: LearningMaterialCategory) -> String {
        switch category {
        case .cet:
            return "character.book.closed"
        case .exam:
            return "doc.text.magnifyingglass"
        case .courseware:
            return "rectangle.on.rectangle.angled"
        case .other:
            return "tray.full"
        }
    }
}
