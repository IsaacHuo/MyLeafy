import AVFoundation
import Combine
import QuickLook
import SwiftUI
import UIKit

struct ScheduleMemoCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = ScheduleMemoCameraController()

    let onCapture: (UIImage) -> Void

    var body: some View {
        cameraContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear(perform: camera.start)
            .onDisappear(perform: camera.stop)
            .alert("无法拍照", isPresented: Binding(
                get: { camera.captureErrorMessage != nil },
                set: { if !$0 { camera.captureErrorMessage = nil } }
            )) {
                Button("好") { camera.captureErrorMessage = nil }
            } message: {
                Text(camera.captureErrorMessage ?? "")
            }
    }

    @ViewBuilder
    private var cameraContent: some View {
        switch camera.state {
        case .denied:
            unavailableContent(
                title: "未开启相机权限",
                message: "请在系统设置中允许 MyLeafy 使用相机。",
                showsSettingsButton: true
            )
        case .unavailable(let message):
            unavailableContent(title: "无法使用相机", message: message, showsSettingsButton: false)
        case .loading, .ready:
            ZStack {
                Color.black
                    .ignoresSafeArea()

                ScheduleMemoCameraPreview(session: camera.session)
                    .ignoresSafeArea()

                ProgressView()
                    .tint(.white)
                    .controlSize(.large)
                    .opacity(camera.state == .loading ? 1 : 0)
                    .animation(.easeOut(duration: 0.15), value: camera.state)

                cameraControls
            }
        }
    }

    private var cameraControls: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                cameraControlButton(
                    systemName: camera.isFlashEnabled ? "bolt.fill" : "bolt.slash.fill",
                    accessibilityLabel: camera.isFlashEnabled ? "关闭闪光灯" : "开启闪光灯",
                    isDisabled: !camera.isFlashAvailable,
                    action: camera.toggleFlash
                )
            }

            Spacer()

            HStack {
                cameraControlButton(
                    systemName: "xmark",
                    accessibilityLabel: "关闭相机",
                    action: dismiss.callAsFunction
                )

                Spacer()

                Button {
                    camera.capture { image in
                        onCapture(image)
                        dismiss()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.9), lineWidth: 5)
                            .frame(width: 72, height: 72)
                        Circle()
                            .fill(.white)
                            .frame(width: 58, height: 58)
                    }
                    .frame(width: 76, height: 76)
                }
                .buttonStyle(.plain)
                .disabled(camera.state != .ready || camera.isCapturing)
                .opacity(camera.isCapturing ? 0.55 : 1)
                .accessibilityLabel("拍照")

                Spacer()

                cameraControlButton(
                    systemName: "arrow.triangle.2.circlepath.camera",
                    accessibilityLabel: "切换前后镜头",
                    isDisabled: !camera.canSwitchCamera,
                    action: camera.switchCamera
                )
            }
        }
        .padding(18)
    }

    private func cameraControlButton(
        systemName: String,
        accessibilityLabel: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .leafyGlassSurface(
            in: Circle(),
            tint: .black.opacity(0.24),
            fallbackFill: .black.opacity(0.46),
            isInteractive: true
        )
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.38 : 1)
        .accessibilityLabel(accessibilityLabel)
    }

    private func unavailableContent(
        title: String,
        message: String,
        showsSettingsButton: Bool
    ) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "camera.fill")
                .font(.system(size: 36, weight: .medium))
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.72))

            if showsSettingsButton {
                Button("前往设置") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .buttonStyle(.borderedProminent)
            }

            Button("关闭", action: dismiss.callAsFunction)
                .buttonStyle(.bordered)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .padding(28)
        .background(.black)
    }
}

