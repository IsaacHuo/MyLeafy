import Combine
import OSLog
import PhotosUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct CommunityComposerSheet: View {
    let onPosted: (String) -> Void
    let onDraftChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyDependencies) private var dependencies
    @ObservedObject private var sessionManager = CommunitySessionManager.shared

    private let initialDraftID: UUID?
    @State private var draftID: UUID
    @State private var draftExists: Bool
    @State private var composerMode: CommunityComposerMode = .post
    @State private var title = ""
    @State private var postBody = ""
    @State private var category = communityCategories[0]
    @State private var isAnonymous = false
    @State private var pollQuestion = ""
    @State private var pollDetail = ""
    @State private var pollOptions = ["", ""]
    @State private var pollHasDeadline = false
    @State private var pollClosesAt = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
    @State private var isSubmitting = false
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var draftImages: [CommunityDraftImage] = []
    @State private var draftAttachments: [CommunityDraftAttachment] = []
    @State private var showingAttachmentImporter = false
    @State private var errorMessage: String?
    @State private var showingProfileEditor = false
    @State private var showingTermsSheet = false
    @State private var showingNewDraftCloseConfirmation = false
    @State private var showingDraftSaveFailureConfirmation = false
    @State private var operationAlert: LeafyOperationAlert?
    @State private var draftSaveState: CommunityDraftSaveState = .idle
    @State private var draftSaveTask: Task<Void, Never>?
    @State private var isLoadingDraft = false
    @State private var draftLoadFailed = false
    @StateObject private var pollViewModel = CommunityPollsViewModel()

    init(
        draftID: UUID? = nil,
        onDraftChanged: @escaping () -> Void = {},
        onPosted: @escaping (String) -> Void
    ) {
        initialDraftID = draftID
        self.onDraftChanged = onDraftChanged
        self.onPosted = onPosted
        _draftID = State(initialValue: draftID ?? UUID())
        _draftExists = State(initialValue: draftID != nil)
    }

    private var communityAccessGate: CommunityAccessGate {
        CommunityAccessGate(
            sessionManager: sessionManager,
            termsChecker: dependencies.communityRepository
        )
    }

    private var pollInput: CreatePollInput {
        CreatePollInput(
            question: pollQuestion,
            detail: pollDetail,
            options: pollOptions,
            closesAt: pollHasDeadline ? ISO8601DateFormatter().string(from: pollClosesAt) : nil
        )
    }

    private var isSubmitDisabled: Bool {
        if isSubmitting { return true }

        switch composerMode {
        case .post:
            return title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || postBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .poll:
            return pollInput.validationError != nil
        }
    }

    private var autosaveSignature: CommunityDraftAutosaveSignature {
        CommunityDraftAutosaveSignature(
            mode: composerMode,
            title: title,
            body: postBody,
            category: category,
            isAnonymous: isAnonymous,
            imageIDs: draftImages.map(\.id),
            attachmentIDs: draftAttachments.map(\.id)
        )
    }

    private var hasMeaningfulDraftContent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !postBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !draftImages.isEmpty
            || !draftAttachments.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    LeafySectionTitle(composerMode.sectionTitle, subtitle: composerMode.subtitle)

                    if initialDraftID == nil {
                        Picker("发布类型", selection: $composerMode) {
                            ForEach(CommunityComposerMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("发布类型")
                    }

                    if let errorMessage {
                        CommunityInlineError(message: errorMessage)
                    }

                    if composerMode == .post, let statusText = draftSaveState.statusText {
                        Label(
                            statusText,
                            systemImage: draftSaveState.isFailure
                                ? "exclamationmark.triangle.fill"
                                : "checkmark.circle"
                        )
                        .microCaption()
                        .foregroundStyle(draftSaveState.isFailure ? AppTheme.danger : AppTheme.secondaryText)
                        .accessibilityLabel(statusText)
                    }

                    composerFields
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle("发布")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyLeading) {
                    Button("关闭") {
                        closeComposer()
                    }
                }
                ToolbarItem(placement: .leafyTrailing) {
                    Button(isSubmitting ? L10n.text("发布中", language: leafyLanguage) : L10n.text("发布", language: leafyLanguage)) {
                        Task { await submitCurrentMode() }
                    }
                    .disabled(isSubmitDisabled)
                }
            }
            .task {
                await sessionManager.restoreProfileIfPossible()
                loadInitialDraftIfNeeded()
                await preflightPostCreation()
            }
            .onDisappear {
                draftSaveTask?.cancel()
            }
            .onChange(of: selectedItems) { _, newValue in
                Task {
                    await loadSelectedImages(from: newValue)
                }
            }
            .onChange(of: composerMode) { oldMode, newMode in
                draftSaveTask?.cancel()
                errorMessage = nil
                if oldMode == .post, newMode == .poll,
                   draftExists {
                    saveDraftNow(allowWhenPoll: true)
                }
            }
            .onChange(of: autosaveSignature) { _, _ in
                scheduleDraftSave()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase != .active,
                      composerMode == .post,
                      CommunityComposerDraftPolicy.shouldAutosave(draftExists: draftExists)
                else {
                    return
                }
                draftSaveTask?.cancel()
                saveDraftNow()
            }
            .fileImporter(
                isPresented: $showingAttachmentImporter,
                allowedContentTypes: CommunityComposerAttachmentTypes.allowed,
                allowsMultipleSelection: true
            ) { result in
                handleAttachmentSelection(result)
            }
            .leafySheet(isPresented: $showingProfileEditor) {
                CommunityProfileEditorSheet()
                    .presentationDetents([.medium, .large])
            }
            .leafySheet(isPresented: $showingTermsSheet) {
                CommunityTermsAgreementSheet {
                    operationAlert = .success(L10n.text("设置已保存。", language: leafyLanguage))
                }
                    .presentationDetents([.large])
            }
            .confirmationDialog(
                "是否存入草稿箱？",
                isPresented: $showingNewDraftCloseConfirmation,
                titleVisibility: .visible
            ) {
                Button("存入草稿箱") {
                    saveNewDraftAndDismiss()
                }
                Button("放弃", role: .destructive) {
                    discardNewDraftAndDismiss()
                }
                Button("继续编辑", role: .cancel) {}
            } message: {
                Text("保存后可以在“我的发帖”中的草稿箱继续编辑。")
            }
            .confirmationDialog(
                "草稿修改尚未保存",
                isPresented: $showingDraftSaveFailureConfirmation,
                titleVisibility: .visible
            ) {
                Button("继续编辑", role: .cancel) {}
                Button("放弃未保存的更改", role: .destructive) {
                    dismiss()
                }
            } message: {
                Text("请检查设备存储空间后重试，或放弃这次未保存的更改。")
            }
            .interactiveDismissDisabled(
                draftExists || hasMeaningfulDraftContent
            )
            .leafyOperationAlert($operationAlert)
        }
    }

    @ViewBuilder
    private var composerFields: some View {
        switch composerMode {
        case .post:
            postFields
            imageFields
            attachmentFields
        case .poll:
            CommunityPollDraftFields(
                question: $pollQuestion,
                detail: $pollDetail,
                options: $pollOptions,
                hasDeadline: $pollHasDeadline,
                closesAt: $pollClosesAt
            )
        }
    }

    private var postFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("标题")
                .leafyHeadline()
            TextField("例如：图书馆晚上哪里更安静？", text: $title)
                .leafyDisableAutocapitalization()
                .padding(14)
                .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))

            Text("正文")
                .leafyHeadline()
            TextField("补充具体的问题或经验，便于他人回复。", text: $postBody, axis: .vertical)
                .lineLimit(8, reservesSpace: true)
                .padding(14)
                .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))

            Text("分类")
                .leafyHeadline()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(communityCategories, id: \.self) { option in
                        CommunityCategoryPill(
                            title: option,
                            isSelected: category == option
                        ) {
                            category = option
                        }
                    }
                }
            }

            Toggle("匿名发布", isOn: $isAnonymous)
                .tint(AppTheme.accent)
        }
        .padding(18)
        .leafyCardStyle()
    }

    private var imageFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("图片")
                    .leafyHeadline()
                Spacer()
                Text("\(draftImages.count)/\(CommunityImageUpload.postImageLimit)")
                    .microCaption()
                    .foregroundStyle(AppTheme.tertiaryText)
            }

            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: CommunityImageUpload.postImageLimit,
                matching: .images
            ) {
                HStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                    Text("选择图片")
                        .leafyBody()
                }
                .foregroundStyle(AppTheme.accentEmphasis)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(AppTheme.softFill, in: Capsule())
            }

            if !draftImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(draftImages) { draft in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: draft.image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 92, height: 92)
                                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))

                                Button {
                                    removeDraftImage(draft.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.white, .black.opacity(0.5))
                                }
                                .offset(x: 6, y: -6)
                            }
                        }
                    }
                }
            }
        }
        .padding(18)
        .leafyCardStyle()
    }

    private var attachmentFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("附件")
                    .leafyHeadline()
                Spacer()
                Text("\(draftAttachments.count)/\(CommunityPostAttachment.postAttachmentLimit)")
                    .microCaption()
                    .foregroundStyle(AppTheme.tertiaryText)
            }

            Button {
                showingAttachmentImporter = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "paperclip")
                    Text("添加 PDF、Excel、Word 或 Markdown")
                        .leafyBody()
                }
                .foregroundStyle(AppTheme.accentEmphasis)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(AppTheme.softFill, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(draftAttachments.count >= CommunityPostAttachment.postAttachmentLimit)

            ForEach(draftAttachments) { draft in
                HStack(spacing: 12) {
                    Image(systemName: CommunityComposerAttachmentTypes.systemImage(for: draft.upload.fileExtension))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AppTheme.accentEmphasis)
                        .frame(width: 34, height: 34)
                        .background(AppTheme.softFill, in: RoundedRectangle(cornerRadius: 9))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(draft.upload.displayName)
                            .leafyBody()
                            .lineLimit(1)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(draft.upload.byteSize), countStyle: .file))
                            .microCaption()
                            .foregroundStyle(AppTheme.tertiaryText)
                    }

                    Spacer()

                    Button {
                        removeDraftAttachment(draft.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("移除附件")
                }
            }

            Text("每个附件不超过 10 MB；附件会私密存储，下载时临时授权。")
                .microCaption()
                .foregroundStyle(AppTheme.tertiaryText)
        }
        .padding(18)
        .leafyCardStyle()
    }

    private func submitCurrentMode() async {
        switch composerMode {
        case .post:
            await submitPost()
        case .poll:
            await submitPoll()
        }
    }

    private func preflightPostCreation() async {
        switch await communityAccessGate.evaluate(.postCreation, forceBootstrap: true) {
        case .allowed:
            errorMessage = nil
        case .requiresProfileCompletion:
            showingProfileEditor = true
            errorMessage = L10n.text("第一次发帖前需要先完善社区资料。", language: leafyLanguage)
        case .requiresTermsAcceptance:
            showingTermsSheet = true
            errorMessage = L10n.text("发布前需要先同意社区条款。", language: leafyLanguage)
        case .failed(let message):
            errorMessage = message
        }
    }

    private func submitPost() async {
        isSubmitting = true
        defer { isSubmitting = false }

        switch await communityAccessGate.evaluate(.postCreation, forceBootstrap: true) {
        case .allowed:
            break
        case .requiresProfileCompletion:
            showingProfileEditor = true
            errorMessage = L10n.text("第一次发帖前需要先完善社区资料。", language: leafyLanguage)
            return
        case .requiresTermsAcceptance:
            showingTermsSheet = true
            errorMessage = L10n.text("发布前需要先同意社区条款。", language: leafyLanguage)
            return
        case .failed(let message):
            errorMessage = message
            return
        }

        do {
            let handoff = try CommunityPostDraftPublishHandoff.enqueue(
                draftID: draftExists ? draftID : nil,
                ownerProfileID: sessionManager.currentUserID,
                repository: dependencies.communityPostDraftRepository
            ) {
                try dependencies.communityRepository.enqueuePostPublication(
                    input: CreatePostInput(
                        title: title,
                        body: postBody,
                        category: category,
                        isAnonymous: isAnonymous
                    ),
                    images: draftImages.map(\.upload),
                    attachments: draftAttachments.map(\.upload)
                )
            }
            var postedMessage = L10n.text(
                "已加入发布队列，可在社区顶部查看进度。",
                language: leafyLanguage
            )
            if handoff.deletedDraft {
                draftExists = false
                onDraftChanged()
            } else if let cleanupError = handoff.draftCleanupError {
                postedMessage = L10n.text(
                    "帖子已加入发布队列，但草稿未能删除：%@",
                    language: leafyLanguage,
                    cleanupError
                )
            }
            cleanupComposerAttachments()
            onPosted(postedMessage)
            dismiss()
        } catch {
            if error.localizedDescription == CommunityServiceError.profileCompletionRequired.localizedDescription {
                showingProfileEditor = true
            } else if error.localizedDescription == CommunityServiceError.termsAcceptanceRequired.localizedDescription {
                showingTermsSheet = true
            }
            errorMessage = error.localizedDescription
        }
    }

    private func submitPoll() async {
        isSubmitting = true
        defer { isSubmitting = false }

        switch await communityAccessGate.evaluate(.postCreation, forceBootstrap: true) {
        case .allowed:
            break
        case .requiresProfileCompletion:
            showingProfileEditor = true
            errorMessage = L10n.text("发布投票前需要先完善社区资料。", language: leafyLanguage)
            return
        case .requiresTermsAcceptance:
            showingTermsSheet = true
            errorMessage = L10n.text("发布投票前需要先同意社区条款。", language: leafyLanguage)
            return
        case .failed(let message):
            errorMessage = message
            return
        }

        if await pollViewModel.createPoll(input: pollInput) {
            onPosted(L10n.text("投票已提交审核。", language: leafyLanguage))
            dismiss()
        } else {
            errorMessage = pollViewModel.errorMessage
        }
    }

    private func loadSelectedImages(from items: [PhotosPickerItem]) async {
        errorMessage = nil
        var loaded: [CommunityDraftImage] = []
        if items.count > CommunityImageUpload.postImageLimit {
            errorMessage = L10n.text("单条帖子最多上传 %d 张图片。", language: leafyLanguage, CommunityImageUpload.postImageLimit)
        }

        for item in items.prefix(CommunityImageUpload.postImageLimit) {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    continue
                }

                let result = try await dependencies.communityImageProcessor.compressedJPEG(
                    from: data,
                    maxPixelDimension: CommunityImageUpload.postImageMaxPixelDimension,
                    maxBytes: CommunityImageUpload.postImageMaxBytes
                )
                guard let preview = ImageDataDecoder.decodedImage(
                    from: result.previewData,
                    targetSize: CGSize(width: 420, height: 420)
                ) else {
                    continue
                }

                loaded.append(CommunityDraftImage(id: result.upload.id, image: preview, upload: result.upload))
            } catch {
                errorMessage = L10n.text("加载图片失败：%@", language: leafyLanguage, error.localizedDescription)
            }
        }

        draftImages = loaded
    }

    private func removeDraftImage(_ id: UUID) {
        draftImages.removeAll { $0.id == id }
    }

    private func handleAttachmentSelection(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            let remaining = CommunityPostAttachment.postAttachmentLimit - draftAttachments.count
            guard remaining > 0 else { return }
            if urls.count > remaining {
                errorMessage = "单条帖子最多上传 2 个附件。"
            }
            for url in urls.prefix(remaining) {
                draftAttachments.append(
                    CommunityDraftAttachment(upload: try stageAttachment(from: url))
                )
            }
        } catch {
            errorMessage = "添加附件失败：\(error.localizedDescription)"
        }
    }

    private func stageAttachment(from sourceURL: URL) throws -> CommunityAttachmentUpload {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileExtension = sourceURL.pathExtension.lowercased()
        guard CommunityPostAttachment.supportedExtensions.contains(fileExtension) else {
            throw CommunityComposerAttachmentError.unsupportedType
        }

        let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let byteSize = values.fileSize, byteSize > 0 else {
            throw CommunityComposerAttachmentError.unreadableFile
        }
        guard byteSize <= CommunityPostAttachment.maxBytes else {
            throw CommunityComposerAttachmentError.fileTooLarge
        }

        let directory = try CommunityComposerAttachmentTypes.stagingDirectory()
        let id = UUID()
        let destination = directory.appendingPathComponent("\(id.uuidString.lowercased()).\(fileExtension)")
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: destination.path
        )

        return CommunityAttachmentUpload(
            id: id,
            localURL: destination,
            displayName: CommunityComposerAttachmentTypes.sanitizedDisplayName(sourceURL.lastPathComponent),
            contentType: CommunityComposerAttachmentTypes.contentType(for: fileExtension),
            fileExtension: fileExtension,
            byteSize: byteSize
        )
    }

    private func removeDraftAttachment(_ id: UUID) {
        draftAttachments.removeAll { $0.id == id }
    }

    private func cleanupComposerAttachments() {
        for draft in draftAttachments {
            try? FileManager.default.removeItem(at: draft.upload.localURL)
        }
        draftAttachments.removeAll()
    }

    private func loadInitialDraftIfNeeded() {
        guard let initialDraftID, let ownerProfileID = sessionManager.currentUserID else { return }
        isLoadingDraft = true
        defer { isLoadingDraft = false }

        do {
            let payload = try dependencies.communityPostDraftRepository.loadDraft(
                id: initialDraftID,
                ownerProfileID: ownerProfileID
            )
            title = payload.draft.input.title
            postBody = payload.draft.input.body
            category = payload.draft.input.category ?? communityCategories[0]
            isAnonymous = payload.draft.input.isAnonymous
            draftImages = try payload.images.map { upload in
                guard let preview = ImageDataDecoder.decodedImage(
                    from: upload.data,
                    targetSize: CGSize(width: 420, height: 420)
                ) else {
                    throw CommunityPostDraftError.invalidImage(upload.id.uuidString)
                }
                return CommunityDraftImage(id: upload.id, image: preview, upload: upload)
            }
            draftAttachments = payload.attachments.map(CommunityDraftAttachment.init(upload:))
            draftLoadFailed = false
            draftSaveState = .saved(payload.draft.updatedAt)
        } catch {
            draftLoadFailed = true
            errorMessage = error.localizedDescription
            draftSaveState = .failed(error.localizedDescription)
        }
    }

    private func scheduleDraftSave() {
        guard !isLoadingDraft, composerMode == .post else { return }
        draftSaveTask?.cancel()
        guard CommunityComposerDraftPolicy.shouldAutosave(draftExists: draftExists) else {
            draftSaveState = .idle
            return
        }

        draftSaveState = .saving
        draftSaveTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                saveDraftNow()
            } catch {
                return
            }
        }
    }

    private func saveDraftNow(allowWhenPoll: Bool = false) {
        guard composerMode == .post || allowWhenPoll,
              draftExists || hasMeaningfulDraftContent else { return }
        guard !draftLoadFailed else {
            let message = draftSaveState.failureMessage
                ?? L10n.text("草稿读取失败，无法安全覆盖原文件。")
            draftSaveState = .failed(message)
            errorMessage = message
            return
        }
        guard let ownerProfileID = sessionManager.currentUserID else {
            let message = L10n.text("当前社区身份不可用，草稿尚未保存。请继续编辑或放弃更改。")
            draftSaveState = .failed(message)
            errorMessage = message
            return
        }

        draftSaveTask?.cancel()
        draftSaveState = .saving
        let previousAttachmentURLs = draftAttachments.map(\.upload.localURL)

        do {
            let payload = try dependencies.communityPostDraftRepository.saveDraft(
                id: draftID,
                ownerProfileID: ownerProfileID,
                input: CreatePostInput(
                    title: title,
                    body: postBody,
                    category: category,
                    isAnonymous: isAnonymous
                ),
                images: draftImages.map(\.upload),
                attachments: draftAttachments.map(\.upload)
            )
            draftExists = true
            draftImages = try payload.images.map { upload in
                guard let preview = ImageDataDecoder.decodedImage(
                    from: upload.data,
                    targetSize: CGSize(width: 420, height: 420)
                ) else {
                    throw CommunityPostDraftError.invalidImage(upload.id.uuidString)
                }
                return CommunityDraftImage(id: upload.id, image: preview, upload: upload)
            }
            draftAttachments = payload.attachments.map(CommunityDraftAttachment.init(upload:))
            for url in previousAttachmentURLs
            where url.path.contains("CommunityComposerAttachments")
                && !draftAttachments.contains(where: { $0.upload.localURL == url }) {
                try? FileManager.default.removeItem(at: url)
            }
            draftSaveState = .saved(payload.draft.updatedAt)
            onDraftChanged()
        } catch {
            draftSaveState = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    private func closeComposer() {
        draftSaveTask?.cancel()
        guard composerMode == .post || draftExists || hasMeaningfulDraftContent else {
            dismiss()
            return
        }

        switch CommunityComposerDraftPolicy.closeAction(
            draftExists: draftExists,
            hasMeaningfulContent: hasMeaningfulDraftContent
        ) {
        case .dismiss:
            dismiss()

        case .saveExistingDraft:
            saveDraftNow()
            if draftSaveState.isFailure {
                showingDraftSaveFailureConfirmation = true
                return
            }
            dismiss()

        case .askToSaveNewDraft:
            showingNewDraftCloseConfirmation = true
        }
    }

    private func saveNewDraftAndDismiss() {
        saveDraftNow(allowWhenPoll: composerMode == .poll)
        guard !draftSaveState.isFailure else { return }
        dismiss()
    }

    private func discardNewDraftAndDismiss() {
        cleanupComposerAttachments()
        dismiss()
    }
}
