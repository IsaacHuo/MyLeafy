import Combine
import OSLog
import PhotosUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

private struct CommunityCommentComposerHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct RealCommunityPostDetailSheet: View {
    let post: CommunityPost
    let onPostChanged: (CommunityPost) -> Void
    let onPostRemoved: () -> Void

    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyDependencies) private var dependencies
    @StateObject private var viewModel: CommunityPostDetailViewModel
    @ObservedObject private var sessionManager = CommunitySessionManager.shared
    @State private var commentBody = ""
    @State private var showingProfileEditor = false
    @State private var showingTermsSheet = false
    @State private var reportTarget: CommunityModerationTarget?
    @State private var blockTarget: CommunityModerationTarget?
    @State private var showingDeletePostConfirmation = false
    @State private var operationAlert: LeafyOperationAlert?
    @State private var isCommentSubmitInFlight = false
    @State private var replyTarget: CommunityComment?
    @State private var downloadingAttachmentIDs: Set<UUID> = []
    @State private var attachmentDownloadError: String?
    @State private var attachmentPreview: CommunityAttachmentPreview?
    @State private var commentComposerHeight: CGFloat = 0
    @FocusState private var isCommentFieldFocused: Bool

    private var communityAccessGate: CommunityAccessGate {
        CommunityAccessGate(
            sessionManager: sessionManager,
            termsChecker: dependencies.communityRepository
        )
    }

    init(
        post: CommunityPost,
        onPostChanged: @escaping (CommunityPost) -> Void = { _ in },
        onPostRemoved: @escaping () -> Void = {}
    ) {
        self.post = post
        self.onPostChanged = onPostChanged
        self.onPostRemoved = onPostRemoved
        _viewModel = StateObject(wrappedValue: CommunityPostDetailViewModel(post: post))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    RealCommunityPostCard(
                        post: viewModel.post,
                        showsImageStrip: true,
                        showsBody: true,
                        isLikeLoading: viewModel.isLikeLoading,
                        isFavoriteLoading: viewModel.isFavoriteLoading,
                        isLikeDisabled: viewModel.post.authorID == sessionManager.currentUserID,
                        canDelete: viewModel.post.authorID == sessionManager.currentUserID,
                        onReport: {
                            reportTarget = .post(viewModel.post)
                        },
                        onBlock: {
                            blockTarget = .post(viewModel.post)
                        },
                        onDelete: {
                            showingDeletePostConfirmation = true
                        },
                        onToggleLike: {
                            switch await communityAccessGate.evaluate(.profileInteraction, forceBootstrap: true) {
                            case .allowed:
                                break
                            case .requiresProfileCompletion:
                                viewModel.errorMessage = L10n.text("点赞前需要先完善社区资料。", language: leafyLanguage)
                                showingProfileEditor = true
                                return
                            case .requiresTermsAcceptance:
                                showingTermsSheet = true
                                return
                            case .failed(let message):
                                viewModel.errorMessage = message
                                return
                            }

                            if let updatedPost = await viewModel.toggleLike() {
                                onPostChanged(updatedPost)
                            }
                        },
                        onToggleFavorite: {
                            switch await communityAccessGate.evaluate(.profileInteraction, forceBootstrap: true) {
                            case .allowed:
                                break
                            case .requiresProfileCompletion:
                                viewModel.errorMessage = L10n.text("收藏前需要先完善社区资料。", language: leafyLanguage)
                                showingProfileEditor = true
                                return
                            case .requiresTermsAcceptance:
                                showingTermsSheet = true
                                return
                            case .failed(let message):
                                viewModel.errorMessage = message
                                return
                            }

                            if let updatedPost = await viewModel.toggleFavorite() {
                                onPostChanged(updatedPost)
                                operationAlert = .success(
                                    updatedPost.viewerHasFavorited
                                        ? L10n.text("已添加收藏。", language: leafyLanguage)
                                        : L10n.text("已取消收藏。", language: leafyLanguage)
                                )
                            }
                        }
                    )

                    if !viewModel.post.attachments.isEmpty {
                        CommunityPostAttachmentsSection(
                            attachments: viewModel.post.attachments,
                            downloadingIDs: downloadingAttachmentIDs,
                            errorMessage: attachmentDownloadError,
                            onOpen: { attachment in
                                Task { await openAttachment(attachment) }
                            }
                        )
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("评论区")
                            .leafyHeadline()

                        if viewModel.isLoading && viewModel.comments.isEmpty {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        } else if let errorMessage = viewModel.errorMessage, viewModel.comments.isEmpty {
                            CommunityErrorCard(message: errorMessage) {
                                Task { await viewModel.load() }
                            }
                        } else if viewModel.comments.isEmpty {
                            Text("暂无评论。")
                                .leafyBody()
                                .foregroundStyle(AppTheme.secondaryText)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .leafyCardStyle()
                        } else {
                            ForEach(viewModel.commentThreads) { thread in
                                commentCard(thread.root)

                                if !thread.replies.isEmpty {
                                    VStack(spacing: 10) {
                                        ForEach(thread.replies) { reply in
                                            commentCard(reply)
                                        }
                                    }
                                    .padding(.leading, 28)
                                }
                            }

                            if viewModel.nextCommentCursor != nil {
                                Button {
                                    Task { await viewModel.loadMoreComments() }
                                } label: {
                                    HStack(spacing: 8) {
                                        if viewModel.isLoadingMoreComments {
                                            ProgressView()
                                                .controlSize(.small)
                                        }
                                        Text(viewModel.isLoadingMoreComments ? "正在加载" : "加载更多评论")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .disabled(viewModel.isLoadingMoreComments)
                            }
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.page)
                .padding(.top, 8)
                .padding(.bottom, max(AppSpacing.page, commentComposerHeight))
            }
            .background(LeafyPageBackground())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("帖子详情")
            .leafyInlineNavigationTitle()
            .overlay(alignment: .bottom) {
                commentComposerOverlay
            }
            .task {
                await viewModel.load()
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
            .sheet(item: $attachmentPreview) { preview in
                CommunityAttachmentPreviewSheet(url: preview.url)
            }
            .leafyOperationAlert($operationAlert)
            .confirmationDialog("举报内容", isPresented: Binding(
                get: { reportTarget != nil },
                set: { if !$0 { reportTarget = nil } }
            ), titleVisibility: .visible) {
                ForEach(communityReportReasons, id: \.self) { reason in
                    Button(reason) {
                        submitReport(reason: reason)
                    }
                }
                Button("取消", role: .cancel) {
                    reportTarget = nil
                }
            } message: {
                Text("举报后该内容会立即从你的页面移除，并进入 24 小时审核队列。")
            }
            .confirmationDialog("屏蔽该用户？", isPresented: Binding(
                get: { blockTarget != nil },
                set: { if !$0 { blockTarget = nil } }
            ), titleVisibility: .visible) {
                Button("屏蔽", role: .destructive) {
                    blockSelectedAuthor()
                }
                Button("取消", role: .cancel) {
                    blockTarget = nil
                }
            } message: {
                Text("屏蔽后将不再看到该用户的帖子、评论和通知。")
            }
            .confirmationDialog("删除这条帖子？", isPresented: $showingDeletePostConfirmation, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    Task { await deleteCurrentPost() }
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    private var isSubmitDisabled: Bool {
        isCommentSubmitInFlight
            || viewModel.isSubmitting
            || CommunityCommentComposerPolicy.submissionBody(
                from: commentBody,
                replyingTo: replyTarget
            ).isEmpty
    }

    private func commentCard(_ comment: CommunityComment) -> CommunityCommentCard {
        CommunityCommentCard(
            comment: comment,
            canDelete: comment.authorID == sessionManager.currentUserID,
            canReply: CommunityCommentInteractionPolicy.canReply(
                to: comment,
                viewerID: sessionManager.currentUserID
            ),
            canLike: CommunityCommentInteractionPolicy.canLike(
                comment,
                viewerID: sessionManager.currentUserID
            ),
            isLikeLoading: viewModel.activeCommentLikeIDs.contains(comment.id),
            onReply: { beginReply(to: comment) },
            onToggleLike: { Task { await toggleCommentLike(comment) } },
            onReport: { reportTarget = .comment(comment) },
            onBlock: { blockTarget = .comment(comment) },
            onDelete: { Task { await deleteComment(comment) } }
        )
    }

    private var commentComposer: some View {
        HStack(alignment: .bottom, spacing: 4) {
            commentField

            sendButton
                .frame(width: 44, height: 44)
        }
        .padding(.leading, 14)
        .padding(.trailing, 2)
        .frame(minHeight: 44)
        .leafyGlassSurface(
            in: Capsule(),
            isInteractive: true
        )
    }

    private var commentComposerOverlay: some View {
        VStack(spacing: 10) {
            if let errorMessage = viewModel.errorMessage, !errorMessage.isEmpty {
                CommunityInlineError(message: errorMessage)
                    .padding(.horizontal, AppSpacing.page)
            }

            LeafyGlassGroup(spacing: 8) {
                commentComposer
            }
            .padding(.horizontal, AppSpacing.page)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CommunityCommentComposerHeightKey.self,
                    value: proxy.size.height
                )
            }
        }
        .onPreferenceChange(CommunityCommentComposerHeightKey.self) { height in
            commentComposerHeight = height
        }
    }

    private var commentField: some View {
        TextField("写评论…", text: $commentBody, axis: .vertical)
            .lineLimit(1...3)
            .focused($isCommentFieldFocused)
            .onChange(of: commentBody) { previousBody, newBody in
                guard let replyTarget else { return }
                if !CommunityCommentComposerPolicy.retainsReplyTarget(replyTarget, in: newBody) {
                    self.replyTarget = nil
                    let updatedBody = CommunityCommentComposerPolicy.bodyAfterEditingReplyMention(
                        previousBody: previousBody,
                        newBody: newBody,
                        target: replyTarget
                    )
                    if updatedBody != newBody {
                        commentBody = updatedBody
                    }
                }
            }
            .leafyBody()
            .padding(.vertical, 10)
            .frame(minHeight: 44, alignment: .center)
    }

    @ViewBuilder
    private var sendButton: some View {
        if #available(iOS 26.0, *) {
            Button {
                Task { await submitComment() }
            } label: {
                sendButtonLabel
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .controlSize(.regular)
            .tint(AppTheme.accent)
            .disabled(isSubmitDisabled)
            .accessibilityLabel(isCommentSubmitInFlight ? "正在发送评论" : "发送评论")
        } else {
            standardSendButton
        }
    }

    private var standardSendButton: some View {
        Button {
            Task { await submitComment() }
        } label: {
            sendButtonLabel
                .foregroundStyle(AppTheme.textOnAccent)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(isSubmitDisabled ? AppTheme.accent.opacity(0.45) : AppTheme.accent)
                )
        }
        .buttonStyle(.plain)
        .disabled(isSubmitDisabled)
        .accessibilityLabel(isCommentSubmitInFlight ? "正在发送评论" : "发送评论")
    }

    @ViewBuilder
    private var sendButtonLabel: some View {
        if isCommentSubmitInFlight {
            ProgressView()
                .controlSize(.small)
                .frame(width: 20, height: 20)
        } else {
            Image(systemName: "arrow.up")
                .font(.system(size: 17, weight: .bold))
                .frame(width: 20, height: 20)
        }
    }

    @MainActor
    private func submitComment() async {
        guard !isCommentSubmitInFlight else { return }
        let pendingReplyTarget = replyTarget
        let pendingBody = CommunityCommentComposerPolicy.submissionBody(
            from: commentBody,
            replyingTo: pendingReplyTarget
        )
        guard !pendingBody.isEmpty else { return }

        isCommentSubmitInFlight = true
        defer { isCommentSubmitInFlight = false }

        switch await communityAccessGate.evaluate(.commentCreation, forceBootstrap: true) {
        case .allowed:
            break
        case .requiresProfileCompletion:
            viewModel.errorMessage = L10n.text("评论前需要先完善社区资料。", language: leafyLanguage)
            showingProfileEditor = true
            return
        case .requiresTermsAcceptance:
            viewModel.errorMessage = L10n.text("评论前需要先同意社区条款。", language: leafyLanguage)
            showingTermsSheet = true
            return
        case .failed(let message):
            viewModel.errorMessage = message
            return
        }

        let didSucceed = await viewModel.submitComment(body: pendingBody, replyingTo: pendingReplyTarget)
        if didSucceed {
            commentBody = ""
            replyTarget = nil
            isCommentFieldFocused = false
            operationAlert = .success(L10n.text("评论发布成功。", language: leafyLanguage))
        }
    }

    @MainActor
    private func beginReply(to target: CommunityComment) {
        let updatedBody = CommunityCommentComposerPolicy.draft(
            bySelecting: target,
            currentBody: commentBody,
            previousTarget: replyTarget
        )
        replyTarget = target
        commentBody = updatedBody
        isCommentFieldFocused = true
    }

    @MainActor
    private func toggleCommentLike(_ comment: CommunityComment) async {
        switch await communityAccessGate.evaluate(.profileInteraction, forceBootstrap: true) {
        case .allowed:
            await viewModel.toggleCommentLike(comment)
        case .requiresProfileCompletion:
            viewModel.errorMessage = L10n.text("点赞前需要先完善社区资料。", language: leafyLanguage)
            showingProfileEditor = true
        case .requiresTermsAcceptance:
            showingTermsSheet = true
        case .failed(let message):
            viewModel.errorMessage = message
        }
    }

    @MainActor
    private func openAttachment(_ attachment: CommunityPostAttachment) async {
        guard !downloadingAttachmentIDs.contains(attachment.id) else { return }
        downloadingAttachmentIDs.insert(attachment.id)
        attachmentDownloadError = nil
        defer { downloadingAttachmentIDs.remove(attachment.id) }

        do {
            let download = try await dependencies.communityRepository.attachmentDownloadURL(
                attachmentID: attachment.id
            )
            let (temporaryURL, response) = try await URLSession.shared.download(from: download.url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw CommunityComposerAttachmentError.unreadableFile
            }

            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("CommunityAttachmentPreviews", isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let previewURL = directory.appendingPathComponent(
                "\(UUID().uuidString)-\(CommunityComposerAttachmentTypes.sanitizedDisplayName(download.displayName))"
            )
            try FileManager.default.moveItem(at: temporaryURL, to: previewURL)
            attachmentPreview = CommunityAttachmentPreview(url: previewURL)
        } catch {
            attachmentDownloadError = "附件下载失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func submitReport(reason: String) {
        guard let target = reportTarget else { return }
        reportTarget = nil
        Task {
            switch target {
            case .post:
                if await viewModel.reportPost(reason: reason) {
                    operationAlert = .success(
                        L10n.text("举报已提交。", language: leafyLanguage),
                        action: {
                            onPostRemoved()
                            dismiss()
                        }
                    )
                }
            case .comment(let comment):
                await viewModel.reportComment(comment, reason: reason)
                if viewModel.errorMessage == nil {
                    operationAlert = .success(L10n.text("举报已提交。", language: leafyLanguage))
                }
            }
        }
    }

    @MainActor
    private func blockSelectedAuthor() {
        guard let target = blockTarget else { return }
        blockTarget = nil
        Task {
            switch target {
            case .post:
                if await viewModel.blockPostAuthor() {
                    operationAlert = .success(
                        L10n.text("已屏蔽该用户。", language: leafyLanguage),
                        action: {
                            onPostRemoved()
                            dismiss()
                        }
                    )
                }
            case .comment(let comment):
                await viewModel.blockCommentAuthor(comment)
                if viewModel.errorMessage == nil {
                    operationAlert = .success(L10n.text("已屏蔽该用户。", language: leafyLanguage))
                }
            }
        }
    }

    @MainActor
    private func deleteCurrentPost() async {
        if await viewModel.deletePost() {
            operationAlert = .success(
                L10n.text("帖子已删除。", language: leafyLanguage),
                action: {
                    onPostRemoved()
                    dismiss()
                }
            )
        }
    }

    @MainActor
    private func deleteComment(_ comment: CommunityComment) async {
        do {
            try await dependencies.communityRepository.deleteComment(commentID: comment.id)
            await viewModel.load()
            operationAlert = .success(L10n.text("评论已删除。", language: leafyLanguage))
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }
}

struct RealCommunityPostCard: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let post: CommunityPost
    var showsImageStrip = true
    var showsBody = false
    var isLikeLoading = false
    var isFavoriteLoading = false
    var isLikeDisabled = false
    var allowsImagePreview = true
    var canDelete = false
    var onOpen: (() -> Void)? = nil
    var onReport: (() -> Void)? = nil
    var onBlock: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onToggleLike: (() async -> Void)? = nil
    var onToggleFavorite: (() async -> Void)? = nil

    @State private var selectedImagePreviewIndex: Int?
    @State private var shareCardSource: CommunityPostCardPreviewSource?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            postSummary
                .contentShape(Rectangle())
                .onTapGesture {
                    onOpen?()
                }

            if showsImageStrip, !post.images.isEmpty {
                CommunityRemoteImageStrip(
                    images: post.images,
                    allowsSelection: allowsImagePreview,
                    onTapStrip: onOpen
                ) { index in
                    selectedImagePreviewIndex = index
                }
            }

            HStack(spacing: 16) {
                CommunityMetric(icon: "bubble.left", value: "\(post.commentCount)")
                if let onToggleLike {
                    CommunityLikeButton(
                        isLiked: post.viewerHasLiked,
                        value: "\(post.likeCount)",
                        isLoading: isLikeLoading,
                        isDisabled: isLikeDisabled,
                        action: onToggleLike
                    )
                } else {
                    CommunityMetric(icon: post.viewerHasLiked ? "heart.fill" : "heart", value: "\(post.likeCount)")
                }
                if let onToggleFavorite {
                    CommunityFavoriteButton(
                        isFavorited: post.viewerHasFavorited,
                        isLoading: isFavoriteLoading,
                        action: onToggleFavorite
                    )
                }
            }
        }
        .padding(18)
        .leafyCardStyle()
        .overlay {
            if post.pin != nil {
                RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                    .strokeBorder(AppTheme.warning.opacity(0.42), lineWidth: 1.5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onOpen?()
        }
        .leafyFullScreenCover(isPresented: Binding(
            get: { selectedImagePreviewIndex != nil },
            set: { if !$0 { selectedImagePreviewIndex = nil } }
        )) {
            if let selectedImagePreviewIndex {
                CommunityRemoteImagePreview(
                    images: post.images,
                    initialIndex: selectedImagePreviewIndex
                )
            }
        }
        .leafySheet(item: $shareCardSource) { source in
            CommunityPostCardPreviewSheet(source: source)
        }
    }

    private var postSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                authorIdentity

                Spacer()

                if let pin = post.pin {
                    CommunityPinBadge(pin: pin)
                }

                if let moderationStatusLabel = post.moderationStatusLabel {
                    Text(moderationStatusLabel)
                        .microCaption()
                        .foregroundStyle(AppTheme.warning)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(AppTheme.warning.opacity(0.12), in: Capsule())
                } else {
                    Text(post.categoryLabel)
                        .microCaption()
                        .foregroundStyle(AppTheme.accentEmphasis)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(AppTheme.softFill, in: Capsule())
                }

                if hasModerationActions {
                    moderationMenu
                }
            }

            postTitleText

            if showsBody, !post.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                CommunityLinkedText(post.body)
            }
        }
    }

    @ViewBuilder
    private var authorIdentity: some View {
        if let author = post.isAnonymous ? nil : post.author {
            NavigationLink {
                CommunityUserProfileView(profile: author)
            } label: {
                authorIdentityContent(profile: author)
            }
            .buttonStyle(.plain)
        } else {
            authorIdentityContent(profile: nil)
        }
    }

    private func authorIdentityContent(profile: CommunityProfile?) -> some View {
        HStack(spacing: 9) {
            CommunityAvatarView(profile: profile, size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(post.displayAuthorName)
                    .leafySubheadline()
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(post.relativeTimestamp)
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var postTitleText: some View {
        if showsBody {
            Text(post.title)
                .leafyHeadline()
                .foregroundStyle(AppTheme.primaryText)
                .textSelection(.enabled)
        } else {
            Text(post.title)
                .leafyHeadline()
                .foregroundStyle(AppTheme.primaryText)
        }
    }
    private var hasModerationActions: Bool {
        true
    }

    private var moderationMenu: some View {
        Menu {
            Button {
                shareCardSource = CommunityPostCardPreviewSource(content: .post(post))
            } label: {
                Label("生成图文卡片", systemImage: "rectangle.on.rectangle.angled")
            }

            ShareLink(item: post.shareURL, subject: Text(post.title), message: Text(post.shareText)) {
                Label("分享链接", systemImage: "link")
            }

            Button {
                LeafyClipboard.string = post.title
            } label: {
                Label("复制标题", systemImage: "doc.on.doc")
            }

            if !post.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    LeafyClipboard.string = post.body
                } label: {
                    Label("复制正文", systemImage: "text.quote")
                }
            }

            if let onReport {
                Button(role: .destructive) {
                    onReport()
                } label: {
                    Label("举报", systemImage: "exclamationmark.bubble")
                }
            }

            if let onBlock, post.authorID != CommunitySessionManager.shared.currentUserID {
                Button(role: .destructive) {
                    onBlock()
                } label: {
                    Label("屏蔽该用户", systemImage: "person.crop.circle.badge.xmark")
                }
            }

            if canDelete, let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("更多操作")
    }
}

struct CommunityLinkedText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(LeafyLinkedTextBuilder.attributedString(from: text))
            .leafyBody()
            .foregroundStyle(AppTheme.secondaryText)
            .tint(AppTheme.accent)
            .textSelection(.enabled)
    }
}

