import Foundation
import os
import SwiftUI

struct CommunityUserProfileView: View {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "MyLeafy",
        category: "CommunityProfile"
    )

    @Environment(\.leafyDependencies) private var dependencies
    @Environment(\.leafyLanguage) private var leafyLanguage
    @ObservedObject private var sessionManager = CommunitySessionManager.shared

    private let profileID: UUID?
    private let initialProfile: CommunityProfile?
    private let allowsEditing: Bool

    @State private var profile: CommunityProfile?
    @State private var profileStats: CommunityProfileStats?
    @State private var posts: [CommunityPost] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedPost: CommunityPost?
    @State private var draftCount = 0

    init(
        profileID: UUID?,
        initialProfile: CommunityProfile? = nil,
        allowsEditing: Bool = false
    ) {
        self.profileID = profileID ?? initialProfile?.id
        self.initialProfile = initialProfile
        self.allowsEditing = allowsEditing
        _profile = State(initialValue: initialProfile)
    }

    init(profile: CommunityProfile, allowsEditing: Bool = false) {
        self.init(profileID: profile.id, initialProfile: profile, allowsEditing: allowsEditing)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppSpacing.card) {
                profileHero

                if allowsEditing {
                    profileQuickActions
                }

                postsSection
            }
            .padding(.horizontal, AppSpacing.page)
            .padding(.top, AppSpacing.micro)
            .padding(.bottom, 44)
            .frame(maxWidth: 760, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollContentBackground(.hidden)
        .background(LeafyPageBackground())
        .navigationTitle(profile?.limitedResolvedDisplayName ?? L10n.text("个人主页", language: leafyLanguage))
        .leafyInlineNavigationTitle()
        .toolbar {
            if allowsEditing {
                ToolbarItem(placement: .leafyTrailing) {
                    NavigationLink {
                        CommunityProfileEditorView()
                    } label: {
                        Text(L10n.text("编辑", language: leafyLanguage))
                    }
                }
            }
        }
        .task(id: loadTaskID) {
            await load()
            loadDraftCount()
        }
        .refreshable {
            await load()
            loadDraftCount()
        }
        .onChange(of: sessionManager.profile) { _, newProfile in
            guard allowsEditing, let newProfile else { return }
            profile = newProfile
        }
        .onReceive(NotificationCenter.default.publisher(for: .communityPostDraftsDidChange)) { notification in
            guard allowsEditing, notification.object as? UUID == sessionManager.currentUserID else { return }
            loadDraftCount()
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
    }

    private var loadTaskID: String {
        [profileID?.uuidString, initialProfile?.id.uuidString, allowsEditing.description]
            .compactMap { $0 }
            .joined(separator: "|")
    }

    @ViewBuilder
    private var profileHero: some View {
        if let profile {
            ZStack(alignment: .bottomLeading) {
                CommunityProfileCoverPreview(image: nil, profile: profile, usesFixedAspectRatio: false)
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .bottom, spacing: 14) {
                        CommunityAvatarView(profile: profile, size: 86)
                            .overlay(
                                Circle()
                                    .stroke(.white.opacity(0.82), lineWidth: 2)
                            )

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(profile.limitedResolvedDisplayName)
                                    .title2()
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.78)

                                Text(L10n.text(profileTitle.title, language: leafyLanguage))
                                    .microCaption()
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.white.opacity(0.18), in: Capsule())
                                    .lineLimit(1)
                            }

                            Text(profile.trimmedBio ?? emptyBioText)
                                .leafyBody()
                                .foregroundStyle(profile.trimmedBio == nil ? .white.opacity(0.66) : .white.opacity(0.9))
                                .lineLimit(2)

                            if let profileEducationLine {
                                Text(profileEducationLine)
                                    .microCaption()
                                    .foregroundStyle(.white.opacity(0.76))
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(spacing: 10) {
                        ForEach(profileBadges, id: \.title) { badge in
                            Text(badge.title)
                                .microCaption()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.white.opacity(0.16), in: Capsule())
                        }
                    }
                }
                .padding(18)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                    .stroke(AppTheme.separator.opacity(0.7), lineWidth: 0.7)
            )
        } else if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
        } else {
            ContentUnavailableView(
                "社区资料暂不可用",
                systemImage: "person.crop.circle.badge.exclamationmark",
                description: Text("请稍后再试。")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    private var profileQuickActions: some View {
        HStack(spacing: 12) {
            NavigationLink {
                ProfileCommunityPostListView(kind: .liked)
            } label: {
                quickAction(icon: "heart.fill", title: "点赞", tint: AppTheme.danger)
            }
            .buttonStyle(.plain)

            NavigationLink {
                ProfileCommunityCommentListView()
            } label: {
                quickAction(icon: "text.bubble.fill", title: "评论", tint: AppTheme.accentEmphasis)
            }
            .buttonStyle(.plain)

            NavigationLink {
                ProfileCommunityPostListView(kind: .favorited)
            } label: {
                quickAction(icon: "bookmark.fill", title: "收藏", tint: AppTheme.warning)
            }
            .buttonStyle(.plain)

            NavigationLink {
                ProfileCommunityPollListView()
            } label: {
                quickAction(icon: "chart.bar.xaxis", title: "投票", tint: AppTheme.accent)
            }
            .buttonStyle(.plain)
        }
    }

    private func quickAction(icon: String, title: String, tint: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.12), in: Circle())

            Text(title)
                .microCaption()
                .fontWeight(.semibold)
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .stroke(AppTheme.separator.opacity(0.7), lineWidth: 0.7)
        )
    }

    private var postsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(allowsEditing ? "我的发帖" : "公开帖子")
                        .leafyTitle3()
                        .foregroundStyle(AppTheme.primaryText)
                    Text(allowsEditing ? "已发布的内容会展示在这里" : "匿名、待审核和隐藏内容不会出现在个人主页。")
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer()
            }

            postsContent
        }
    }

    private var draftBoxCard: some View {
        NavigationLink {
            CommunityPostDraftsView()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.accentEmphasis)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.softFill, in: Circle())

                Text("草稿箱")
                    .leafySubheadline()
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.primaryText)

                Text(draftCount > 0 ? "\(draftCount) 篇未发布内容" : "暂无草稿")
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.leading)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                AppTheme.cardBackground,
                in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                    .stroke(AppTheme.separator.opacity(0.7), lineWidth: 0.7)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            .contentShape(.interaction, RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .contentShape(.interaction, RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .accessibilityLabel(draftCount > 0 ? "草稿箱，\(draftCount) 篇未发布内容" : "草稿箱，暂无草稿")
        .accessibilityHint("打开草稿箱")
    }

    @ViewBuilder
    private var postsContent: some View {
        if allowsEditing {
            editablePostsContent
        } else {
            publicPostsContent
        }
    }

    private var editablePostsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            CommunityMasonryGrid(items: editableMasonryItems, spacing: 10) { item in
                switch item {
                case .draftBox:
                    draftBoxCard
                case .post(let post):
                    masonryPostCard(post)
                }
            }

            editablePostsStatus
        }
    }

    @ViewBuilder
    private var editablePostsStatus: some View {
        if isLoading && posts.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
        } else if let errorMessage, posts.isEmpty {
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
        } else if posts.isEmpty {
            ContentUnavailableView(
                "暂无已发布帖子",
                systemImage: "text.bubble",
                description: Text("发布后会自动出现在这里。")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        } else if let errorMessage {
            Text(errorMessage)
                .leafyBody()
                .foregroundStyle(AppTheme.danger)
        }
    }

    @ViewBuilder
    private var publicPostsContent: some View {
        if isLoading && posts.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
        } else if let errorMessage, posts.isEmpty {
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
        } else if posts.isEmpty {
            ContentUnavailableView(
                "暂无公开帖子",
                systemImage: "text.bubble",
                description: Text("匿名、待审核和隐藏内容不会出现在个人主页。")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        } else {
            if let errorMessage {
                Text(errorMessage)
                    .leafyBody()
                    .foregroundStyle(AppTheme.danger)
            }

            CommunityMasonryGrid(items: posts, spacing: 10) { post in
                masonryPostCard(post)
            }
        }
    }

    private var editableMasonryItems: [CommunityProfileMasonryItem] {
        [.draftBox] + posts.map(CommunityProfileMasonryItem.post)
    }

    private func masonryPostCard(_ post: CommunityPost) -> some View {
        CommunityMasonryPostCard(
            post: post,
            showsAuthor: !allowsEditing,
            showsCategory: !allowsEditing,
            onOpen: {
                selectedPost = post
            }
        )
    }

    private var emptyBioText: String {
        allowsEditing
            ? L10n.text("尚未填写签名", language: leafyLanguage)
            : L10n.text("该用户尚未填写签名", language: leafyLanguage)
    }

    private var profileEducationLine: String? {
        guard let profile else { return nil }
        let parts = [profile.grade, profile.major]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private var profileTitle: CommunityProfileTitle {
        if let profileStats {
            return CommunityProfileTitle(title: profileStats.title, tint: AppTheme.accentEmphasis)
        }

        let likeCount = posts.reduce(0) { $0 + $1.likeCount }
        return CommunityProfileTitle(
            title: CommunityProfileTitleName.title(publicPostCount: posts.count, receivedLikeCount: likeCount),
            tint: likeCount > 0 || !posts.isEmpty ? AppTheme.secondaryText : AppTheme.tertiaryText
        )
    }

    private var profileBadges: [ProfileBadge] {
        guard let profile else { return [] }
        var badges: [ProfileBadge] = []

        if profile.showsEduVerificationBadge {
            badges.append(ProfileBadge(title: L10n.text("已完成教务实名", language: leafyLanguage), tint: AppTheme.accentEmphasis))
        }

        return badges
    }

    @MainActor
    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        if allowsEditing {
            await sessionManager.restoreProfileIfPossible()
            await sessionManager.bootstrapCommunityUser()
            if let currentProfile = sessionManager.profile {
                profile = currentProfile
            }
        }

        guard let targetID = profile?.id ?? profileID else {
            errorMessage = sessionManager.bootstrapError ?? CommunityServiceError.missingAuthenticatedUser.localizedDescription
            posts = []
            return
        }
        if profileStats?.profileID != targetID {
            profileStats = nil
        }

        do {
            async let profileRequest = dependencies.communityActivityRepository.fetchProfile(userID: targetID)
            async let postsRequest = allowsEditing
                ? dependencies.communityActivityRepository.fetchPosts(authoredBy: targetID, limit: 30)
                : dependencies.communityActivityRepository.fetchPublicPosts(authoredBy: targetID, limit: 30)
            async let statsRequest = fetchProfileStats(targetID)

            let (loadedProfile, loadedPosts, loadedStats) = try await (profileRequest, postsRequest, statsRequest)
            if let loadedProfile {
                profile = loadedProfile
            }
            posts = loadedPosts
            profileStats = loadedStats
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            if profile == nil {
                profile = initialProfile
            }
            profileStats = nil
            posts = []
        }
    }

    private func fetchProfileStats(_ profileID: UUID) async -> CommunityProfileStats? {
        do {
            return try await dependencies.communityActivityRepository
                .fetchProfileStats(profileIDs: [profileID])
                .first { $0.profileID == profileID }
        } catch {
            return nil
        }
    }

    private func applyPostChange(_ updatedPost: CommunityPost) {
        guard updatedPost.status == "published", !updatedPost.isAnonymous else {
            posts.removeAll { $0.id == updatedPost.id }
            return
        }
        posts = posts.map { $0.id == updatedPost.id ? updatedPost : $0 }
    }

    private func loadDraftCount() {
        guard allowsEditing, let ownerProfileID = sessionManager.currentUserID else {
            draftCount = 0
            return
        }
        do {
            draftCount = try dependencies.communityPostDraftRepository
                .listDrafts(ownerProfileID: ownerProfileID)
                .count
        } catch {
            draftCount = 0
            Self.logger.error(
                "Load community draft count failed owner=\(ownerProfileID.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .private)"
            )
        }
    }
}

enum CommunityProfileMasonryItem: Identifiable, Equatable {
    case draftBox
    case post(CommunityPost)

    var id: String {
        switch self {
        case .draftBox:
            return "draft-box"
        case .post(let post):
            return "post-\(post.id.uuidString)"
        }
    }
}

private struct ProfileBadge {
    let title: String
    let tint: Color
}

private struct CommunityProfileTitle {
    let title: String
    let tint: Color
}
