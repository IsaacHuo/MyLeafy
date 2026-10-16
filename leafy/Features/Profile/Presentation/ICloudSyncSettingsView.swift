import SwiftUI

struct ICloudSyncSettingsView: View {
    @ObservedObject private var sync = ICloudSyncCoordinator.shared
    @State private var confirmsEnable = false
    @State private var confirmsDelete = false
    var body: some View {
        List {
            Section {
                Toggle("iCloud 同步", isOn: Binding(get: { sync.isEnabled }, set: { enabled in
                    if enabled { confirmsEnable = true } else { sync.setEnabled(false) }
                }))
                .disabled(ReviewDemoMode.isEnabled || sync.isBusy)
                Text("开启后，课表、成绩考试、备注提醒、个人日程、随记及附件、课表与个性化设置，会同步到当前 Apple 账号的 iCloud。不同校园身份分别保存。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("同步状态") {
                if sync.isBusy { ProgressView(sync.phase.title) }
                if let date = sync.lastSuccess { LabeledContent("最近成功", value: date.formatted(date: .abbreviated, time: .shortened)) }
                else { Text("尚未完成同步").foregroundStyle(.secondary) }
                if sync.pendingCount > 0 { Text("待同步或待接收：\(sync.pendingCount) 项") }
                if let failure = sync.failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
                if let details = sync.failureDetails {
                    DisclosureGroup("错误详情") {
                        Text(details).font(.caption.monospaced()).textSelection(.enabled)
                        ShareLink(item: details) { Label("分享诊断信息", systemImage: "square.and.arrow.up") }
                    }
                }
                Button("立即同步 / 重试") { sync.retry() }.disabled(!sync.isEnabled || sync.isBusy)
            }
            Section {
                Text("关闭同步会保留本机与云端数据。学校密码、登录会话和社区缓存不参与同步。学习资料、职业规划、医疗等其他模块本轮不参与同步。")
                    .font(.footnote).foregroundStyle(.secondary)
                if ReviewDemoMode.isEnabled { Text("演示模式不支持 iCloud 同步。") }
                Button("删除此身份云端数据", role: .destructive) { confirmsDelete = true }.disabled(sync.isBusy || ReviewDemoMode.isEnabled)
            }
        }
        .navigationTitle("iCloud 同步")
        .leafyInlineNavigationTitle()
        .confirmationDialog("开启 iCloud 同步？", isPresented: $confirmsEnable, titleVisibility: .visible) {
            Button("开启并合并数据") { sync.setEnabled(true) }
            Button("取消", role: .cancel) {}
        } message: { Text("本机数据将与当前 Apple 账号中此校园身份的数据合并。文本冲突会保留副本，附件也会上传。") }
        .confirmationDialog("删除此身份的 iCloud 数据？", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("删除云端数据并关闭同步", role: .destructive) { Task { await sync.deleteCloudData() } }
            Button("取消", role: .cancel) {}
        } message: { Text("本机数据保留，其他设备将停止同步此云端空间。重新开启同步会再次上传本机数据。") }
    }
}
