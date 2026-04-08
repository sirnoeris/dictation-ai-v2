import AppKit
import SwiftUI

// MARK: - PillWindowController
// Manages a non-activating NSPanel that floats above all windows.
// The panel hosts the SwiftUI PillView via NSHostingView.

@MainActor
final class PillWindowController {

    private var panel: NSPanel?
    private let appState: AppState
    private let settings: AppSettings

    // Track drag position
    private var isDragging = false

    init(appState: AppState, settings: AppSettings) {
        self.appState = appState
        self.settings = settings
        buildPanel()
    }

    // MARK: - Build

    private func buildPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 52),
            styleMask:   [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing:     .buffered,
            defer:       false
        )
        panel.isFloatingPanel         = true
        panel.level                   = .floating
        panel.isOpaque                = false
        panel.backgroundColor         = .clear
        panel.hasShadow               = true
        panel.hidesOnDeactivate       = false
        panel.becomesKeyOnlyIfNeeded  = true
        panel.collectionBehavior      = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior       = .utilityWindow
        panel.isMovableByWindowBackground = false

        let pillView = PillView(
            appState: appState,
            settings: settings,
            onSettingsTap: { [weak self] in
                NotificationCenter.default.post(name: .openSettings, object: nil)
            },
            onDragChanged: { [weak self] _ in
                // Dragging handled by NSWindow's built-in move
            }
        )

        let hosting = NSHostingView(rootView: pillView)
        hosting.wantsLayer = true
        panel.contentView  = hosting

        // Make the pill draggable
        hosting.allowedTouchTypes = []

        self.panel = panel
        position(at: CGPoint(x: settings.pillX, y: settings.pillY))
    }

    // MARK: - Show / Hide

    func show() {
        guard let panel else { return }
        position(at: CGPoint(x: settings.pillX, y: settings.pillY))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            panel.alphaValue = 1
        })
    }

    // MARK: - Position

    private func position(at point: CGPoint) {
        guard let panel else { return }
        guard let screen = NSScreen.main else { return }

        let frame = panel.frame
        let maxX  = screen.visibleFrame.maxX - frame.width
        let minX  = screen.visibleFrame.minX
        let maxY  = screen.visibleFrame.maxY - frame.height
        let minY  = screen.visibleFrame.minY

        let x = max(minX, min(maxX, point.x))
        let y = max(minY, min(maxY, point.y))
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Called when the user finishes dragging the pill. Saves new position.
    func savePosition() {
        guard let panel else { return }
        let origin = panel.frame.origin
        settings.pillX = origin.x
        settings.pillY = origin.y
    }
}

// MARK: - Notification name

extension Notification.Name {
    static let openSettings = Notification.Name("DictationAI.openSettings")
}