struct CommunityRemoteImageStrip: View {
    let images: [CommunityPostImage]
    var allowsSelection = true
    var onTapStrip: (() -> Void)? = nil
    let onSelectImage: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                    if allowsSelection {
                        Button {
                            onSelectImage(index)
                        } label: {
                            imageCell(image)
                        }
                        .buttonStyle(.plain)
                    } else {
                        imageCell(image)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !allowsSelection {
                onTapStrip?()
            }
        }
    }

    @ViewBuilder
    private func imageCell(_ image: CommunityPostImage) -> some View {
        if let thumbnailURL = image.resolvedThumbnailURL {
            AsyncImage(url: thumbnailURL) { phase in
                switch phase {
                case .empty:
                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        .fill(AppTheme.fill)
                        .overlay(ProgressView())
                case .success(let loadedImage):
                    loadedImage
                        .resizable()
                        .scaledToFill()
                case .failure:
                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        .fill(AppTheme.fill)
                        .overlay(Image(systemName: "photo").foregroundStyle(AppTheme.secondaryText))
                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: 120, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        }
    }
}

struct CommunityRemoteImagePreview: View {
    let images: [CommunityPostImage]
    let initialIndex: Int

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex = 0

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.imagePreviewBackground(for: colorScheme)
                    .ignoresSafeArea()

                TabView(selection: $selectedIndex) {
                    ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                        if let fullURL = image.resolvedFullURL {
                            ZoomableRemotePreviewImage(url: fullURL)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 32)
                                .tag(index)
                        } else {
                            ContentUnavailableView("图片无法加载", systemImage: "photo")
                                .tag(index)
                        }
                    }
                }
                .leafyImagePreviewTabStyle(showsIndex: images.count > 1)
                .background(AppTheme.imagePreviewBackground(for: colorScheme))

                VStack {
                    Spacer()
                    if images.count > 1 {
                        Text("\(selectedIndex + 1) / \(images.count)")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.45), in: Capsule())
                            .padding(.bottom, 22)
                    }
                }
            }
            .onAppear {
                selectedIndex = min(max(initialIndex, 0), max(images.count - 1, 0))
            }
            .toolbar {
                ToolbarItem(placement: .leafyLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.danger)
                }
            }
            .leafyNavigationToolbarBackgroundHidden()
        }
    }
}

