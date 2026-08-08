import AVFoundation
import Combine
import OSLog
import Speech

private actor ScheduleMemoAudioSessionController {
    func activate() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true)
    }

    func deactivate() throws {
        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

@MainActor
final class ScheduleMemoSpeechRecognizer: ObservableObject {
    enum State: Equatable {
        case idle
        case requestingPermission
        case listening
        case unavailable(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript = ""

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let audioEngine = AVAudioEngine()
    private let audioSessionController = ScheduleMemoAudioSessionController()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var activeSessionID: UUID?

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.isaachuo.leafy",
        category: "ScheduleMemoSpeech"
    )

    var isListening: Bool { state == .listening }

    func toggle() async {
        if isListening { await stop() } else { await start() }
    }

    func start() async {
        await stop(resetState: false)
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            state = .unavailable("当前设备不支持离线语音转写，请继续使用文字或图片记录。")
            return
        }

        state = .requestingPermission
        guard await requestSpeechAuthorization() == .authorized else {
            state = .unavailable("未获得语音识别权限，可在系统设置中允许后重试。")
            return
        }
        guard await requestMicrophonePermission() else {
            state = .unavailable("未获得麦克风权限，可在系统设置中允许后重试。")
            return
        }

        do {
            try await audioSessionController.activate()

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true
            self.request = request
            transcript = ""

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak request] buffer, _ in
                request?.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()

            let sessionID = UUID()
            activeSessionID = sessionID
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.activeSessionID == sessionID else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                        if result.isFinal { await self.stop() }
                    } else if error != nil {
                        await self.stop(resetState: false)
                        self.state = .unavailable("语音转写中断，请稍后重试。")
                    }
                }
            }
            state = .listening
        } catch {
            await stop(resetState: false)
            state = .unavailable("无法启动麦克风，请检查设备音频状态后重试。")
        }
    }

    func stop(resetState: Bool = true) async {
        activeSessionID = nil
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        if resetState { state = .idle }
        do {
            try await audioSessionController.deactivate()
        } catch {
            Self.logger.error(
                "Audio session deactivation failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func clearMessage() {
        if case .unavailable = state { state = .idle }
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission {
                continuation.resume(returning: $0)
            }
        }
    }

    deinit {
        if audioEngine.isRunning { audioEngine.stop() }
        task?.cancel()
    }
}
