import AVFoundation
import Combine
import Foundation

@MainActor
final class ScheduleMemoAudioRecorder: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case requestingPermission
        case recording
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var level: Float = -60

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private(set) var recordingURL: URL?

    var isRecording: Bool { state == .recording }
    var canSave: Bool { state == .ready && recordingURL != nil && elapsed > 0 }

    func start() async {
        discard()
        state = .requestingPermission
        guard await requestPermission() else {
            state = .failed("未获得麦克风权限，可在系统设置中允许后重试。")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default, options: [.duckOthers])
            try session.setActive(true)

            let url = ScheduleMemoAudioStore.temporaryRecordingURL()
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            self.recorder = recorder
            recordingURL = url
            guard recorder.prepareToRecord(), recorder.record() else {
                throw ScheduleMemoAudioStoreError.saveFailed
            }

            elapsed = 0
            level = -60
            state = .recording
            startTimer()
        } catch {
            if let recordingURL {
                try? FileManager.default.removeItem(at: recordingURL)
            }
            recorder = nil
            recordingURL = nil
            deactivateAudioSession()
            state = .failed("无法开始录音，请检查设备音频状态后重试。")
        }
    }

    func stop() {
        guard isRecording else { return }
        recorder?.stop()
        updateMeter()
        timer?.invalidate()
        timer = nil
        state = elapsed > 0 ? .ready : .failed("没有录到有效音频，请重新录制。")
        deactivateAudioSession()
    }

    func discard() {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        recordingURL = nil
        elapsed = 0
        level = -60
        state = .idle
        deactivateAudioSession()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            timeInterval: 0.1,
            target: self,
            selector: #selector(handleTimer),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func handleTimer() {
        updateMeter()
        if elapsed >= ScheduleMemoAudioStore.maximumDuration {
            stop()
        }
    }

    private func updateMeter() {
        guard let recorder else { return }
        elapsed = min(recorder.currentTime, ScheduleMemoAudioStore.maximumDuration)
        recorder.updateMeters()
        level = recorder.averagePower(forChannel: 0)
    }

    private func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission {
                continuation.resume(returning: $0)
            }
        }
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

@MainActor
final class ScheduleMemoAudioPlaybackController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var currentAudioID: UUID?
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func toggle(_ audio: ScheduleMemoAudio) {
        if currentAudioID == audio.id, let player {
            if player.isPlaying {
                player.pause()
                isPlaying = false
                stopTimer()
            } else {
                player.play()
                isPlaying = true
                startTimer()
            }
            return
        }

        stop()
        guard let url = ScheduleMemoAudioStore.fileURL(named: audio.localFilename) else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            self.player = player
            currentAudioID = audio.id
            duration = max(player.duration, audio.duration)
            elapsed = 0
            player.play()
            isPlaying = true
            startTimer()
        } catch {
            stop()
        }
    }

    func stop() {
        player?.stop()
        player = nil
        stopTimer()
        currentAudioID = nil
        isPlaying = false
        elapsed = 0
        duration = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.stop()
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(
            timeInterval: 0.1,
            target: self,
            selector: #selector(handleTimer),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func handleTimer() {
        guard let player else { return }
        elapsed = player.currentTime
        isPlaying = player.isPlaying
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
