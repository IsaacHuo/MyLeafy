import AVFAudio
import AVFoundation
import CoreLocation
import EventKit
import Photos
import Speech
import SwiftUI
import UserNotifications

struct SystemPermissionsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference
    @State private var statuses = Dictionary(uniqueKeysWithValues: SystemPermission.allCases.map { ($0, SystemPermissionStatus.notDetermined) })
    @State private var locationRequester = LocationPermissionRequester()

    var body: some View {
        List {
            Section {
                ForEach(SystemPermission.allCases) { permission in
                    permissionRow(permission)
                }
            } footer: {
                Text("权限仅会在你使用对应功能或在此页面主动开启时请求。已关闭的权限需要在系统设置中重新开启。")
            }
        }
        .leafyInsetGroupedListStyle()
        .scrollContentBackground(.hidden)
        .background(LeafyPageBackground())
        .tint(AppTheme.accent(for: themeColorPreference))
        .navigationTitle("权限管理")
        .leafyInlineNavigationTitle()
        .task { await refreshStatuses() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshStatuses() }
        }
    }

    private func permissionRow(_ permission: SystemPermission) -> some View {
        let status = statuses[permission] ?? .notDetermined

        return Toggle(isOn: permissionBinding(for: permission)) {
            HStack(alignment: .center, spacing: 12) {
                LeafyIconBadge(
                    systemName: permission.systemImage,
                    tint: AppTheme.accent(for: themeColorPreference)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(permission.title)
                        .leafyBody()
                        .foregroundStyle(AppTheme.primaryText)
                    Text(permission.detail)
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(2)
                }
            }
        }
        .tint(AppTheme.accent(for: themeColorPreference))
        .disabled(status == .unavailable)
        .padding(.vertical, 2)
    }

    private func permissionBinding(for permission: SystemPermission) -> Binding<Bool> {
        Binding(
            get: { (statuses[permission] ?? .notDetermined) == .allowed },
            set: { isEnabled in
                Task { await update(permission, isEnabled: isEnabled) }
            }
        )
    }

    @MainActor
    private func update(_ permission: SystemPermission, isEnabled: Bool) async {
        let status = await permission.status()
        guard isEnabled != (status == .allowed) else { return }

        if isEnabled {
            switch status {
            case .notDetermined:
                await permission.request(using: locationRequester)
                await refreshStatuses()
            case .denied, .restricted:
                LeafySystemSettings.openApplicationSettings()
            case .allowed, .unavailable:
                break
            }
        } else if status == .allowed {
            LeafySystemSettings.openApplicationSettings()
        }
    }

    @MainActor
    private func refreshStatuses() async {
        var updated = statuses
        for permission in SystemPermission.allCases {
            updated[permission] = await permission.status()
        }
        statuses = updated
    }
}

private enum SystemPermission: CaseIterable, Identifiable {
    case location
    case notifications
    case calendar
    case camera
    case microphone
    case speechRecognition
    case photosAddOnly

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .location: "location.fill"
        case .notifications: "bell.badge.fill"
        case .calendar: "calendar"
        case .camera: "camera.fill"
        case .microphone: "mic.fill"
        case .speechRecognition: "waveform"
        case .photosAddOnly: "photo.badge.arrow.down"
        }
    }

    var title: String {
        switch self {
        case .location: "定位"
        case .notifications: "通知"
        case .calendar: "日历"
        case .camera: "相机"
        case .microphone: "麦克风"
        case .speechRecognition: "语音识别"
        case .photosAddOnly: "添加到照片"
        }
    }

    var detail: String {
        switch self {
        case .location: "显示当前位置天气与课表出行建议"
        case .notifications: "课程提醒、日程报告与阳光长跑提醒"
        case .calendar: "导出、更新和移除已导出的课表日历事件"
        case .camera: "拍摄随记图片"
        case .microphone: "录制语音随记"
        case .speechRecognition: "在设备端转写语音随记"
        case .photosAddOnly: "保存你创建的图片和反馈图片"
        }
    }

    @MainActor
    func status() async -> SystemPermissionStatus {
        switch self {
        case .location:
            return SystemPermissionStatus(CLLocationManager().authorizationStatus)
        case .notifications:
            return SystemPermissionStatus(await UNUserNotificationCenter.current().notificationSettings().authorizationStatus)
        case .calendar:
            return SystemPermissionStatus(EKEventStore.authorizationStatus(for: .event))
        case .camera:
            return SystemPermissionStatus(AVCaptureDevice.authorizationStatus(for: .video))
        case .microphone:
            return SystemPermissionStatus(AVAudioApplication.shared.recordPermission)
        case .speechRecognition:
            return SystemPermissionStatus(SFSpeechRecognizer.authorizationStatus())
        case .photosAddOnly:
            return SystemPermissionStatus(PHPhotoLibrary.authorizationStatus(for: .addOnly))
        }
    }

    @MainActor
    func request(using locationRequester: LocationPermissionRequester) async {
        switch self {
        case .location:
            await locationRequester.requestWhenInUseAuthorization()
        case .notifications:
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        case .calendar:
            let eventStore = EKEventStore()
            _ = try? await eventStore.requestFullAccessToEvents()
        case .camera:
            _ = await AVCaptureDevice.requestAccess(for: .video)
        case .microphone:
            _ = await AVAudioApplication.requestRecordPermission()
        case .speechRecognition:
            _ = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
        case .photosAddOnly:
            _ = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    continuation.resume(returning: status)
                }
            }
        }
    }
}

private enum SystemPermissionStatus: Equatable {
    case notDetermined
    case allowed
    case denied
    case restricted
    case unavailable

    init(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .authorizedWhenInUse, .authorizedAlways: self = .allowed
        case .denied: self = .denied
        case .restricted: self = .restricted
        @unknown default: self = .unavailable
        }
    }

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .authorized, .provisional, .ephemeral: self = .allowed
        case .denied: self = .denied
        @unknown default: self = .unavailable
        }
    }

    init(_ status: EKAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .fullAccess, .authorized: self = .allowed
        case .denied: self = .denied
        case .restricted, .writeOnly: self = .restricted
        @unknown default: self = .unavailable
        }
    }

    init(_ status: AVAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .authorized: self = .allowed
        case .denied: self = .denied
        case .restricted: self = .restricted
        @unknown default: self = .unavailable
        }
    }

    init(_ status: AVAudioApplication.recordPermission) {
        switch status {
        case .undetermined: self = .notDetermined
        case .granted: self = .allowed
        case .denied: self = .denied
        @unknown default: self = .unavailable
        }
    }

    init(_ status: SFSpeechRecognizerAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .authorized: self = .allowed
        case .denied: self = .denied
        case .restricted: self = .restricted
        @unknown default: self = .unavailable
        }
    }

    init(_ status: PHAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .authorized, .limited: self = .allowed
        case .denied: self = .denied
        case .restricted: self = .restricted
        @unknown default: self = .unavailable
        }
    }

}

@MainActor
private final class LocationPermissionRequester: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var continuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func requestWhenInUseAuthorization() async {
        guard locationManager.authorizationStatus == .notDetermined else { return }

        await withCheckedContinuation { continuation in
            self.continuation = continuation
            locationManager.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume()
    }
}
