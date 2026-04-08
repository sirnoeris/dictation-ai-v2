import SwiftUI

// MARK: - WaveformView
// Animated 5-bar equaliser that bounces to real-time audio level.

struct WaveformView: View {

    let barLevels: [Float]  // 5 values, each 0–1
    var color: Color = .white
    var barWidth: CGFloat  = 3
    var spacing:  CGFloat  = 3
    var maxHeight: CGFloat = 22

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(0..<5) { i in
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(color.opacity(0.85))
                    .frame(
                        width:  barWidth,
                        height: max(3, CGFloat(barLevels[safe: i] ?? 0) * maxHeight)
                    )
                    .animation(
                        .spring(response: 0.15, dampingFraction: 0.6),
                        value: barLevels[safe: i] ?? 0
                    )
            }
        }
        .frame(height: maxHeight)
    }
}

// MARK: - Idle pulse bars (for when recording hasn't started yet)

struct PulsingDotsView: View {
    @State private var phase = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: 5, height: 5)
                    .scaleEffect(phase ? 1 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever()
                            .delay(Double(i) * 0.18),
                        value: phase
                    )
            }
        }
        .onAppear { phase = true }
    }
}

// MARK: - Array safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black
        WaveformView(barLevels: [0.4, 0.8, 0.6, 0.9, 0.3])
            .padding()
    }
    .frame(width: 100, height: 60)
}
