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

enum CommunityProfileOptions {
    static let colleges = CommunityCatalogOptions.units

    static var grades: [String] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return stride(from: currentYear, through: currentYear - 6, by: -1).map { "\($0)级" }
    }
}

struct CommunityProfileOptionMenu: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let title: String
    let placeholder: String
    let options: [String]
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text(title, language: leafyLanguage))
                .leafyHeadline()

            Menu {
                Button {
                    selection = ""
                } label: {
                    optionLabel(placeholder, isSelected: selection.isEmpty)
                }

                Divider()

                ForEach(options, id: \.self) { option in
                    Button {
                        selection = option
                    } label: {
                        optionLabel(option, isSelected: selection == option)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(selection.isEmpty ? L10n.text(placeholder, language: leafyLanguage) : displayText(selection))
                        .leafyBody()
                        .foregroundStyle(selection.isEmpty ? AppTheme.tertiaryText : AppTheme.primaryText)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.accentEmphasis)
                }
                .padding(14)
                .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func optionLabel(_ text: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(displayText(text), systemImage: "checkmark")
        } else {
            Text(displayText(text))
        }
    }

    private func displayText(_ text: String) -> String {
        if text.hasSuffix("级"), let year = text.dropLast().wholeNumberValue {
            return L10n.text("%d 级", language: leafyLanguage, year)
        }
        return L10n.text(text, language: leafyLanguage)
    }
}

extension Substring {
    var wholeNumberValue: Int? {
        Int(String(self))
    }
}

struct CommunityProfileEditorSheet: View {
    var body: some View {
        NavigationStack {
            CommunityProfileEditorView(showsCancelButton: true)
        }
    }
}

