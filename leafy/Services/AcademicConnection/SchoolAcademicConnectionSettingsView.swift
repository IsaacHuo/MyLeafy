import SwiftUI

struct SchoolAcademicConnectionSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = SchoolVPNSettingsStore.shared
    let identity: CampusIdentity?
    @State private var account = ""
    @State private var password = ""
    @State private var remember = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("当前方式", value: settings.isEnabled(for: identity) ? "北林 VPN 同步" : "校园网直连")
            } footer: {
                Text("配置 VPN 后，点击同步或下拉刷新即可在非校园网环境下更新课表。每次操作结束后断开连接。")
            }
            Section {
                TextField("VPN 账号", text: $account)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("VPN 密码", text: $password)
                    .textContentType(.password)
                Toggle("在此 iPhone 安全保存凭据", isOn: $remember)
                Button("保存并使用 VPN") { save() }
                    .disabled(account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
            } header: {
                Text("北林 VPN 同步 · 推荐")
            } footer: {
                Text("填写学校 VPN 账号和密码，可能与教务密码不同。保存的凭据仅存于此设备的钥匙串；不保存时仅供下一次操作使用。连接器通过 HTTPS 接收本次凭据，不写入数据库或日志。")
            }
            Section {
                Text("校园网直连")
                Text("手动连接校园网后，使用手机自身的教务会话刷新。VPN 不可用时，可在刷新失败提示中选择本次直连。其他教务功能仍使用校园网直连。")
                    .foregroundStyle(.secondary)
                if settings.isEnabled(for: identity) {
                    Button("移除 VPN 配置", role: .destructive) {
                        do {
                            SchoolTimetableConnection.shared.cancel()
                            try settings.remove(for: identity)
                            password = ""
                            message = "已移除 VPN 配置，后续使用校园网直连。"
                        } catch { message = error.localizedDescription }
                    }
                }
            }
            if let message { Section { Text(message).accessibilityIdentifier("academicConnectionMessage") } }
            if let warning = settings.storageWarning { Section { Text(warning).foregroundStyle(.red) } }
        }
        .navigationTitle("教务连接")
        .leafyInlineNavigationTitle()
        .task { load() }
        .onDisappear { password = "" }
    }

    private func load() {
        do {
            if let credential = try settings
                .credential(for: identity) { account = credential.account; password = credential.password }
            remember = try settings.rememberChoice(for: identity)
        } catch { message = error.localizedDescription }
    }

    private func save() {
        guard identity?.scopeKey == ActiveCampusContext.identity?.scopeKey else {
            message = "当前账号已变化，请重新打开教务连接设置。"
            return
        }
        do {
            SchoolTimetableConnection.shared.cancel()
            try settings.configure(
                SchoolVPNCredential(account: account, password: password),
                remember: remember,
                identity: identity
            )
            password = ""
            dismiss()
        } catch { message = error.localizedDescription }
    }
}
