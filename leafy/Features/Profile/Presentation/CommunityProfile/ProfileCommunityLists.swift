import Foundation
import PhotosUI
import Photos
import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum ProfileCommunityPostListKind {
    case authored
    case liked
    case favorited

    var title: String {
        switch self {
        case .authored: return L10n.text("我的发帖")
        case .liked: return L10n.text("我的点赞")
        case .favorited: return L10n.text("我的收藏")
        }
    }

    var emptyTitle: String {
        switch self {
        case .authored: return L10n.text("还没有发过帖子")
        case .liked: return L10n.text("还没有点赞过帖子")
        case .favorited: return L10n.text("还没有收藏帖子")
        }
    }

    var emptySystemImage: String {
        switch self {
        case .authored: return "text.bubble"
        case .liked: return "heart"
        case .favorited: return "bookmark"
        }
    }

    var deleteActionTitle: String {
        switch self {
        case .authored: return L10n.text("删除")
        case .liked: return L10n.text("取消点赞")
        case .favorited: return L10n.text("取消收藏")
        }
    }

    var deleteActionIcon: String {
        switch self {
        case .authored: return "trash"
        case .liked: return "heart.slash"
        case .favorited: return "bookmark.slash"
        }
    }
}

struct ProfileCommunityPostListView: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyDependencies) private var dependencies
    let kind: ProfileCommunityPostListKind

    @ObservedObject private var sessionManager = CommunitySessionManager.shared
    @State private var posts: [CommunityPost] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedPost: CommunityPost?
    @State private var deletingPostIDs: Set<UUID> = []
    @State private var operationAlert: LeafyOperationAlert?

    var body: some View {
        List {
            if isLoading && posts.isEmpty {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if let errorMessage, posts.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(errorMessage)
                            .leafyBody()
                            .foregroundStyle(AppTheme.secondaryText)

                        Button("重试") {
                            Task { await load() }
                        }
                        .foregroundStyle(AppTheme.accentEmphasis)
                    }
                    .padding(.vertical, 8)
                }
            } else if posts.isEmpty {
                Section {
                    ContentUnavailableView(kind.emptyTitle, systemImage: kind.emptySystemImage)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
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
                    ForEach(posts) { post in
                        ProfileCommunityPostCompactCard(
                            post: post,
                            isDeleting: deletingPostIDs.contains(post.id),
                            onOpen: {
                                selectedPost = post
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: AppSpacing.page, bottom: 6, trailing: AppSpacing.page))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { await deletePost(post) }
                            } label: {
                                Label(kind.deleteActionTitle, systemImage: kind.deleteActionIcon)
                            }
                            .tint(.red)
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(LeafyPageBackground())
        .navigationTitle(kind.title)
        .leafyInlineNavigationTitle()
        .task {
            await load()
        }
        .refreshable {
            await load()
        }
        .sheet(item: $selectedPost) { post in
            RealCommunityPostDetailSheet(post: post) { updatedPost in
                applyPostChange(updatedPost)
            } onPostRemoved: {
                posts.removeAll { $0.id == post.id }
                selectedPost = nil
            }
                .presentationDetents([.medium, .large])
        }
        .leafyOperationAlert($operationAlert)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        await sessionManager.restoreProfileIfPossible()
        await sessionManager.bootstrapCommunityUser()

        if let bootstrapError = sessionManager.bootstrapError {
            posts = []
            errorMessage = bootstrapError
            return
        }

        guard let userID = sessionManager.currentUserID else {
            posts = []
            errorMessage = CommunityServiceError.missingAuthenticatedUser.localizedDescription
            return
        }

        do {
            switch kind {
            case .authored:
                posts = try await dependencies.communityActivityRepository.fetchPosts(authoredBy: userID)
            case .liked:
                posts = try await dependencies.communityActivityRepository.fetchLikedPosts(by: userID)
            case .favorited:
                posts = try await dependencies.communityActivityRepository.fetchFavoritedPosts(by: userID)
            }
            errorMessage = nil
        } catch {
            posts = []
            errorMessage = error.localizedDescription
        }
    }

    private func applyPostChange(_ updatedPost: CommunityPost) {
        posts = ProfileCommunityPostListReducer.applyingPostChange(updatedPost, to: posts, kind: kind)
    }

    private func deletePost(_ post: CommunityPost) async {
        guard !deletingPostIDs.contains(post.id) else { return }
        deletingPostIDs.insert(post.id)
        defer { deletingPostIDs.remove(post.id) }

        do {
            switch kind {
            case .authored:
                try await dependencies.communityActivityRepository.deletePost(postID: post.id)
            case .liked:
                _ = try await dependencies.communityActivityRepository.togglePostLike(postID: post.id)
            case .favorited:
                _ = try await dependencies.communityActivityRepository.togglePostFavorite(postID: post.id)
            }
            posts.removeAll { $0.id == post.id }
            if selectedPost?.id == post.id {
                selectedPost = nil
            }
            errorMessage = nil
            switch kind {
            case .authored:
                operationAlert = .success(L10n.text("帖子已删除！", language: leafyLanguage))
            case .liked:
                operationAlert = .success(L10n.text("已取消点赞！", language: leafyLanguage))
            case .favorited:
                operationAlert = .success(L10n.text("已取消收藏！", language: leafyLanguage))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ProfileCommunityCommentListView: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyDependencies) private var dependencies
    @ObservedObject private var sessionManager = CommunitySessionManager.shared
    @State private var comments: [CommunityComment] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var deletingCommentIDs: Set<UUID> = []
    @State private var operationAlert: LeafyOperationAlert?

    var body: some View {
        List {
            if isLoading && comments.isEmpty {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                }
            } else if let errorMessage, comments.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(errorMessage)
                            .leafyBody()
                            .foregroundStyle(AppTheme.secondaryText)
                        Button("重试") {
                            Task { await load() }
                        }
                        .foregroundStyle(AppTheme.accentEmphasis)
                    }
                    .padding(.vertical, 8)
                }
            } else if comments.isEmpty {
                Section {
                    ContentUnavailableView("还没有评论", systemImage: "text.bubble")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                }
            } else {
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .leafyBody()
                            .foregroundStyle(AppTheme.danger)
                    }
                }

                ForEach(comments) { comment in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(comment.relativeTimestamp)
                                .microCaption()
                                .foregroundStyle(AppTheme.tertiaryText)
                            Spacer()
                            if deletingCommentIDs.contains(comment.id) {
                                ProgressView()
                                    .scaleEffect(0.75)
                            }
                        }

                        Text(comment.body)
                            .leafyBody()
                            .foregroundStyle(AppTheme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 6)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await delete(comment) }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                }
            }
        }
        .navigationTitle("我的评论")
        .task {
            await load()
        }
        .refreshable {
            await load()
        }
        .leafyOperationAlert($operationAlert)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        await sessionManager.restoreProfileIfPossible()
        await sessionManager.bootstrapCommunityUser()

        if let bootstrapError = sessionManager.bootstrapError {
            comments = []
            errorMessage = bootstrapError
            return
        }

        do {
            comments = try await dependencies.communityActivityRepository.fetchMyComments()
            errorMessage = nil
        } catch {
            comments = []
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ comment: CommunityComment) async {
        guard !deletingCommentIDs.contains(comment.id) else { return }
        deletingCommentIDs.insert(comment.id)
        defer { deletingCommentIDs.remove(comment.id) }

        do {
            try await dependencies.communityActivityRepository.deleteComment(commentID: comment.id)
            comments.removeAll { $0.id == comment.id }
            errorMessage = nil
            operationAlert = .success(L10n.text("评论已删除！", language: leafyLanguage))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum ProfileCommunityPollListKind: String, CaseIterable, Identifiable {
    case authored
    case voted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .authored: return L10n.text("我发起的")
        case .voted: return L10n.text("我投过的")
        }
    }

    var emptyTitle: String {
        switch self {
        case .authored: return L10n.text("还没有发起投票")
        case .voted: return L10n.text("还没有参与投票")
        }
    }
}