struct CommunityProfileEditorView: View {
    @ObservedObject private var sessionManager = CommunitySessionManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyLanguage) private var leafyLanguage
    @State private var nickname = ""
    @State private var bio = ""
    @State private var college = ""
    @State private var grade = ""
    @State private var showsEduVerificationBadge = false
    @State private var showingAvatarPicker = false
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var avatarCropDraft: CommunityAvatarCropDraft?
    @State private var avatarPreview: UIImage?
    @State private var avatarUpload: CommunityImageUpload?
    @State private var coverPreview: UIImage?
    @State private var coverUpload: CommunityImageUpload?
    @State private var resetCoverToDefault = false
    @State private var errorMessage: String?
    @State private var isLoadingAvatar = false
    @State private var isSaving = false
    @State private var showingCampusChangeSheet = false
    @State private var pendingCampusRequest: CommunityCampusMembershipRequest?
    @State private var isLoadingCampusRequest = false
    @State private var operationAlert: LeafyOperationAlert?

    var showsCancelButton = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.card) {

                if let errorMessage {
                    Text(errorMessage)
                        .leafyBody()
                        .foregroundStyle(AppTheme.danger)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 16) {
                        CommunityAvatarPreview(image: avatarPreview, profile: sessionManager.profile, size: 72)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Button {
                                    showingAvatarPicker = true
                                } label: {
                                    HStack(spacing: 8) {
                                        if isLoadingAvatar {
                                            ProgressView()
                                                .controlSize(.small)
                                        }

                                        Text(isLoadingAvatar ? L10n.text("读取中", language: leafyLanguage) : L10n.text("选择头像", language: leafyLanguage))
                                            .leafyBody()
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.86)
                                    }
                                    .foregroundStyle(AppTheme.accentEmphasis)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(AppTheme.softFill, in: Capsule())
                                    .contentShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .disabled(isLoadingAvatar)

                                NavigationLink {
                                    CommunityProfileCoverEditorView(
                                        profile: sessionManager.profile,
                                        coverPreview: $coverPreview,
                                        coverUpload: $coverUpload,
                                        resetCoverToDefault: $resetCoverToDefault
                                    )
                                } label: {
                                    Text(L10n.text("选择主页背景", language: leafyLanguage))
                                        .leafyBody()
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.86)
                                        .foregroundStyle(AppTheme.accentEmphasis)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(AppTheme.softFill, in: Capsule())
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }

                            Text(mediaStatusText)
                                .microCaption()
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }

                    if let profile = sessionManager.profile {
                        infoRow(title: "教务实名", value: profile.displayName ?? L10n.text("未获取", language: leafyLanguage))
                        infoRow(title: "绑定学号", value: profile.eduID)
                    }

                    CommunityProfileCampusSection(
                        profile: sessionManager.profile,
                        pendingRequest: pendingCampusRequest,
                        isLoading: isLoadingCampusRequest,
                        onChangeTapped: {
                            showingCampusChangeSheet = true
                        }
                    )

                    Toggle(isOn: $showsEduVerificationBadge) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.text("公开实名认证标记", language: leafyLanguage))
                                .leafyBody()
                                .foregroundStyle(AppTheme.primaryText)
                            Text(L10n.text("开启后别人只会看到“已完成教务实名”，不会显示姓名或学号。", language: leafyLanguage))
                                .microCaption()
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                    .tint(AppTheme.accent)

                    HStack {
                        Text(L10n.text("昵称", language: leafyLanguage))
                            .leafyHeadline()

                        Spacer()

                        Text("\(nickname.count)/\(CommunityNickname.maxLength)")
                            .microCaption()
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    TextField(L10n.text("输入社区昵称", language: leafyLanguage), text: $nickname)
                        .leafyDisableAutocapitalization()
                        .padding(14)
                        .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                        .onChange(of: nickname) { _, newValue in
                            let limitedNickname = CommunityNickname.limited(newValue)
                            if limitedNickname != newValue {
                                nickname = limitedNickname
                            }
                        }

                    HStack {
                        Text(L10n.text("签名", language: leafyLanguage))
                            .leafyHeadline()

                        Spacer()

                        Text("\(bio.count)/\(CommunityProfileBio.maxLength)")
                            .microCaption()
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    TextField(L10n.text("写一句个人签名", language: leafyLanguage), text: $bio, axis: .vertical)
                        .leafyDisableAutocapitalization()
                        .lineLimit(2...4)
                        .padding(14)
                        .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                        .onChange(of: bio) { _, newValue in
                            let limitedBio = CommunityProfileBio.limited(newValue)
                            if limitedBio != newValue {
                                bio = limitedBio
                            }
                        }

                    CommunityProfileOptionMenu(
                        title: "学院",
                        placeholder: "不显示学院",
                        options: CommunityProfileOptions.colleges,
                        selection: $college
                    )

                    CommunityProfileOptionMenu(
                        title: "年级",
                        placeholder: "不显示年级",
                        options: CommunityProfileOptions.grades,
                        selection: $grade
                    )
                }
                .padding(18)
                .leafyCardStyle()
            }
        }
        .padding(AppSpacing.page)
        .background(LeafyPageBackground())
        .navigationTitle(L10n.text("编辑资料", language: leafyLanguage))
        .leafyInlineNavigationTitle()
        .task {
            await sessionManager.restoreProfileIfPossible()
            await sessionManager.bootstrapCommunityUser()
            syncFieldsFromProfile()
            await loadPendingCampusRequest()
        }
        .onChange(of: selectedAvatarItem) { _, newItem in
            Task {
                await loadSelectedAvatar(from: newItem)
            }
        }
        .photosPicker(
            isPresented: $showingAvatarPicker,
            selection: $selectedAvatarItem,
            matching: .images
        )
        .sheet(item: $avatarCropDraft) { draft in
            CommunityAvatarCropSheet(image: draft.image) { croppedImage in
                applyCroppedAvatar(croppedImage)
            }
        }
        .sheet(isPresented: $showingCampusChangeSheet) {
            CommunityCampusChangeSheet(
                profile: sessionManager.profile,
                pendingRequest: $pendingCampusRequest
            )
            .presentationDetents([.medium, .large])
        }
        .toolbar {
            if showsCancelButton {
                ToolbarItem(placement: .leafyLeading) {
                    Button(L10n.text("取消", language: leafyLanguage)) {
                        dismiss()
                    }
                }
            }
            ToolbarItem(placement: .leafyTrailing) {
                Button(isSaving ? L10n.text("保存中", language: leafyLanguage) : L10n.text("保存", language: leafyLanguage)) {
                    Task {
                        await saveProfile()
                    }
                }
                .disabled(isSaving || CommunityNickname.normalized(nickname).isEmpty)
            }
        }
        .leafyOperationAlert($operationAlert)
    }

    @ViewBuilder
    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(L10n.text(title, language: leafyLanguage))
                .leafyBody()
                .foregroundStyle(AppTheme.secondaryText)
            Spacer()
            Text(value)
                .leafyBody()
                .foregroundStyle(AppTheme.primaryText)
        }
    }

    private var mediaStatusText: String {
        if resetCoverToDefault {
            return L10n.text("保存后主页会使用默认背景。", language: leafyLanguage)
        }
        if coverUpload != nil {
            return L10n.text("已选择新的主页背景，保存后生效。", language: leafyLanguage)
        }
        return L10n.text("头像和主页背景都可以不填，未设置时使用默认样式。", language: leafyLanguage)
    }

    @MainActor
    private func loadPendingCampusRequest() async {
        isLoadingCampusRequest = true
        defer { isLoadingCampusRequest = false }

        do {
            pendingCampusRequest = try await sessionManager.fetchCurrentCampusMembershipRequest()
        } catch {
            pendingCampusRequest = nil
        }
    }

    private func syncFieldsFromProfile() {
        guard let profile = sessionManager.profile else { return }
        if nickname.isEmpty { nickname = CommunityNickname.limited(profile.nickname) }
        if bio.isEmpty { bio = CommunityProfileBio.limited(profile.trimmedBio ?? "") }
        showsEduVerificationBadge = profile.showsEduVerificationBadge
        if college.isEmpty {
            let storedCollege = profile.major ?? ""
            college = CommunityProfileOptions.colleges.contains(storedCollege) ? storedCollege : ""
        }
        if grade.isEmpty {
            let storedGrade = profile.grade ?? ""
            grade = CommunityProfileOptions.grades.contains(storedGrade) ? storedGrade : ""
        }
    }

    private func loadSelectedAvatar(from item: PhotosPickerItem?) async {
        guard let item else { return }
        isLoadingAvatar = true
        defer { isLoadingAvatar = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = L10n.text("无法读取这张图片，请换一张头像。", language: leafyLanguage)
                return
            }

            guard let image = ImageDataDecoder.decodedImage(from: data) else {
                errorMessage = L10n.text("无法读取这张图片，请换一张头像。", language: leafyLanguage)
                return
            }

            avatarCropDraft = CommunityAvatarCropDraft(image: image)
            errorMessage = nil
        } catch {
            errorMessage = L10n.text("加载头像失败：%@", language: leafyLanguage, error.localizedDescription)
        }
    }

    @MainActor
    private func applyCroppedAvatar(_ image: UIImage) {
        do {
            let upload = try CommunityImageUpload.compressedJPEG(
                from: image,
                maxPixelDimension: CommunityImageUpload.avatarImageMaxPixelDimension,
                maxBytes: CommunityImageUpload.avatarImageMaxBytes
            )
            avatarPreview = ImageDataDecoder.decodedImage(
                from: upload.data,
                targetSize: CGSize(width: 128, height: 128)
            ) ?? image
            avatarUpload = upload
            errorMessage = nil
        } catch {
            errorMessage = L10n.text("加载头像失败：%@", language: leafyLanguage, error.localizedDescription)
        }
    }

    private func saveProfile() async {
        isSaving = true
        defer { isSaving = false }

        await sessionManager.bootstrapCommunityUser(force: true)
        if let bootstrapError = sessionManager.bootstrapError {
            errorMessage = bootstrapError
            return
        }

        guard sessionManager.profile != nil else {
            errorMessage = L10n.text("社区身份尚未建立，请确认教务登录仍有效后重试。", language: leafyLanguage)
            return
        }

        do {
            let updatedProfile = try await sessionManager.updateProfile(
                input: CommunityProfileUpdateInput(
                    nickname: CommunityNickname.normalized(nickname),
                    major: college,
                    grade: grade,
                    bio: CommunityProfileBio.normalized(bio),
                    showsEduVerificationBadge: showsEduVerificationBadge
                ),
                avatar: avatarUpload,
                cover: coverUpload,
                resetCoverToDefault: resetCoverToDefault
            )
            if let avatarUpload {
                try? CommunityAvatarCache.shared.save(data: avatarUpload.data, for: updatedProfile)
            }
            errorMessage = nil
            operationAlert = .success(
                L10n.text("资料已保存！", language: leafyLanguage),
                action: { dismiss() }
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CommunityProfileCampusSection: View {
    let profile: CommunityProfile?
    let pendingRequest: CommunityCampusMembershipRequest?
    let isLoading: Bool
    let onChangeTapped: () -> Void

    private var currentSchoolName: String {
        profile?.communitySchoolDisplayName ?? "尚未选择"
    }

    private var canRequestChange: Bool {
        ActiveCampusContext.identity?.isCustom == true
            && profile?.hasApprovedCommunityAccess == true
            && pendingRequest?.isPending != true
    }

    private var statusText: String {
        if isLoading {
            return "正在同步学校申请状态…"
        }
        if let pendingRequest, pendingRequest.isPending {
            switch pendingRequest.requestType {
            case .schoolChange:
                return "正在审核更换到 \(pendingRequest.schoolName) 的申请；通过前仍保留当前学校社区。"
            case .initialNewSchool:
                return "\(pendingRequest.schoolName) 的新增学校申请正在审核。"
            }
        }
        guard let profile else {
            return "社区身份尚未建立。"
        }
        if profile.hasApprovedCommunityAccess {
            return "当前只归属一个学校社区；更换到其它已有学校需要审核。"
        }
        switch profile.communityAccessStatus {
        case .pending:
            return "学校申请正在审核中。"
        case .rejected:
            return profile.communityRejectionReason ?? "学校申请未通过。"
        case .general:
            return "通用入口尚未选择学校社区。"
        case .approved:
            return "学校社区正在同步。"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "building.2")
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text("学校社区")
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)
                    Text(currentSchoolName)
                        .leafyBody()
                        .foregroundStyle(AppTheme.primaryText)
                    Text(statusText)
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
            }

            if canRequestChange {
                Button("更换学校社区", action: onChangeTapped)
                    .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }
}

private struct CommunityCampusChangeSheet: View {
    @ObservedObject private var sessionManager = CommunitySessionManager.shared
    @Environment(\.dismiss) private var dismiss
    let profile: CommunityProfile?
    @Binding var pendingRequest: CommunityCampusMembershipRequest?
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var currentSchoolName: String? {
        profile?.communitySchoolDisplayName
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    VStack(alignment: .leading, spacing: AppSpacing.micro) {
                        Text("更换学校社区")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.primaryText)
                        Text("提交后需要管理员审核。审核通过前，你仍留在当前学校社区。")
                            .leafyBody()
                            .foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .leafyBody()
                            .foregroundStyle(AppTheme.danger)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                    }

                    CommunityCampusSelectionPanel(
                        mode: .change(currentSchoolName: currentSchoolName),
                        isSubmitting: isSubmitting,
                        onSelectCampus: { campus in
                            Task { await submitChange(to: campus) }
                        },
                        onSubmitNewSchool: nil
                    )
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle("学校社区")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }

    @MainActor
    private func submitChange(to campus: CommunityCampusOption) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            pendingRequest = try await sessionManager.submitCommunitySchoolChangeRequest(campusID: campus.id)
            errorMessage = nil
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CommunityProfileCoverEditorView: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let profile: CommunityProfile?
    @Binding var coverPreview: UIImage?
    @Binding var coverUpload: CommunityImageUpload?
    @Binding var resetCoverToDefault: Bool

    @State private var showingCoverPicker = false
    @State private var selectedCoverItem: PhotosPickerItem?
    @State private var coverCropDraft: CommunityCoverCropDraft?
    @State private var isLoadingCover = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.card) {
                VStack(alignment: .leading, spacing: 12) {
                    CommunityProfileCoverPreview(
                        image: coverPreview,
                        profile: resetCoverToDefault ? nil : profile
                    )

                    HStack(spacing: 10) {
                        Button {
                            showingCoverPicker = true
                        } label: {
                            HStack(spacing: 8) {
                                if isLoadingCover {
                                    ProgressView()
                                        .controlSize(.small)
                                }

                                Text(isLoadingCover ? L10n.text("读取中", language: leafyLanguage) : L10n.text("选择照片", language: leafyLanguage))
                                    .leafyBody()
                            }
                            .foregroundStyle(AppTheme.accentEmphasis)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(AppTheme.softFill, in: Capsule())
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoadingCover)

                        Button {
                            coverPreview = nil
                            coverUpload = nil
                            resetCoverToDefault = true
                        } label: {
                            Text(L10n.text("使用默认背景", language: leafyLanguage))
                                .leafyBody()
                                .foregroundStyle(AppTheme.accentEmphasis)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(AppTheme.softFill, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Text(statusText)
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .padding(18)
                .leafyCardStyle()

                if let errorMessage {
                    Text(errorMessage)
                        .leafyBody()
                        .foregroundStyle(AppTheme.danger)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                }
            }
        }
        .padding(AppSpacing.page)
        .background(LeafyPageBackground())
        .navigationTitle(L10n.text("主页背景", language: leafyLanguage))
        .leafyInlineNavigationTitle()
        .photosPicker(
            isPresented: $showingCoverPicker,
            selection: $selectedCoverItem,
            matching: .images
        )
        .onChange(of: selectedCoverItem) { _, newItem in
            Task {
                await loadSelectedCover(from: newItem)
            }
        }
        .sheet(item: $coverCropDraft) { draft in
            CommunityCoverCropSheet(image: draft.image) { croppedImage in
                applyCroppedCover(croppedImage)
            }
        }
    }

    private var statusText: String {
        if resetCoverToDefault {
            return L10n.text("保存资料后会恢复为内置默认背景。", language: leafyLanguage)
        }
        if coverUpload != nil {
            return L10n.text("拖动裁切后的背景会在保存资料后生效。", language: leafyLanguage)
        }
        return L10n.text("未设置时使用内置默认背景，也可以选择照片后裁切。", language: leafyLanguage)
    }

    private func loadSelectedCover(from item: PhotosPickerItem?) async {
        guard let item else { return }
        isLoadingCover = true
        defer { isLoadingCover = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = ImageDataDecoder.decodedImage(from: data) else {
                errorMessage = L10n.text("无法读取这张图片，请换一张背景图。", language: leafyLanguage)
                return
            }

            coverCropDraft = CommunityCoverCropDraft(image: image)
            errorMessage = nil
        } catch {
            errorMessage = L10n.text("加载背景图失败：%@", language: leafyLanguage, error.localizedDescription)
        }
    }

    @MainActor
    private func applyCroppedCover(_ image: UIImage) {
        do {
            let upload = try CommunityImageUpload.compressedJPEG(
                from: image,
                maxPixelDimension: CommunityImageUpload.profileCoverImageMaxPixelDimension,
                maxBytes: CommunityImageUpload.profileCoverImageMaxBytes
            )
            coverPreview = ImageDataDecoder.decodedImage(
                from: upload.data,
                targetSize: CGSize(width: 720, height: 320)
            ) ?? image
            coverUpload = upload
            resetCoverToDefault = false
            errorMessage = nil
        } catch {
            errorMessage = L10n.text("加载背景图失败：%@", language: leafyLanguage, error.localizedDescription)
        }
    }
}

struct CommunityAvatarView: View {
    @AppStorage("appThemeColorPreference") private var appThemeColorPreferenceRaw = AppThemeColorPreference.green.rawValue

    let profile: CommunityProfile?
    let size: CGFloat

    @State private var avatarImage: UIImage?

    var body: some View {
        Group {
            if let avatarImage {
                Image(uiImage: avatarImage)
                    .resizable()
                    .scaledToFill()
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(AppTheme.separator, lineWidth: 1)
        )
        .task(id: avatarTaskID) {
            await loadAvatar()
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(themeColor.opacity(0.18))
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(themeColor)
            )
    }

    private var avatarTaskID: String {
        [
            profile?.id.uuidString ?? "anonymous",
            profile?.avatarPath ?? "",
            profile?.resolvedAvatarURL?.absoluteString ?? ""
        ].joined(separator: "|")
    }

    private var themeColor: Color {
        AppThemeColorPreference.storedValue(appThemeColorPreferenceRaw).swatchColor
    }

    @MainActor
    private func loadAvatar() async {
        avatarImage = CommunityAvatarCache.shared.image(for: profile)
        guard avatarImage == nil,
              let profile,
              let url = profile.resolvedAvatarURL else {
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled,
                  let image = ImageDataDecoder.decodedImage(
                    from: data,
                    targetSize: CGSize(width: size, height: size)
                  )
            else { return }
            try? CommunityAvatarCache.shared.save(data: data, for: profile)
            avatarImage = image
        } catch {
            avatarImage = nil
        }
    }
}

struct CommunityAvatarPreview: View {
    let image: UIImage?
    let profile: CommunityProfile?
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                CommunityAvatarView(profile: profile, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

struct CommunityProfileCoverPreview: View {
    let image: UIImage?
    let profile: CommunityProfile?
    var usesFixedAspectRatio = true

    var body: some View {
        GeometryReader { proxy in
            coverContent
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .frame(maxWidth: .infinity)
        .modifier(CommunityProfileCoverAspectModifier(isEnabled: usesFixedAspectRatio))
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .stroke(AppTheme.separator, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var coverContent: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let url = profile?.resolvedCoverURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        CommunityProfileDefaultCover()
                            .overlay(ProgressView().controlSize(.small))
                    case .success(let loadedImage):
                        loadedImage
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        CommunityProfileDefaultCover()
                    @unknown default:
                        CommunityProfileDefaultCover()
                    }
                }
            } else {
                CommunityProfileDefaultCover()
            }
        }
    }
}

private struct CommunityProfileCoverAspectModifier: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.aspectRatio(2.25, contentMode: .fit)
        } else {
            content
        }
    }
}