struct ZoomableRemotePreviewImage: View {
    let url: URL

    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .scaleEffect(scale)
                        .offset(offset)
                        .simultaneousGesture(magnificationGesture)
                        .modifier(ZoomedRemoteImageDragModifier(
                            isEnabled: scale > 1.02,
                            offset: $offset,
                            baseOffset: $baseOffset
                        ))
                        .animation(.spring(response: 0.22, dampingFraction: 0.88), value: scale)
                        .animation(.spring(response: 0.22, dampingFraction: 0.88), value: offset)
                case .failure:
                    ContentUnavailableView("图片无法加载", systemImage: "photo")
                        .frame(width: geometry.size.width, height: geometry.size.height)
                @unknown default:
                    EmptyView()
                }
            }
        }
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(baseScale * value.magnification, 1), 5)
                if scale <= 1.02 {
                    offset = .zero
                    baseOffset = .zero
                }
            }
            .onEnded { _ in
                scale = min(max(scale, 1), 5)
                baseScale = scale
                if scale <= 1.02 {
                    scale = 1
                    baseScale = 1
                    offset = .zero
                    baseOffset = .zero
                }
            }
    }

}

struct ZoomedRemoteImageDragModifier: ViewModifier {
    let isEnabled: Bool
    @Binding var offset: CGSize
    @Binding var baseOffset: CGSize

