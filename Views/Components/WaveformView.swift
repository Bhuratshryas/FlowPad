import SwiftUI

// MARK: - Live Waveform (Recording)

struct WaveformView: View {
    let meterLevel: Float
    let isRecording: Bool

    @State private var bars: [CGFloat] = Array(repeating: 0.05, count: 50)

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0 ..< bars.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.5), Color.accentColor],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 3.5, height: max(3, bars[index] * 56))
                    .animation(
                        .spring(response: 0.12, dampingFraction: 0.55),
                        value: bars[index]
                    )
            }
        }
        .frame(height: 60)
        .onChange(of: meterLevel) { _, newValue in
            guard isRecording else { return }
            withAnimation {
                bars.removeFirst()
                let jitter = CGFloat.random(in: -0.08 ... 0.08)
                bars.append(max(0.05, CGFloat(newValue) + jitter))
            }
        }
    }
}

// MARK: - Static Waveform (Playback)

struct StaticWaveformView: View {
    let progress: Double

    private let barCount = 60
    @State private var heights: [CGFloat] = []

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(0 ..< barCount, id: \.self) { index in
                    let fraction = Double(index) / Double(barCount)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(fraction <= progress ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(
                            width: max(2, (geo.size.width - CGFloat(barCount - 1) * 2) / CGFloat(barCount)),
                            height: max(3, heights.isEmpty ? 8 : heights[index] * geo.size.height)
                        )
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 36)
        .onAppear {
            if heights.isEmpty {
                heights = (0 ..< barCount).map { _ in CGFloat.random(in: 0.12 ... 1.0) }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: progress)
    }
}
