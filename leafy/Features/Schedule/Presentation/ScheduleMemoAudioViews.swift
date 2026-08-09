import SwiftData
import SwiftUI

struct ScheduleMemoAudioRecorderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var recorder = ScheduleMemoAudioRecorder()
    @State private var note = ""
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.page) {
                Spacer(minLength: AppSpacing.card)

                Image(systemName: recorder.isRecording ? "waveform" : "mic.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(recorder.isRecording ? AppTheme.danger : AppTheme.accentEmphasis)
                    .symbolEffect(.variableColor.iterative, isActive: recorder.isRecording)
                    .frame(width: 92, height: 92)
                    .background(AppTheme.softFill, in: Circle())

                Text(ScheduleMemoAudioTimeFormatter.string(recorder.elapsed))
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .monospacedDigit()

                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)

                if recorder.state == .ready {
                    TextField("添加一句备注（可选）", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 52)
                        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                controls
                Spacer(minLength: AppSpacing.card)
            }
            .padding(.horizontal, AppSpacing.page)
            .background(LeafyPageBackground())
            .navigationTitle("录音随记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                if recorder.canSave {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存", action: save)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .alert("无法保存录音", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("知道了") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .onDisappear {
            recorder.discard()
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch recorder.state {
        case .idle, .failed:
            Button {
                Task { await recorder.start() }
            } label: {
                Label("开始录音", systemImage: "record.circle")
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.danger)
        case .requestingPermission:
            ProgressView("正在准备麦克风…")
                .frame(minHeight: 48)
        case .recording:
            Button {
                recorder.stop()
            } label: {
                Label("停止录音", systemImage: "stop.circle.fill")
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.danger)
        case .ready:
            Button {
                Task { await recorder.start() }
            } label: {
                Label("重新录制", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.bordered)
        }
    }

    private var statusText: String {
        switch recorder.state {
        case .idle:
            return "最长可录制 10 分钟，录音仅保存在本机。"
        case .requestingPermission:
            return "正在请求录音权限"
        case .recording:
            return "正在录音，达到 10 分钟会自动停止"
        case .ready:
            return "录音已完成，可以添加备注后保存"
        case .failed(let message):
            return message
        }
    }

    private func save() {
        guard recorder.canSave, let sourceURL = recorder.recordingURL else { return }
        var storedFilename: String?
        do {
            let filename = try ScheduleMemoAudioStore.importRecording(from: sourceURL)
            storedFilename = filename
            let memo = ScheduleMemo(body: note, kind: .audio)
            modelContext.insert(memo)
            modelContext.insert(ScheduleMemoAudio(
                memoID: memo.id,
                localFilename: filename,
                duration: recorder.elapsed
            ))
            try modelContext.save()
            dismiss()
        } catch {
            if let storedFilename {
                try? ScheduleMemoAudioStore.deleteFile(named: storedFilename)
            }
            modelContext.rollback()
            saveError = error.localizedDescription
        }
    }
}

struct ScheduleMemoAudioPlayerBar: View {
    let audio: ScheduleMemoAudio
    @ObservedObject var controller: ScheduleMemoAudioPlaybackController

    private var isCurrent: Bool { controller.currentAudioID == audio.id }
    private var elapsed: TimeInterval { isCurrent ? controller.elapsed : 0 }
    private var duration: TimeInterval { max(isCurrent ? controller.duration : 0, audio.duration) }

    var body: some View {
        HStack(spacing: AppSpacing.compact) {
            Button {
                controller.toggle(audio)
            } label: {
                Image(systemName: isCurrent && controller.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(AppTheme.cardBackground, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCurrent && controller.isPlaying ? "暂停录音" : "播放录音")

            VStack(spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .foregroundStyle(AppTheme.accentEmphasis)
                    ProgressView(value: min(max(elapsed / max(duration, 0.01), 0), 1))
                        .tint(AppTheme.accentEmphasis)
                }
                HStack {
                    Text(ScheduleMemoAudioTimeFormatter.string(elapsed))
                    Spacer()
                    Text(ScheduleMemoAudioTimeFormatter.string(duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppTheme.cardBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

enum ScheduleMemoAudioTimeFormatter {
    static func string(_ interval: TimeInterval) -> String {
        let seconds = max(Int(interval.rounded(.down)), 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