    func body(content: Content) -> some View {
        if isEnabled {
            content.simultaneousGesture(dragGesture)
        } else {
            content
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: baseOffset.width + value.translation.width,
                    height: baseOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                baseOffset = offset
            }
    }
}

struct CommunityCommentCard: View {
    let comment: CommunityComment
    var canDelete = false
    var canReply = false
    var canLike = false
    var isLikeLoading = false
    var onReply: () -> Void = {}
    var onToggleLike: () -> Void = {}
    var onReport: (() -> Void)? = nil
    var onBlock: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                authorIdentity

                Spacer()

                HStack(spacing: 2) {
                    if hasModerationActions {
                        moderationMenu
                    }

                    if canLike {
                        likeButton
                    }
                }
            }

            if let replyTarget = comment.replyTargetDisplayName, comment.isReply {
                replyableContent(replyTarget: replyTarget)
            } else {
                replyableContent(replyTarget: nil)
            }
        }
        .padding(16)
        .background(
            AppTheme.cardElevated,
            in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .stroke(AppTheme.separator.opacity(0.7), lineWidth: 0.7)
        )
    }

    @ViewBuilder
    private func replyableContent(replyTarget: String?) -> some View {
        if canReply {
            Button {
                onReply()
            } label: {
                commentContent(replyTarget: replyTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("回复 \(comment.displayAuthorName)")
        } else {
            commentContent(replyTarget: replyTarget)
        }
    }

    private func commentContent(replyTarget: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let replyTarget {
                Text("回复 @\(replyTarget)")
                    .microCaption()
                    .foregroundStyle(AppTheme.accentEmphasis)
            }

            Text(comment.isDeletedPlaceholder ? "该评论已删除" : comment.body)
                .leafyBody()
                .foregroundStyle(comment.isDeletedPlaceholder ? AppTheme.tertiaryText : AppTheme.secondaryText)
                .italic(comment.isDeletedPlaceholder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var likeButton: some View {
        Button {
            onToggleLike()
        } label: {
            HStack(spacing: 6) {
                if isLikeLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: comment.viewerHasLiked ? "heart.fill" : "heart")
                        .font(.system(size: 20, weight: .medium))
                }
                if comment.likeCount > 0 {
                    Text("\(comment.likeCount)")
                        .microCaption()
                }
            }
            .foregroundStyle(comment.viewerHasLiked ? .red : AppTheme.secondaryText)
            .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLikeLoading)
        .accessibilityLabel(comment.viewerHasLiked ? "取消点赞" : "点赞")
    }

    @ViewBuilder
    private var authorIdentity: some View {
        if let author = comment.isAnonymous ? nil : comment.author {
            NavigationLink {
                CommunityUserProfileView(profile: author)
            } label: {
                authorIdentityContent(profile: author)
            }
            .buttonStyle(.plain)
        } else {
            authorIdentityContent(profile: nil)
        }
    }

    private func authorIdentityContent(profile: CommunityProfile?) -> some View {
        HStack(spacing: 10) {
            CommunityAvatarView(profile: profile, size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(comment.displayAuthorName)
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)
                Text(comment.relativeTimestamp)
                    .microCaption()
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
        .contentShape(Rectangle())
    }

    private var hasModerationActions: Bool {
        onReport != nil || onBlock != nil || (canDelete && onDelete != nil)
    }

    private var moderationMenu: some View {
        Menu {
            if let onReport {
                Button(role: .destructive) {
                    onReport()
                } label: {
                    Label("举报", systemImage: "exclamationmark.bubble")
                }
            }

            if let onBlock, comment.authorID != CommunitySessionManager.shared.currentUserID {
                Button(role: .destructive) {
                    onBlock()
                } label: {
                    Label("屏蔽该用户", systemImage: "person.crop.circle.badge.xmark")
                }
            }

            if canDelete, let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("评论操作")
    }
}

struct CommunityProfileBanner: View {
    let profile: CommunityProfile

    var body: some View {
        HStack(spacing: 14) {
            CommunityAvatarView(profile: profile, size: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(profile.limitedResolvedDisplayName)
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)
                Text(profile.subtitleText)
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer()
        }
        .padding(16)
        .leafyCardStyle()
    }
}

struct CommunityMetric: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(value)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(AppTheme.secondaryText)
    }
}

struct CommunityLikeButton: View {
    let isLiked: Bool
    let value: String
    let isLoading: Bool
    let isDisabled: Bool
    let action: (() async -> Void)?

    var body: some View {
        Button {
            guard !isDisabled else { return }
            guard let action else { return }
            Task {
                await action()
            }
        } label: {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: isDisabled ? "heart.slash" : (isLiked ? "heart.fill" : "heart"))
                }

                Text(value)
                    .lineLimit(1)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(isDisabled ? AppTheme.tertiaryText : (isLiked ? AppTheme.accentEmphasis : AppTheme.secondaryText))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || action == nil)
        .accessibilityHint(isDisabled ? L10n.text("不能点赞自己的帖子") : "")
    }
}