struct CommunityProfileDefaultCover: View {
    @AppStorage(AppThemeColorPreference.storageKey) private var appThemeColorPreferenceRaw = AppThemeColorPreference.green.rawValue

    var body: some View {
        LinearGradient(
            colors: [
                themeColor.opacity(0.9),
                AppTheme.softFill,
                Color(uiColor: .secondarySystemBackground)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(.white.opacity(0.26))
                .padding(18)
        }
    }

    private var themeColor: Color {
        AppThemeColorPreference.storedValue(appThemeColorPreferenceRaw).swatchColor
    }
}

struct CommunityAvatarCropDraft: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct CommunityCoverCropDraft: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct CommunityCoverCropSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyLanguage) private var leafyLanguage

    let image: UIImage
    let onConfirm: (UIImage) -> Void

    @State private var offset = CGSize.zero
    @State private var baseOffset = CGSize.zero
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1

    private let cropWidth: CGFloat = 320
    private let cropHeight: CGFloat = 142
    private var cropAspectRatio: CGFloat { cropWidth / cropHeight }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Spacer(minLength: 12)

                ZStack {
                    Color.black.opacity(0.9)

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(scale)
                        .offset(offset)
                        .frame(width: cropWidth, height: cropHeight)
                        .clipShape(Rectangle())
                        .gesture(dragGesture)
                        .simultaneousGesture(magnificationGesture)

                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.9), lineWidth: 2)
                        .allowsHitTesting(false)
                }
                .frame(width: cropWidth, height: cropHeight)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                Text(L10n.text("拖动或缩放背景图，保留框中的部分。", language: leafyLanguage))
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)

                Spacer(minLength: 12)
            }
            .padding(AppSpacing.page)
            .background(LeafyPageBackground())
            .navigationTitle(L10n.text("裁切主页背景", language: leafyLanguage))
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyLeading) {
                    Button(L10n.text("取消", language: leafyLanguage)) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .leafyTrailing) {
                    Button(L10n.text("使用", language: leafyLanguage)) {
                        onConfirm(croppedImage())
                        dismiss()
                    }
                }
            }
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

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(baseScale * value, 1), 4)
            }
            .onEnded { _ in
                baseScale = scale
            }
    }

    private func croppedImage() -> UIImage {
        image.leafyCoverImage(
            width: CommunityImageUpload.profileCoverImageMaxPixelDimension,
            aspectRatio: cropAspectRatio,
            viewSize: CGSize(width: cropWidth, height: cropHeight),
            scale: scale,
            offset: offset
        )
    }
}

