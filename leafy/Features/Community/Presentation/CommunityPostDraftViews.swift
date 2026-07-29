import SwiftUI

private struct CommunityPostDraftSelection: Identifiable {
    let id: UUID
}

struct CommunityPostDraftsView: View {
    @Environment(\.leafyDependencies) private var dependencies
    @ObservedObject private var sessionManager = CommunitySessionManager.shared

    @State private var drafts: [CommunityPostDraft] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedDraft: CommunityPostDraftSelection?
    @State private var deletingDraft: CommunityPostDraft?
    @State private var cardSource: CommunityPostCardPreviewSource?
    @State private var operationAlert: LeafyOperationAlert?

    var body: some View {
        List {
            content
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(LeafyPageBackground())
        .navigationTitle("草稿箱")
        .leafyInlineNavigationTitle()
        .task {
            await load()
        }
        .refreshable {
            await load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .communityPostDraftsDidChange)) { notification in
            guard notification.object as? UUID == sessionManager.currentUserID else { return }
            Task { await load() }
        }
        .sheet(item: $selectedDraft) { selection in
            CommunityComposerSheet(
                draftID: selection.id,
                onDraftChanged: {
                    Task { await load() }
                }
            ) { message in
                operationAlert = .success(message)
                Task { await load() }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $cardSource) { source in
            CommunityPostCardPreviewSheet(source: source)
        }
        .confirmationDialog(
            "删除这份草稿？",
            isPresented: Binding(
                get: { deletingDraft != nil },
                set: { if !$0 { deletingDraft = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                deleteSelectedDraft()
            }
            Button("取消", role: .cancel) {
                deletingDraft = nil
            }
        } message: {
            Text("草稿正文、图片和附件都会从本机删除，且无法恢复。")
        }
        .leafyOperationAlert($operationAlert)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && drafts.isEmpty {
            Section {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else if let errorMessage, drafts.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(errorMessage)
                        .leafyBody()
                        .foregroundStyle(AppTheme.secondaryText)
                    Button("重试") {
                        Task { await load() }
                    }
                }
                .padding(.vertical, 12)
            }
        } else if drafts.isEmpty {
            Section {
                ContentUnavailableView(
                    "暂无草稿",
                    systemImage: "doc.text",
                    description: Text("保存的帖子会显示在这里。")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .leafyBody()
                        .foregroundStyle(AppTheme.danger)
                }
            }

            Section {
                ForEach(drafts) { draft in
                    CommunityPostDraftRow(draft: draft)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedDraft = CommunityPostDraftSelection(id: draft.id)
                        }
                        .contextMenu {
                            Button {
                                generateCard(for: draft)
                            } label: {
                                Label("生成图文卡片", systemImage: "rectangle.on.rectangle.angled")
                            }
                            Button(role: .destructive) {
                                deletingDraft = draft
                            } label: {
                                Label("删除草稿", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deletingDraft = draft
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            .tint(AppTheme.danger)
                            Button {
                                generateCard(for: draft)
                            } label: {
                                Label("卡片", systemImage: "rectangle.on.rectangle.angled")
                            }
                            .tint(AppTheme.accent)
                        }
                        .listRowInsets(
                            EdgeInsets(
                                top: 6,
                                leading: AppSpacing.page,
                                bottom: 6,
                                trailing: AppSpacing.page
                            )
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        }
    }

    @MainActor
    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        await sessionManager.restoreProfileIfPossible()
        guard let ownerProfileID = sessionManager.currentUserID else {
            drafts = []
            errorMessage = CommunityServiceError.missingAuthenticatedUser.localizedDescription
            return
        }

        do {
            drafts = try dependencies.communityPostDraftRepository.listDrafts(
                ownerProfileID: ownerProfileID
            )
            errorMessage = nil
        } catch {
            drafts = []
            errorMessage = error.localizedDescription
        }
    }

    private func generateCard(for draft: CommunityPostDraft) {
        guard let ownerProfileID = sessionManager.currentUserID,
              let profile = sessionManager.profile else {
            errorMessage = CommunityServiceError.missingAuthenticatedUser.localizedDescription
            return
        }
        do {
            let payload = try dependencies.communityPostDraftRepository.loadDraft(
                id: draft.id,
                ownerProfileID: ownerProfileID
            )
            cardSource = CommunityPostCardPreviewSource(content: .draft(payload, profile))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteSelectedDraft() {
        guard let draft = deletingDraft,
              let ownerProfileID = sessionManager.currentUserID else { return }
        deletingDraft = nil
        do {
            try dependencies.communityPostDraftRepository.deleteDraft(
                id: draft.id,
                ownerProfileID: ownerProfileID
            )
            drafts.removeAll { $0.id == draft.id }
            operationAlert = .success("草稿已删除。")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CommunityPostDraftRow: View {
    let draft: CommunityPostDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(draft.displayTitle)
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.tertiaryText)
            }

            Text(draft.bodyPreview)
                .leafyBody()
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(2)

            HStack(spacing: 10) {
                Label(
                    CommunityPostCategory.normalized(draft.input.category) ?? L10n.text("社区"),
                    systemImage: draft.input.isAnonymous ? "person.crop.circle.badge.questionmark" : "tag"
                )
                if !draft.images.isEmpty {
                    Label("\(draft.images.count)", systemImage: "photo")
                }
                if !draft.attachments.isEmpty {
                    Label("\(draft.attachments.count)", systemImage: "paperclip")
                }
                Spacer()
                Text(DateFormatters.headerWithTime.string(from: draft.updatedAt))
            }
            .microCaption()
            .foregroundStyle(AppTheme.tertiaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppTheme.cardBackground,
            in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                .stroke(AppTheme.separator, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开并继续编辑草稿")
    }
}