struct CommunityFavoriteButton: View {
    let isFavorited: Bool
    let isLoading: Bool
    let action: (() async -> Void)?

    var body: some View {
        Button {
            guard let action else { return }
            Task {
                await action()
            }
        } label: {
            Group {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: isFavorited ? "bookmark.fill" : "bookmark")
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(isFavorited ? AppTheme.accentEmphasis : AppTheme.secondaryText)
            .frame(width: 28, height: 24)
            .offset(x: -5)
        }
        .buttonStyle(.plain)
        .disabled(action == nil || isLoading)
        .accessibilityLabel(isFavorited ? L10n.text("取消收藏") : L10n.text("收藏"))
    }
}

struct CommunityErrorCard: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .leafyBody()
                .foregroundStyle(AppTheme.secondaryText)

            Button("重试", action: retry)
                .foregroundStyle(AppTheme.accentEmphasis)
        }
        .padding(18)
        .leafyCardStyle()
    }
}

struct CommunityInlineError: View {
    let message: String

    var body: some View {
        Text(message)
            .leafyBody()
            .foregroundStyle(AppTheme.danger)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }
}

struct CommunityTermsPromptCard: View {
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(AppTheme.accentEmphasis)
                Text("社区条款")
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)
            }

            Text("进入社区前请确认已阅读并同意 \(AppBrand.displayName) 社区条款。社区对违规内容和滥用用户零容忍。")
                .leafyBody()
                .foregroundStyle(AppTheme.secondaryText)

            Button("阅读并同意") {
                action()
            }
            .foregroundStyle(AppTheme.accentEmphasis)
        }
        .padding(18)
        .leafyCardStyle()
    }
}