struct ProfileCommunityPollListView: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyDependencies) private var dependencies
    @ObservedObject private var sessionManager = CommunitySessionManager.shared

    @State private var selectedKind: ProfileCommunityPollListKind = .authored
    @State private var authoredPolls: [CommunityPoll] = []
    @State private var votedPolls: [CommunityPoll] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedPoll: CommunityPoll?
    @State private var activePollIDs: Set<UUID> = []
    @State private var deletionTarget: CommunityPoll?
    @State private var operationAlert: LeafyOperationAlert?

    private var currentPolls: [CommunityPoll] {
        selectedKind == .authored ? authoredPolls : votedPolls
    }

    var body: some View {
        List {
            Section {
                Picker("投票类型", selection: $selectedKind) {
                    ForEach(ProfileCommunityPollListKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 4)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if isLoading && currentPolls.isEmpty {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if let errorMessage, currentPolls.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(errorMessage)
                            .leafyBody()
                            .foregroundStyle(AppTheme.secondaryText)

                        Button("重试") {
                            Task { await load() }
                        }
                        .foregroundStyle(AppTheme.accentEmphasis)
                    }
                    .padding(.vertical, 8)
                }
            } else if currentPolls.isEmpty {
                Section {
                    ContentUnavailableView(selectedKind.emptyTitle, systemImage: "chart.bar.xaxis")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
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
                    ForEach(currentPolls) { poll in
                        ProfileCommunityPollCompactCard(
                            poll: poll,
                            isBusy: activePollIDs.contains(poll.id),
                            onOpen: { selectedPoll = poll }
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: AppSpacing.page, bottom: 6, trailing: AppSpacing.page))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if selectedKind == .authored && poll.canRequestDeletion {
                                Button(role: .destructive) {
                                    deletionTarget = poll
                                } label: {
                                    Label("申请删除", systemImage: "trash")
                                }
                                .tint(.red)
                            }
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(LeafyPageBackground())
        .navigationTitle("我的投票")
        .leafyInlineNavigationTitle()
        .task {
            await load()
        }
        .refreshable {
            await load()
        }
        .sheet(item: $selectedPoll) { poll in
            CommunityPollDetailSheet(
                poll: poll,
                isLoading: activePollIDs.contains(poll.id),
                canDelete: selectedKind == .authored && poll.canRequestDeletion,
                onVote: { option in
                    await vote(poll: poll, option: option)
                },
                onDelete: {
                    deletionTarget = poll
                    selectedPoll = nil
                }
            )
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog("申请删除这个投票？", isPresented: Binding(
            get: { deletionTarget != nil },
            set: { if !$0 { deletionTarget = nil } }
        ), titleVisibility: .visible) {
            Button("提交申请", role: .destructive) {
                requestSelectedPollDeletion()
            }
            Button("取消", role: .cancel) {
                deletionTarget = nil
            }
        } message: {
            Text("提交后需后台审核。审核前投票会继续公开展示。")
        }
        .leafyOperationAlert($operationAlert)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        await sessionManager.restoreProfileIfPossible()
        await sessionManager.bootstrapCommunityUser()

        if let bootstrapError = sessionManager.bootstrapError {
            authoredPolls = []
            votedPolls = []
            errorMessage = bootstrapError
            return
        }

        guard sessionManager.currentUserID != nil else {
            authoredPolls = []
            votedPolls = []
            errorMessage = CommunityServiceError.missingAuthenticatedUser.localizedDescription
            return
        }

        do {
            async let authored = dependencies.communityActivityRepository.fetchMyAuthoredPolls()
            async let voted = dependencies.communityActivityRepository.fetchMyVotedPolls()
            authoredPolls = try await authored
            votedPolls = try await voted
            errorMessage = nil
        } catch {
            authoredPolls = []
            votedPolls = []
            errorMessage = error.localizedDescription
        }
    }

    private func vote(poll: CommunityPoll, option: CommunityPollOption) async {
        guard !activePollIDs.contains(poll.id) else { return }
        activePollIDs.insert(poll.id)
        defer { activePollIDs.remove(poll.id) }

        do {
            let updatedPoll = try await dependencies.communityRepository.votePoll(pollID: poll.id, optionID: option.id)
            replacePoll(updatedPoll)
            selectedPoll = updatedPoll
            errorMessage = nil
            operationAlert = .success(L10n.text("已记录你的选择！", language: leafyLanguage))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func requestSelectedPollDeletion() {
        guard let poll = deletionTarget else { return }
        deletionTarget = nil
        Task { await requestDeletion(poll: poll) }
    }

    private func requestDeletion(poll: CommunityPoll) async {
        guard !activePollIDs.contains(poll.id) else { return }
        activePollIDs.insert(poll.id)
        defer { activePollIDs.remove(poll.id) }

        do {
            let updatedPoll = try await dependencies.communityActivityRepository.requestPollDeletion(pollID: poll.id, reason: nil)
            replacePoll(updatedPoll)
            selectedPoll = selectedPoll?.id == updatedPoll.id ? updatedPoll : selectedPoll
            errorMessage = nil
            operationAlert = .success(L10n.text("删除申请已提交！", language: leafyLanguage))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func replacePoll(_ poll: CommunityPoll) {
        if let index = authoredPolls.firstIndex(where: { $0.id == poll.id }) {
            authoredPolls[index] = poll
        }
        if let index = votedPolls.firstIndex(where: { $0.id == poll.id }) {
            votedPolls[index] = poll
        }
    }
}

struct ProfileCommunityPollCompactCard: View {
    let poll: CommunityPoll
    let isBusy: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(poll.statusText)
                                .microCaption()
                                .foregroundStyle(statusColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(statusColor.opacity(0.12), in: Capsule())

                            Text(poll.relativeTimestamp)
                                .microCaption()
                                .foregroundStyle(AppTheme.tertiaryText)
                        }

                        Text(poll.question)
                            .leafyHeadline()
                            .foregroundStyle(AppTheme.primaryText)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if isBusy {
                        ProgressView()
                            .scaleEffect(0.75)
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.tertiaryText)
                            .padding(.top, 4)
                    }
                }

                HStack(spacing: 14) {
                    ProfileCommunityPostMetric(icon: "person.2", value: "\(poll.totalVoteCount)")
                    if poll.viewerOptionID != nil {
                        ProfileCommunityPostMetric(icon: "checkmark.circle", value: "已投")
                    }
                    if poll.isDeletionPending {
                        ProfileCommunityPostMetric(icon: "hourglass", value: "删审")
                    }

                    Spacer()

                    Text(poll.displayAuthorName)
                        .microCaption()
                        .foregroundStyle(AppTheme.tertiaryText)
                        .lineLimit(1)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                    .stroke(AppTheme.separator, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var statusColor: Color {
        if poll.isDeletionPending { return AppTheme.warning }
        switch poll.status {
        case "published": return poll.isClosed ? AppTheme.secondaryText : AppTheme.accentEmphasis
        case "pending_review": return AppTheme.warning
        case "hidden", "deleted": return AppTheme.danger
        default: return AppTheme.secondaryText
        }
    }
}

struct ProfileCommunityPostCompactCard: View {
    let post: CommunityPost
    let isDeleting: Bool
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(post.moderationStatusLabel ?? post.categoryLabel)
                            .microCaption()
                            .foregroundStyle(post.moderationStatusLabel == nil ? AppTheme.accentEmphasis : AppTheme.warning)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background((post.moderationStatusLabel == nil ? AppTheme.softFill : AppTheme.warning.opacity(0.12)), in: Capsule())

                        Text(post.relativeTimestamp)
                            .microCaption()
                            .foregroundStyle(AppTheme.tertiaryText)
                    }

                    Text(post.title)
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)

                if isDeleting {
                    ProgressView()
                        .scaleEffect(0.75)
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.tertiaryText)
                        .padding(.top, 4)
                }
            }

            HStack(spacing: 14) {
                ProfileCommunityPostMetric(icon: "bubble.left", value: "\(post.commentCount)")
                ProfileCommunityPostMetric(icon: "heart", value: "\(post.likeCount)")

                if !post.images.isEmpty {
                    ProfileCommunityPostMetric(icon: "photo", value: "\(post.images.count)")
                }

                Spacer()

                Text(post.displayAuthorName)
                    .microCaption()
                    .foregroundStyle(AppTheme.tertiaryText)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                .stroke(AppTheme.separator, lineWidth: 1)
        )
    }
}

struct ProfileCommunityPostMetric: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(value)
        }
        .microCaption()
        .foregroundStyle(AppTheme.tertiaryText)
    }
}

struct ProfilePlaceholderListView: View {
    let title: String
    let subtitle: String
    let items: [String]

    var body: some View {
        List {
            Section {
                Text(subtitle)
                    .leafyBody()
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Section {
                ForEach(items, id: \.self) { item in
                    Text(item)
                }
            }
        }
        .navigationTitle(title)
    }
}