struct CommunityAvatarCropSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyLanguage) private var leafyLanguage

    let image: UIImage
    let onConfirm: (UIImage) -> Void

    @State private var offset = CGSize.zero
    @State private var baseOffset = CGSize.zero
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1

    private let cropSide: CGFloat = 280

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Spacer(minLength: 12)

                ZStack {
                    Color.black.opacity(0.9)

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(scale)
                        .offset(offset)
                        .frame(width: cropSide, height: cropSide)
                        .clipShape(Rectangle())
                        .gesture(dragGesture)
                        .simultaneousGesture(magnificationGesture)

                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.9), lineWidth: 2)
                        .allowsHitTesting(false)
                }
                .frame(width: cropSide, height: cropSide)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                Text(L10n.text("拖动或缩放头像，保留方框中的部分。", language: leafyLanguage))
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)

                Spacer(minLength: 12)
            }
            .padding(AppSpacing.page)
            .background(LeafyPageBackground())
            .navigationTitle(L10n.text("裁切头像", language: leafyLanguage))
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyLeading) {
                    Button(L10n.text("取消", language: leafyLanguage)) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .leafyTrailing) {
                    Button(L10n.text("使用", language: leafyLanguage)) {
                        onConfirm(croppedImage())
                        dismiss()
                    }
                }
            }
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

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(baseScale * value, 1), 4)
            }
            .onEnded { _ in
                baseScale = scale
            }
    }

    private func croppedImage() -> UIImage {
        image.leafySquareAvatarImage(
            sideLength: CommunityImageUpload.avatarImageMaxPixelDimension,
            viewSideLength: cropSide,
            scale: scale,
            offset: offset
        )
    }
}

