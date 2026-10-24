import SwiftUI
import UIKit

/// Named row types keep settings destinations out of the root list's generic metadata.
struct ProfileSettingsRows: View {
    @Environment(\.leafyLanguage) private var language
    let isCommunityEnabled: Bool
    let lastSyncValue: String
    let semesterValue: String
    let iCloudValue: String
    let sharingValue: String
    let personalizationValue: String
    let timetableBackgroundValue: String
    @Binding var hidesWeekends: Bool

    var body: some View {
        Section(L10n.text("课表", language: language)) {
            NavigationLink(value: ProfileRoute.cacheSync) {
                ProfileMenuRow(icon: "arrow.triangle.2.circlepath", title: "重新同步", value: lastSyncValue)
            }
            .profileCompactMenuRow()
            NavigationLink(value: ProfileRoute.timetableSettings) {
                ProfileMenuRow(icon: "calendar.badge.clock", title: "课表设置", value: semesterValue)
            }
            .accessibilityHint(L10n.text("新学期开始前，请检查首周周一日期", language: language))
            .profileCompactMenuRow()
            NavigationLink(value: ProfileRoute.iCloudSync) {
                ProfileMenuRow(icon: "icloud", title: "iCloud 同步", value: iCloudValue)
            }
            .profileCompactMenuRow()
            if isCommunityEnabled {
                NavigationLink(value: ProfileRoute.timetableSharing) {
                    ProfileMenuRow(icon: "person.2.fill", title: "共享课表", value: sharingValue)
                }
                .profileCompactMenuRow()
            }
        }
        Section(L10n.text("偏好", language: language)) {
            NavigationLink(value: ProfileRoute.personalization) {
                ProfileMenuRow(icon: "paintpalette.fill", title: "个性化", value: personalizationValue)
            }
            .profileCompactMenuRow()
            NavigationLink(value: ProfileRoute.timetableBackground) {
                ProfileMenuRow(icon: "rectangle.3.group.fill", title: "课表背景", value: timetableBackgroundValue)
            }
            .profileCompactMenuRow()
            ProfileHideWeekendsRow(isOn: $hidesWeekends)
        }
    }
}

extension View {
    func profileCompactMenuRow() -> some View {
        listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
    }
}

struct ProfileMenuRow: View {
    @Environment(\.leafyLanguage) private var language
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let icon: String
    let title: String
    var value: String? = nil
    var tint: Color = AppTheme.accent
    var showsDisclosure = false
    var isLoading = false

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            LeafyCompactProfileIconBadge(systemName: icon, tint: tint, size: 28)
                .accessibilityHidden(true)
            Text(L10n.text(title, language: language))
                .font(.body)
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            Spacer(minLength: 8)
            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                if let value, !value.isEmpty {
                    Text(value)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                }
                if showsDisclosure { LeafyDisclosureIndicator() }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ProfileHideWeekendsRow: View {
    @Environment(\.leafyLanguage) private var language
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 11) {
                LeafyCompactProfileIconBadge(systemName: "calendar.badge.minus", size: 28)
                    .accessibilityHidden(true)
                Text(L10n.text("隐藏周末", language: language))
                    .font(.body)
                    .foregroundStyle(AppTheme.primaryText)
            }
        }
        .tint(AppTheme.accent)
        .profileCompactMenuRow()
    }
}

struct ProfileDeveloperContactCard: View {
    @Environment(\.openURL) private var openURL
    @State private var showsContacts = false
    @State private var mailUnavailable = false
    private let email = "huoweifang@foxmail.com"

    var body: some View {
        Button { showsContacts = true } label: {
            HStack(spacing: 16) {
                Image("DeveloperMemoji")
                    .resizable().scaledToFit().frame(width: 72, height: 72)
                    .accessibilityHidden(true)
                Spacer(minLength: 12)
                Text("找到我").font(.headline).foregroundStyle(AppTheme.primaryText)
                LeafyDisclosureIndicator()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("找到我")
        .accessibilityHint("选择邮箱或小红书联系")
        .confirmationDialog("找到我", isPresented: $showsContacts, titleVisibility: .visible) {
            Button("邮箱：\(email)") {
                openURL(URL(string: "mailto:" + email)!) { accepted in
                    if !accepted { mailUnavailable = true }
                }
            }
            Button("小红书") { openURL(URL(string: "https://xhslink.cn/o/3PFBj45O8EQ")!) }
            Button("取消", role: .cancel) {}
        }
        .alert("无法打开邮件 App", isPresented: $mailUnavailable) {
            Button("复制邮箱") { UIPasteboard.general.string = email }
            Button("取消", role: .cancel) {}
        } message: { Text(email) }
        .tint(.black)
    }
}
