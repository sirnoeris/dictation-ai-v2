import SwiftUI

// MARK: - PillView
// The floating translucent pill overlay. Adapts its content to the current
// recording state: idle → recording → processing → done → error.

struct PillView: View {

    @ObservedObject var appState: AppState
    @ObservedObject var settings: AppSettings

    var onSettingsTap: (() -> Void)?
    var onDragChanged: ((CGPoint) -> Void)?

    // Internal drag state
    @State private var dragOffset: CGSize = .zero
    @State private var localBarLevels: [Float] = [0.1, 0.15, 0.1, 0.12, 0.08]
    @State private var idleBarTimer: Timer?

    var body: some View {
        pillContent
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { v in
                        onDragChanged?(CGPoint(x: v.location.x, y: v.location.y))
                    }
            )
            .onAppear { startIdleAnimation() }
            .onDisappear { stopIdleAnimation() }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var pillContent: some View {
        ZStack {
            // Background: dark frosted glass
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 6)

            HStack(spacing: 10) {
                stateIcon
                stateLabel
                Spacer(minLength: 0)
                settingsButton
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .frame(width: 340, height: 52)
        .overlay(
            Capsule()
                .strokeBorder(borderColor, lineWidth: 0.5)
        )
    }

    // MARK: - State-dependent Icon

    @ViewBuilder
    private var stateIcon: some View {
        switch appState.state {

        case .idle:
            Image(systemName: "mic.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))

        case .recording:
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.2))
                    .frame(width: 28, height: 28)
                    .scaleEffect(pulseScale)
                    .animation(.easeInOut(duration: 0.9).repeatForever(), value: pulseScale)
                WaveformView(
                    barLevels: appState.barLevels,
                    color: .red,
                    barWidth: 2.5,
                    spacing: 2,
                    maxHeight: 18
                )
            }
            .frame(width: 36, height: 30)

        case .processing:
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.7)
                .frame(width: 22, height: 22)
                .tint(.white)

        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color(red: 0.2, green: 0.85, blue: 0.55))
                .transition(.scale.combined(with: .opacity))

        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.orange)
        }
    }

    // MARK: - State-dependent Label

    @ViewBuilder
    private var stateLabel: some View {
        VStack(alignment: .leading, spacing: 1) {
            switch appState.state {

            case .idle:
                Text("Dictation AI")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))

            case .recording:
                Text("Listening…")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Release to transcribe")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.white.opacity(0.5))

            case .processing:
                Text("Transcribing…")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                if settings.enhancementEnabled && settings.hasXAIKey {
                    Text("then cleaning up with Grok")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                }

            case .done(let text):
                Text(text)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .transition(.move(edge: .bottom).combined(with: .opacity))

            case .error(let msg):
                Text("Failed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
                Text(msg)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange.opacity(0.8))
                    .lineLimit(1)
            }
        }
        .animation(.spring(response: 0.3), value: appState.state.label)
    }

    // MARK: - Settings Button

    private var settingsButton: some View {
        Button(action: { onSettingsTap?() }) {
            Image(systemName: "gear")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Styling

    private var borderColor: Color {
        switch appState.state {
        case .recording: return .red.opacity(0.4)
        case .done:      return Color(red: 0.2, green: 0.85, blue: 0.55).opacity(0.4)
        case .error:     return .orange.opacity(0.4)
        default:         return .white.opacity(0.12)
        }
    }

    @State private var pulseScale: CGFloat = 1.0

    // MARK: - Idle bar animation (gentle low-amplitude movement when idle)

    private func startIdleAnimation() {
        idleBarTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            // Subtle random movement for idle state
        }
    }

    private func stopIdleAnimation() {
        idleBarTimer?.invalidate()
        idleBarTimer = nil
    }
}

// MARK: - NSVisualEffectView bridge

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material     = material
        v.blendingMode = blendingMode
        v.state        = .active
        v.isEmphasized = false
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material     = material
        nsView.blendingMode = blendingMode
    }
}