private final class ScheduleMemoCameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    enum CameraState: Equatable {
        case loading
        case ready
        case denied
        case unavailable(String)
    }

    let session = AVCaptureSession()

    @Published private(set) var state: CameraState = .loading
    @Published private(set) var isCapturing = false
    @Published private(set) var isFlashAvailable = false
    @Published private(set) var isFlashEnabled = false
    @Published private(set) var canSwitchCamera = false
    @Published var captureErrorMessage: String?

    private let sessionQueue = DispatchQueue(label: "com.myleafy.schedule-memo-camera")
    private let photoOutput = AVCapturePhotoOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var currentPosition: AVCaptureDevice.Position = .back
    private var isConfigured = false
    private var captureCompletion: ((UIImage) -> Void)?

    func start() {
        state = .loading
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] isGranted in
                guard let self else { return }
                if isGranted {
                    self.configureAndStart()
                } else {
                    DispatchQueue.main.async { self.state = .denied }
                }
            }
        case .denied, .restricted:
            state = .denied
        @unknown default:
            state = .unavailable("系统未返回可识别的相机权限状态。")
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func toggleFlash() {
        guard isFlashAvailable else { return }
        isFlashEnabled.toggle()
    }

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured, let oldInput = self.currentInput else { return }
            let newPosition: AVCaptureDevice.Position = self.currentPosition == .back ? .front : .back
            guard let device = Self.cameraDevice(position: newPosition) else { return }

            do {
                let newInput = try AVCaptureDeviceInput(device: device)
                self.session.beginConfiguration()
                self.session.removeInput(oldInput)
                if self.session.canAddInput(newInput) {
                    self.session.addInput(newInput)
                    self.currentInput = newInput
                    self.currentPosition = newPosition
                } else {
                    self.session.addInput(oldInput)
                }
                self.session.commitConfiguration()
                self.publishCameraCapabilities()
            } catch {
                DispatchQueue.main.async {
                    self.captureErrorMessage = "切换镜头失败：\(error.localizedDescription)"
                }
            }
        }
    }

    func capture(onCapture: @escaping (UIImage) -> Void) {
        guard state == .ready, !isCapturing else { return }
        isCapturing = true
        let usesFlash = isFlashEnabled

        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured else {
                DispatchQueue.main.async {
                    self?.isCapturing = false
                    self?.captureErrorMessage = "相机尚未准备好，请稍后重试。"
                }
                return
            }

            let settings = AVCapturePhotoSettings()
            settings.flashMode = usesFlash && self.currentInput?.device.hasFlash == true ? .on : .off
            if let connection = self.photoOutput.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = self.currentPosition == .front
                }
            }
            self.captureCompletion = onCapture
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let data = photo.fileDataRepresentation()
        let errorDescription = error?.localizedDescription
        Task { @MainActor [weak self] in
            guard let self else { return }
            let completion = self.captureCompletion
            self.captureCompletion = nil
            self.isCapturing = false
            if let errorDescription {
                self.captureErrorMessage = "拍照失败：\(errorDescription)"
                return
            }
            guard let data, let image = UIImage(data: data) else {
                self.captureErrorMessage = "相机没有返回可用的照片。"
                return
            }
            completion?(image)
        }
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                if !self.isConfigured {
                    try self.configureSession()
                }
                guard !self.session.isRunning else {
                    DispatchQueue.main.async { self.state = .ready }
                    return
                }
                self.session.startRunning()
                DispatchQueue.main.async { self.state = .ready }
            } catch {
                DispatchQueue.main.async {
                    self.state = .unavailable(error.localizedDescription)
                }
            }
        }
    }

    private func configureSession() throws {
        guard let device = Self.cameraDevice(position: .back) else {
            throw ScheduleMemoCameraError.cameraUnavailable
        }

        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        guard session.canAddInput(input), session.canAddOutput(photoOutput) else {
            throw ScheduleMemoCameraError.configurationFailed
        }
        session.addInput(input)
        session.addOutput(photoOutput)
        currentInput = input
        currentPosition = .back
        isConfigured = true
        publishCameraCapabilities()
    }

    private func publishCameraCapabilities() {
        let supportsFlash = currentInput?.device.hasFlash == true
        let supportsSwitching = Self.cameraDevice(position: .back) != nil
            && Self.cameraDevice(position: .front) != nil
        DispatchQueue.main.async {
            self.isFlashAvailable = supportsFlash
            if !supportsFlash {
                self.isFlashEnabled = false
            }
            self.canSwitchCamera = supportsSwitching
        }
    }

    private static func cameraDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }
}

private enum ScheduleMemoCameraError: LocalizedError {
    case cameraUnavailable
    case configurationFailed

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "当前设备没有可用的相机。"
        case .configurationFailed:
            return "无法建立相机取景会话。"
        }
    }
}

private struct ScheduleMemoCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> ScheduleMemoCameraPreviewUIView {
        let view = ScheduleMemoCameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: ScheduleMemoCameraPreviewUIView, context: Context) {
        uiView.previewLayer.session = session
    }
}

private final class ScheduleMemoCameraPreviewUIView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let connection = previewLayer.connection,
              connection.isVideoRotationAngleSupported(90) else { return }
        connection.videoRotationAngle = 90
    }
}

struct ScheduleMemoDocumentPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