struct CommunityTermsAgreementSheet: View {
    let onAccepted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyDependencies) private var dependencies
    @State private var isAccepted = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(onAccepted: @escaping () -> Void = {}) {
        self.onAccepted = onAccepted
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("\(AppBrand.displayName) 社区条款")
                            .title2()
                            .foregroundStyle(AppTheme.primaryText)

                        Text("使用社区代表你同意遵守以下规则。\(AppBrand.displayName) 对违规内容和滥用用户采取零容忍政策。")
                            .leafyBody()
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .padding(18)
                    .leafyCardStyle()

                    VStack(alignment: .leading, spacing: 12) {
                        termsLine("不得发布辱骂、骚扰、歧视、威胁、色情低俗、违法、侵权、侵犯隐私或其他令人反感的内容。")
                        termsLine("不得滥用匿名发布、冒充他人、刷屏、恶意引战或规避审核。")
                        termsLine("\(AppBrand.displayName) 会过滤违规内容；用户可以举报内容、屏蔽用户，并可删除自己发布的帖子和评论。")
                        termsLine("开发者会在 24 小时内处理违规举报，必要时移除内容并禁言或移除违规用户。")
                        termsLine("社区安全联系邮箱：\(CommunityTerms.supportEmail)。")
                    }
                    .padding(18)
                    .leafyCardStyle()

                    Toggle(isOn: $isAccepted) {
                        Text("我已阅读并同意社区条款")
                            .leafyBody()
                            .foregroundStyle(AppTheme.primaryText)
                    }
                    .tint(AppTheme.accent)
                    .padding(18)
                    .leafyCardStyle()

                    if let errorMessage {
                        CommunityInlineError(message: errorMessage)
                    }
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle("社区条款")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .leafyTrailing) {
                    Button(isSubmitting ? "保存中" : "同意") {
                        Task { await accept() }
                    }
                    .disabled(!isAccepted || isSubmitting)
                }
            }
        }
    }

    private func termsLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.accentEmphasis)
                .padding(.top, 2)
            Text(text)
                .leafyBody()
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @MainActor
    private func accept() async {
        guard isAccepted else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await dependencies.communityActivityRepository.acceptCurrentTerms()
            onAccepted()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
