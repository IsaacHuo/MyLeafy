import Combine
import OSLog
import QuickLook
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
private enum NotificationOpenResult {
    case post(CommunityPost)
    case announcement(SiteAnnouncement)
    case publication(CommunityPublishTask)
}

@MainActor
private final class CommunityNotificationsViewModel: ObservableObject {
    @Published private(set) var items: [NotificationFeedItem] = []
    @Published private(set) var settings: CommunityNotificationSettings?
    @Published private(set) var isLoading = false
    @Published private(set) var activeItemID: String?
    @Published private(set) var isUpdatingSettings = false
    @Published private(set) var isMarkingAllRead = false
    @Published var errorMessage: String?

    private let repository: any CommunityNotificationRepository
    private let publishCoordinator = CommunityPublishCoordinator.shared

    init(repository: any CommunityNotificationRepository) {
        self.repository = repository
    }

    var isMutedAll: Bool {
        settings?.mutedAll ?? false
    }

    var hasUnreadItems: Bool {
        items.contains { !$0.isRead }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await repository.ensureAnonymousSession()
        } catch {
            items = publishCoordinator.notificationItems.sorted { $0.sortDate > $1.sortDate }
            errorMessage = error.localizedDescription
            return
        }

        await CommunitySessionManager.shared.restoreProfileIfPossible()

