import AVFoundation
import Combine
import QuickLook
import SwiftUI
import UIKit

struct ScheduleMemoMarkdownView: View {
    let source: String

    private var blocks: [ScheduleMemoMarkdownBlock] {
        ScheduleMemoMarkdownParser.blocks(in: source)
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: ScheduleMemoMarkdownBlock) -> some View {
        switch block.kind {
        case .heading(let level):
            Text(inlineMarkdown(block.text))
                .font(headingFont(level))
                .foregroundStyle(AppTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .paragraph:
            Text(inlineMarkdown(block.text))
                .leafyBody()
                .foregroundStyle(AppTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .quote:
            HStack(alignment: .top, spacing: 10) {
                Capsule()
                    .fill(AppTheme.accent)
                    .frame(width: 3)
                Text(inlineMarkdown(block.text))
                    .leafyBody()
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .padding(.vertical, 2)
        case .unorderedList:
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("•")
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.accent)
                Text(inlineMarkdown(block.text))
                    .leafyBody()
                    .foregroundStyle(AppTheme.primaryText)
            }
        case .orderedList(let number):
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("\(number).")
                    .font(.body.monospacedDigit().weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                Text(inlineMarkdown(block.text))
                    .leafyBody()
                    .foregroundStyle(AppTheme.primaryText)
            }
        case .code:
            ScrollView(.horizontal, showsIndicators: false) {
                Text(block.text)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(AppTheme.primaryText)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.softFill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title.bold()
        case 2: return .title2.bold()
        default: return .title3.weight(.semibold)
        }
    }

    private func inlineMarkdown(_ source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
    }
}

struct ScheduleMemoWritingEditor: View {
    enum Mode: String, CaseIterable, Identifiable {
        case edit
        case preview

        var id: String { rawValue }
        var title: String { self == .edit ? "编辑" : "预览" }
    }

    @Environment(\.dismiss) private var dismiss
    let navigationTitle: String
    let onSave: (String, String) -> Void
    @State private var title: String
    @State private var source: String
    @State private var mode: Mode = .edit

    init(
        navigationTitle: String = "写文",
        title: String = "",
        source: String = "",
        onSave: @escaping (String, String) -> Void
    ) {
        self.navigationTitle = navigationTitle
        self.onSave = onSave
        _title = State(initialValue: title)
        _source = State(initialValue: source)
    }

    private var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("写文模式", selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, AppSpacing.page)
                .padding(.vertical, AppSpacing.compact)

                if mode == .edit {
                    VStack(spacing: AppSpacing.compact) {
                        TextField("标题", text: $title)
                            .font(.title2.bold())
                            .textInputAutocapitalization(.sentences)
                        Divider()
                        TextEditor(text: $source)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .overlay(alignment: .topLeading) {
                                if source.isEmpty {
                                    Text("使用 Markdown 写下正文…")
                                        .foregroundStyle(AppTheme.tertiaryText)
                                        .allowsHitTesting(false)
                                        .padding(.top, 8)
                                        .padding(.leading, 5)
                                }
                            }
                    }
                    .padding(.horizontal, AppSpacing.page)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: AppSpacing.card) {
                            Text(normalizedTitle.isEmpty ? "未命名文章" : normalizedTitle)
                                .font(.largeTitle.bold())
                                .foregroundStyle(AppTheme.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ScheduleMemoMarkdownView(source: source)
                        }
                        .padding(AppSpacing.page)
                    }
                }
            }
            .background(LeafyPageBackground())
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(normalizedTitle, source)
                        dismiss()
                    }
                    .disabled(normalizedTitle.isEmpty)
                }
            }
        }
    }
}

fileprivate struct ScheduleMemoMarkdownBlock: Identifiable {
    enum Kind {
        case heading(Int)
        case paragraph
        case quote
        case unorderedList
        case orderedList(Int)
        case code
    }

    let id = UUID()
    let kind: Kind
    let text: String
}

enum ScheduleMemoMarkdownParser {
    fileprivate static func blocks(in source: String) -> [ScheduleMemoMarkdownBlock] {
        let lines = source.components(separatedBy: .newlines)
        var result: [ScheduleMemoMarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String] = []
        var isInCodeBlock = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            result.append(.init(kind: .paragraph, text: paragraph.joined(separator: "\n")))
            paragraph.removeAll()
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if isInCodeBlock {
                    result.append(.init(kind: .code, text: code.joined(separator: "\n")))
                    code.removeAll()
                } else {
                    flushParagraph()
                }
                isInCodeBlock.toggle()
                continue
            }

            if isInCodeBlock {
                code.append(line)
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if let heading = heading(in: trimmed) {
                flushParagraph()
                result.append(.init(kind: .heading(heading.level), text: heading.text))
            } else if trimmed.hasPrefix(">") {
                flushParagraph()
                result.append(.init(kind: .quote, text: String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                flushParagraph()
                result.append(.init(kind: .unorderedList, text: String(trimmed.dropFirst(2))))
            } else if let ordered = orderedListItem(in: trimmed) {
                flushParagraph()
                result.append(.init(kind: .orderedList(ordered.number), text: ordered.text))
            } else {
                paragraph.append(line)
            }
        }

        if isInCodeBlock, !code.isEmpty {
            result.append(.init(kind: .code, text: code.joined(separator: "\n")))
        }
        flushParagraph()
        return result
    }

    static func plainText(from source: String) -> String {
        blocks(in: source).map(\.text).joined(separator: " ")
            .replacingOccurrences(of: #"[*_`]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]+\)"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func heading(in line: String) -> (level: Int, text: String)? {
        let count = line.prefix(while: { $0 == "#" }).count
        guard (1...3).contains(count), line.dropFirst(count).first == " " else { return nil }
        return (count, String(line.dropFirst(count + 1)))
    }

    private static func orderedListItem(in line: String) -> (number: Int, text: String)? {
        guard let dot = line.firstIndex(of: "."),
              let number = Int(line[..<dot]),
              line.index(after: dot) < line.endIndex,
              line[line.index(after: dot)] == " " else { return nil }
        return (number, String(line[line.index(dot, offsetBy: 2)...]))
    }
}

struct ScheduleMemoCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = ScheduleMemoCameraController()

    let onCapture: (UIImage) -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            cameraContent
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .padding(12)
        }
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
                ScheduleMemoCameraPreview(session: camera.session)
                    .ignoresSafeArea()

                if camera.state == .loading {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.large)
                }

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
