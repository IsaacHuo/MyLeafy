import SwiftUI
import UIKit

/// Named row types keep settings destinations out of the root list's generic metadata.
struct ProfileSettingsRows: View {
    let isCustomCampus: Bool
    let isCommunityEnabled: Bool
    let personalizationDetail: String
    let timetableBackgroundDetail: String
    @Binding var hidesWeekends: Bool

    var body: some View {
        NavigationLink(value: ProfileRoute.cacheSync) {
            ProfileMenuRow(icon: "arrow.triangle.2.circlepath", title: "重新同步",
                           detail: isCustomCampus ? "检查本地数据状态" : "重新同步教务数据")
        }
        NavigationLink(value: ProfileRoute.timetableSettings) {
            ProfileMenuRow(icon: "calendar.badge.clock", title: "课表设置", detail: "学期、开学日期与节次时间")
        }
        NavigationLink(value: ProfileRoute.iCloudSync) {
            ProfileMenuRow(icon: "icloud", title: "iCloud 同步", detail: "同步个人数据与设置")
        }
        if isCommunityEnabled {
            NavigationLink(value: ProfileRoute.timetableSharing) {
                ProfileMenuRow(icon: "person.2.fill", title: "共享课表", detail: "邀请同学查看")
            }
        }
        NavigationLink(value: ProfileRoute.personalization) {
            ProfileMenuRow(icon: "paintpalette.fill", title: "个性化", detail: personalizationDetail)
        }
        NavigationLink(value: ProfileRoute.timetableBackground) {
            ProfileMenuRow(icon: "rectangle.3.group.fill", title: "课表背景", detail: timetableBackgroundDetail)
        }
        ProfileHideWeekendsRow(isOn: $hidesWeekends)
    }
}

struct ProfileMenuRow: View {
    @Environment(\.leafyLanguage) private var language
    let icon: String
    let title: String
    let detail: String
    var tint: Color = AppTheme.accent
    var showsDisclosure = false

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            LeafyCompactProfileIconBadge(systemName: icon, tint: tint, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.text(title, language: language))
                    .leafyBody()
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(L10n.text(detail, language: language))
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsDisclosure { LeafyDisclosureIndicator() }
        }
        .padding(.vertical, 1)
    }
}

private struct ProfileHideWeekendsRow: View {
    @Environment(\.leafyLanguage) private var language
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                LeafyCompactProfileIconBadge(systemName: "calendar.badge.minus", size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("隐藏周末", language: language))
                        .leafyBody()
                        .foregroundStyle(AppTheme.primaryText)
                    Text(L10n.text("课表页仅显示周一至周五", language: language))
                        .microCaption()
                        .foregroundStyle(AppTheme.tertiaryText)
                }
            }
        }
        .tint(AppTheme.accent)
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
