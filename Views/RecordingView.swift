import SwiftUI

struct RecordingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var audioService = AudioService()
    @State private var isRecording = false
    @State private var isSaving = false
    @State private var pulseAnimation = false

    /// If true, parent will dismiss by setting the binding; don't call dismiss() after onSave.
    var dismissAfterSave: Bool = false
    var onSave: ((_ recording: (fileName: String, duration: TimeInterval)) -> Void)

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                header
                Spacer()
                timerDisplay
                Spacer()
                waveformArea
                Spacer()
                controlButton
                bottomSpacer
            }
        }
        .preferredColorScheme(.light)
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: isRecording)
        .statusBarHidden(isRecording)
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            AppTheme.surfaceRaised
                .ignoresSafeArea()

            if isRecording {
                RadialGradient(
                    colors: [
                        Color.red.opacity(0.06),
                        Color.clear,
                    ],
                    center: .center,
                    startRadius: 50,
                    endRadius: 400
                )
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                if isRecording {
                    audioService.cancelRecording()
                }
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()

            if isRecording {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                        .opacity(audioService.isPaused ? 0.5 : (pulseAnimation ? 0.3 : 1.0))
                        .animation(
                            audioService.isPaused ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                            value: pulseAnimation
                        )
                        .onAppear { pulseAnimation = true }
                        .onDisappear { pulseAnimation = false }

                    Text(audioService.isPaused ? "Paused" : "Recording")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .transition(.opacity.combined(with: .blurReplace))
            }

            Spacer()

            if isRecording {
                Button("Done") {
                    guard !isSaving else { return }
                    isSaving = true
                    let result = audioService.stopRecording()
                    isRecording = false
                    onSave(result)
                    if !dismissAfterSave {
                        dismiss()
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .disabled(isSaving)
            } else {
                Color.clear.frame(width: 28, height: 28)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Timer

    private var timerDisplay: some View {
        Text(formatTime(audioService.recordingTime))
            .font(.system(size: 72, weight: .ultraLight, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(isRecording ? AppTheme.textPrimary : AppTheme.textTertiary)
            .contentTransition(.numericText())
            .animation(.linear(duration: 0.08), value: audioService.recordingTime)
    }

    // MARK: - Waveform

    private var waveformArea: some View {
        Group {
            if isRecording {
                WaveformView(
                    meterLevel: audioService.meterLevel,
                    isRecording: true
                )
                .padding(.horizontal, 32)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "mic.circle")
                        .font(.system(size: 48))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(AppTheme.textTertiary)

                    Text("Tap to start recording")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .frame(height: 80)
                .transition(.opacity)
            }
        }
    }

    // MARK: - Control Button

    private var controlButton: some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()

            if isRecording {
                if audioService.isPaused {
                    audioService.resumeRecording()
                } else {
                    audioService.pauseRecording()
                }
            } else {
                audioService.startRecording()
                isRecording = true
            }
        } label: {
            ZStack {
                if isRecording, !audioService.isPaused {
                    pulseRings
                }

                Circle()
                    .fill(
                        (isRecording ? Color.red : Color.accentColor).opacity(0.12)
                    )
                    .frame(width: 96, height: 96)

                Circle()
                    .fill(isRecording ? Color.red : Color.accentColor)
                    .frame(width: 76, height: 76)
                    .shadow(
                        color: (isRecording ? Color.red : Color.accentColor).opacity(0.3),
                        radius: 12, y: 4
                    )
                    .overlay {
                        Group {
                            if isRecording {
                                Image(systemName: audioService.isPaused ? "play.fill" : "pause.fill")
                                    .font(.system(size: 28, weight: .medium))
                                    .foregroundStyle(.white)
                            } else {
                                Circle()
                                    .fill(.white)
                                    .frame(width: 30, height: 30)
                            }
                        }
                        .contentTransition(.symbolEffect(.replace))
                    }
            }
        }
        .buttonStyle(.plain)
    }

    private var pulseRings: some View {
        ZStack {
            ForEach(0 ..< 2, id: \.self) { i in
                Circle()
                    .stroke(Color.red.opacity(0.15), lineWidth: 1.5)
                    .frame(width: 96, height: 96)
                    .scaleEffect(pulseAnimation ? 2.2 : 1.0)
                    .opacity(pulseAnimation ? 0 : 0.6)
                    .animation(
                        .easeOut(duration: 2.0)
                            .repeatForever(autoreverses: false)
                            .delay(Double(i) * 0.6),
                        value: pulseAnimation
                    )
            }
        }
    }

    private var bottomSpacer: some View {
        Spacer().frame(height: 72)
    }

    // MARK: - Formatting

    private func formatTime(_ time: TimeInterval) -> String {
        let m = Int(time) / 60
        let s = Int(time) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