        do {
            settings = try await repository.fetchNotificationSettings()
            if settings?.mutedAll == true {
                items = publishCoordinator.notificationItems.sorted { $0.sortDate > $1.sortDate }
                errorMessage = nil
                return
            }

            items = (
                try await repository.fetchNotificationFeed(limit: 50) + publishCoordinator.notificationItems
            ).sorted { $0.sortDate > $1.sortDate }
            errorMessage = nil
        } catch {
            items = publishCoordinator.notificationItems.sorted { $0.sortDate > $1.sortDate }
            errorMessage = error.localizedDescription
        }
    }

    func setMutedAll(_ muted: Bool) async -> Bool {
        guard !isUpdatingSettings else { return false }
        isUpdatingSettings = true
        defer { isUpdatingSettings = false }

        do {
            settings = try await repository.updateNotificationSettings(mutedAll: muted)
            if muted {
                items = publishCoordinator.notificationItems.sorted { $0.sortDate > $1.sortDate }
            } else {
                items = (
                    try await repository.fetchNotificationFeed(limit: 50) + publishCoordinator.notificationItems
                ).sorted { $0.sortDate > $1.sortDate }
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func markAllRead() async -> Bool {
        guard !isMarkingAllRead, !isLoading, hasUnreadItems else { return false }
        isMarkingAllRead = true
        defer { isMarkingAllRead = false }

        do {
            try await repository.markNotificationFeedRead(announcementLimit: 500)
            let readAt = ISO8601DateFormatter().string(from: Date())
            for item in items {
                if case .publication(let notification) = item {
                    publishCoordinator.markNotificationRead(taskID: notification.id)
                }
            }
            items = items.map { $0.markingRead(at: readAt) }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func dismissItem(_ item: NotificationFeedItem) async -> Bool {
        guard activeItemID == nil else { return false }
        activeItemID = item.id
        defer { activeItemID = nil }

        do {
            if case .publication(let notification) = item {
                publishCoordinator.dismissNotification(taskID: notification.id)
            } else {
                try await repository.dismissNotificationFeedItem(item)
            }
            items.removeAll { $0.id == item.id }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func openItem(_ item: NotificationFeedItem) async -> NotificationOpenResult? {
        guard activeItemID == nil else { return nil }
        activeItemID = item.id
        defer { activeItemID = nil }

        switch item {
        case .community(let notification):
            return await openCommunityNotification(notification, itemID: item.id)
        case .announcement(let announcement):
            return await openSiteAnnouncement(announcement, itemID: item.id)
        case .publication(let notification):
            return await openPublicationNotification(notification, itemID: item.id)
        }
    }

    private func openPublicationNotification(
        _ notification: CommunityPublishNotification,
        itemID: String
    ) async -> NotificationOpenResult? {
        publishCoordinator.markNotificationRead(taskID: notification.id)
        if let index = items.firstIndex(where: { $0.id == itemID }) {
            items[index] = .publication(
                CommunityPublishNotification(task: notification.task, isRead: true)
            )
        }

        guard notification.task.state == .published else {
            errorMessage = nil
            return .publication(notification.task)
        }

        do {
            guard let post = try await repository.fetchLinkedPost(postID: notification.task.id) else {
                errorMessage = "已发布的帖子暂时无法打开，请稍后重试。"
                return nil
            }
            errorMessage = nil
            return .post(post)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func openCommunityNotification(_ notification: CommunityNotification, itemID: String) async -> NotificationOpenResult? {
        guard let postID = notification.postID else {
            errorMessage = "这条通知没有关联帖子。"
            return nil
        }

        do {
            if !notification.isRead {
                try await repository.markNotificationRead(notificationID: notification.id)
                if let index = items.firstIndex(where: { $0.id == itemID }) {
                    items[index] = .community(notification.markingRead())
                }
            }

            guard let post = try await repository.fetchLinkedPost(postID: postID) else {
                errorMessage = "关联帖子已不存在。"
                return nil
            }

            errorMessage = nil
            return .post(post)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func openSiteAnnouncement(_ announcement: SiteAnnouncement, itemID: String) async -> NotificationOpenResult? {
        do {
            if !announcement.isRead {
                try await repository.markSiteAnnouncementRead(announcementID: announcement.id)
                let readAt = ISO8601DateFormatter().string(from: Date())
                let updatedAnnouncement = announcement.markingRead(at: readAt)
                if let index = items.firstIndex(where: { $0.id == itemID }) {
                    items[index] = .announcement(updatedAnnouncement)
                }
                errorMessage = nil
                return .announcement(updatedAnnouncement)
            }

            errorMessage = nil
            return .announcement(announcement)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

struct CommunityNotificationsSheet: View {
    let onOpenPost: (CommunityPost) -> Void
    let onUnreadStateChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyLanguage) private var leafyLanguage
    @StateObject private var viewModel: CommunityNotificationsViewModel
    @State private var selectedAnnouncement: SiteAnnouncement?
    @State private var selectedPublishTask: CommunityPublishTask?
    @State private var operationAlert: LeafyOperationAlert?

    init(
        repository: any CommunityNotificationRepository,
        onOpenPost: @escaping (CommunityPost) -> Void,
        onUnreadStateChanged: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: CommunityNotificationsViewModel(repository: repository))
        self.onOpenPost = onOpenPost
        self.onUnreadStateChanged = onUnreadStateChanged
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    CommunityNotificationSettingsRow(
                        isMuted: Binding(
                            get: { viewModel.isMutedAll },
                            set: { muted in
                                Task { await setMutedAll(muted) }
                            }
                        ),
                        isUpdating: viewModel.isUpdatingSettings
                    )
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: AppSpacing.compact, leading: AppSpacing.page, bottom: AppSpacing.micro, trailing: AppSpacing.page))

                if viewModel.isLoading && viewModel.items.isEmpty && !viewModel.isMutedAll {
                    Section {
                        CommunityNotificationStateView(
                            title: "正在加载通知",
                            message: "稍等一下，正在同步最新通知。",
                            systemImage: "bell.badge",
                            showsProgress: true
                        )
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else if viewModel.isMutedAll && viewModel.items.isEmpty {
                    Section {
                        CommunityNotificationStateView(
                            title: "已关闭通知",
                            message: "重新打开后会继续接收新的评论和点赞通知。",
                            systemImage: "bell.slash"
                        )
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
                    Section {
                        CommunityNotificationErrorCard(message: errorMessage) {
                            Task { await viewModel.load() }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else if viewModel.items.isEmpty {
                    Section {
                        CommunityNotificationStateView(
                            title: "暂无通知",
                            message: "有全站通知、评论或点赞时会显示在这里。",
                            systemImage: "bell"
                        )
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    Section {
                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .leafyBody()
                                .foregroundStyle(AppTheme.danger)
                                .padding(14)
                                .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                        }

                        ForEach(viewModel.items) { item in
                            Button {
                                Task {
                                    guard let result = await viewModel.openItem(item) else { return }
                                    if !item.isRead {
                                        onUnreadStateChanged()
                                    }
                                    switch result {
                                    case .post(let post):
                                        dismiss()
                                        onOpenPost(post)
                                    case .announcement(let announcement):
                                        selectedAnnouncement = announcement
                                    case .publication(let task):
                                        selectedPublishTask = task
                                    }
                                }
                            } label: {
                                CommunityNotificationCard(
                                    item: item,
                                    isLoading: viewModel.activeItemID == item.id
                                )
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await dismiss(item) }
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                .tint(AppTheme.danger)
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: AppSpacing.page, bottom: 4, trailing: AppSpacing.page))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 1)
            .scrollContentBackground(.hidden)
            .background(LeafyPageBackground())
            .navigationTitle("通知")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyTrailing) {
                    Button {
                        Task { await markAllRead() }
                    } label: {
                        if viewModel.isMarkingAllRead {
                            ProgressView()
                                .scaleEffect(0.78)
                        } else {
                            Label("全部已读", systemImage: "checkmark.circle")
                        }
                    }
                    .disabled(!canMarkAllRead)
                }
            }
            .task {
                await viewModel.load()
            }
            .refreshable {
                await viewModel.load()
            }
            .leafySheet(item: $selectedAnnouncement) { announcement in
                SiteAnnouncementDetailSheet(announcement: announcement)
                    .presentationDetents([.medium, .large])
            }
            .leafySheet(item: $selectedPublishTask) { task in
                CommunityPublishTaskDetailSheet(taskID: task.id)
                    .presentationDetents([.medium, .large])
            }
            .leafyOperationAlert($operationAlert)
        }
    }

    private var canMarkAllRead: Bool {
        viewModel.hasUnreadItems
            && !viewModel.isLoading
            && !viewModel.isMutedAll
            && !viewModel.isMarkingAllRead
    }

    @MainActor
    private func setMutedAll(_ muted: Bool) async {
        guard await viewModel.setMutedAll(muted) else { return }
        onUnreadStateChanged()
    }

    @MainActor
    private func markAllRead() async {
        guard await viewModel.markAllRead() else { return }
        onUnreadStateChanged()
        operationAlert = .success(L10n.text("已标记全部通知为已读。", language: leafyLanguage))
    }

    @MainActor
    private func dismiss(_ item: NotificationFeedItem) async {
        guard await viewModel.dismissItem(item) else { return }
        if !item.isRead {
            onUnreadStateChanged()
        }
        operationAlert = .success(L10n.text("通知已删除。", language: leafyLanguage))
    }
}

private struct CommunityNotificationSettingsRow: View {
    @Binding var isMuted: Bool
    let isUpdating: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isMuted ? "bell.slash.fill" : "bell.badge.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isMuted ? AppTheme.tertiaryText : AppTheme.accentEmphasis)
                .frame(width: 30, height: 30)
                .background(AppTheme.softFill, in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("关闭通知")
                    .leafyBody()
                    .foregroundStyle(AppTheme.primaryText)
                Text("关闭后评论和点赞不会再生成新通知。")
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: AppSpacing.compact)

            Toggle("", isOn: $isMuted)
                .labelsHidden()
                .disabled(isUpdating)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .stroke(AppTheme.separator, lineWidth: 1)
        )
        .opacity(isUpdating ? 0.72 : 1)
    }
}

private struct CommunityNotificationStateView: View {
    let title: String
    let message: String
    let systemImage: String
    var showsProgress = false

    var body: some View {
        VStack(spacing: 10) {
            if showsProgress {
                ProgressView()
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppTheme.tertiaryText)
            }

            VStack(spacing: 3) {
                Text(title)
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)
                Text(message)
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

private struct CommunityNotificationCard: View {
    let item: NotificationFeedItem
    let isLoading: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: item.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.title)
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !item.isRead {
                        Circle()
                            .fill(AppTheme.danger)
                            .frame(width: 7, height: 7)
                            .accessibilityLabel("未读")
                    }
                }

                if let body = item.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
                    Text(body)
                        .leafySubheadline()
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Text(item.relativeTimestamp)
                        .microCaption()
                        .foregroundStyle(AppTheme.tertiaryText)

                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.72)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .stroke(item.isRead ? AppTheme.separator : tint.opacity(0.24), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .opacity(item.isRead ? 0.78 : 1)
    }

    private var tint: Color {
        switch item {
        case .community(let notification):
            return notification.type == .like ? AppTheme.featureTints[1] : AppTheme.featureTints[0]
        case .announcement(let announcement):
            switch announcement.level {
            case .info:
                return AppTheme.accent
            case .warning:
                return AppTheme.warning
            case .urgent:
                return AppTheme.danger
            }
        case .publication(let notification):
            return notification.task.state == .published ? .green : AppTheme.danger
        }
    }
}

private struct CommunityPublishTaskDetailSheet: View {
    let taskID: UUID

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var coordinator = CommunityPublishCoordinator.shared

    private var task: CommunityPublishTask? {
        coordinator.tasks.first { $0.id == taskID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let task {
                    VStack(alignment: .leading, spacing: AppSpacing.card) {
                        LeafySectionTitle(task.state.title, subtitle: task.input.title)

                        ProgressView(value: task.progress)
                            .tint(task.state == .failed ? AppTheme.danger : AppTheme.accent)

                        if let errorMessage = task.errorMessage {
                            CommunityInlineError(message: errorMessage)
                        }

                        ForEach(task.media) { media in
                            HStack(spacing: 12) {
                                Image(systemName: media.kind == .image ? "photo" : "paperclip")
                                    .foregroundStyle(AppTheme.accentEmphasis)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(media.displayName)
                                        .leafyBody()
                                    Text(media.validated ? "已校验" : media.errorMessage ?? "\(Int(media.progress * 100))%")
                                        .microCaption()
                                        .foregroundStyle(media.errorMessage == nil ? AppTheme.secondaryText : AppTheme.danger)
                                }
                                Spacer()
                            }
                            .padding(14)
                            .leafyCardStyle()
                        }

                        if task.state == .failed {
                            Button("重试发布") {
                                coordinator.retry(taskID: task.id)
                            }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                        }

                        if task.state != .published && task.state != .cancelled {
                            Button("取消任务", role: .destructive) {
                                coordinator.cancel(taskID: task.id)
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(AppSpacing.page)
                } else {
                    ContentUnavailableView("任务已不存在", systemImage: "tray")
                }
            }
            .background(LeafyPageBackground())
            .navigationTitle("发布任务")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct SiteAnnouncementDetailSheet: View {
    let announcement: SiteAnnouncement

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    LeafySectionTitle(announcement.title, subtitle: announcement.relativeTimestamp)

                    HStack(spacing: 8) {
                        LeafyIconBadge(systemName: announcement.systemImage, tint: tint)

                        Text(levelText)
                            .leafySubheadline()
                            .foregroundStyle(tint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(tint.opacity(0.12), in: Capsule())
                    }

                    Text(announcement.body)
                        .leafyBody()
                        .foregroundStyle(AppTheme.primaryText)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .leafyCardStyle()
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle("全站通知")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var tint: Color {
        switch announcement.level {
        case .info:
            return AppTheme.accent
        case .warning:
            return AppTheme.warning
        case .urgent:
            return AppTheme.danger
        }
    }

    private var levelText: String {
        switch announcement.level {
        case .info:
            return "普通公告"
        case .warning:
            return "重要公告"
        case .urgent:
            return "紧急公告"
        }
    }
}

private struct CommunityNotificationErrorCard: View {
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