extension UIImage {
    func leafySquareAvatarImage(
        sideLength: CGFloat,
        viewSideLength: CGFloat,
        scale userScale: CGFloat,
        offset: CGSize
    ) -> UIImage {
        let outputSide = max(1, sideLength.rounded())
        let outputSize = CGSize(width: outputSide, height: outputSide)
        let viewToOutputScale = outputSide / viewSideLength
        let baseScale = max(viewSideLength / size.width, viewSideLength / size.height)
        let displayedSize = CGSize(
            width: size.width * baseScale * userScale * viewToOutputScale,
            height: size.height * baseScale * userScale * viewToOutputScale
        )
        let origin = CGPoint(
            x: ((viewSideLength - (size.width * baseScale * userScale)) / 2 + offset.width) * viewToOutputScale,
            y: ((viewSideLength - (size.height * baseScale * userScale)) / 2 + offset.height) * viewToOutputScale
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: outputSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: outputSize))
            draw(in: CGRect(origin: origin, size: displayedSize))
        }
    }

    func leafyCoverImage(
        width: CGFloat,
        aspectRatio: CGFloat,
        viewSize: CGSize,
        scale userScale: CGFloat,
        offset: CGSize
    ) -> UIImage {
        let outputWidth = max(1, width.rounded())
        let outputHeight = max(1, (outputWidth / aspectRatio).rounded())
        let outputSize = CGSize(width: outputWidth, height: outputHeight)
        let viewToOutputScale = outputWidth / viewSize.width
        let baseScale = max(viewSize.width / size.width, viewSize.height / size.height)
        let displayedSize = CGSize(
            width: size.width * baseScale * userScale * viewToOutputScale,
            height: size.height * baseScale * userScale * viewToOutputScale
        )
        let origin = CGPoint(
            x: ((viewSize.width - (size.width * baseScale * userScale)) / 2 + offset.width) * viewToOutputScale,
            y: ((viewSize.height - (size.height * baseScale * userScale)) / 2 + offset.height) * viewToOutputScale
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: outputSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: outputSize))
            draw(in: CGRect(origin: origin, size: displayedSize))
        }
    }
}
