import SwiftUI

struct AudioPlayerView: View {
    let audioURL: URL
    let duration: TimeInterval
    @Bindable var audioService: AudioService

    var body: some View {
        VStack(spacing: 14) {
            StaticWaveformView(
                progress: duration > 0
                    ? audioService.currentPlaybackTime / duration
                    : 0
            )

            HStack {
                Text(formatTime(audioService.isPlaying ? audioService.currentPlaybackTime : 0))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.textSecondary)

                Spacer()

                Button {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    audioService.togglePlayback(url: audioURL)
                } label: {
                    Image(systemName: audioService.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(AppTheme.accent)
                        .contentTransition(.symbolEffect(.replace))
                }

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    audioService.cyclePlaybackSpeed()
                } label: {
                    Text(audioService.playbackRate >= 1.75 ? "2×" : "1×")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(AppTheme.accent)
                        .frame(minWidth: 28)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(AppTheme.accent.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)

                Text(formatTime(duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let m = Int(time) / 60
        let s = Int(time) % 60
        return String(format: "%d:%02d", m, s)
    }
}
