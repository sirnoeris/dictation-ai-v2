import AppKit
import SwiftUI

// MARK: - DraggableHostingView
// Subclass NSHostingView so mouseDown on non-interactive SwiftUI areas
// initiates a window drag via NSWindow.performDrag(with:).
// Interactive SwiftUI elements (buttons) still consume their own events.

private final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    weak var dragDelegate: PillWindowController?

    override func mouseDown(with event: NSEvent) {
        // Let SwiftUI handle the event first (buttons, gestures, etc.)
        super.mouseDown(with: event)
        // If SwiftUI didn't consume the mouseDown (no interactive element was hit),
        // the call returns quickly. Either way, offer the drag to the window.
        // NSWindow.performDrag only starts if the cursor is actually moving.
        window?.performDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        // Save pill position after any drag completes
        dragDelegate?.savePosition()
    }
}

// MARK: - PillWindowController
// Manages a non-activating NSPanel that floats above all windows.
// The panel hosts the SwiftUI PillView via DraggableHostingView.

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
        panel.animationBehavior             = .utilityWindow
        // isMovableByWindowBackground = false because we use DraggableHostingView
        // which calls performDrag(with:) for proper position saving.
        panel.isMovableByWindowBackground   = false

        let pillView = PillView(
            appState: appState,
            settings: settings,
            onSettingsTap: {
                // self not needed here — post to NotificationCenter directly
                NotificationCenter.default.post(name: .openSettings, object: nil)
            }
        )

        let hosting = DraggableHostingView(rootView: pillView)
        hosting.wantsLayer    = true
        hosting.dragDelegate  = self
        panel.contentView     = hosting

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
