import AppKit
import SwiftUI

// MARK: - SettingsWindowController

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
    }

    func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(settings: settings)
        let hosting = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hosting)
        window.title                   = "Dictation AI — Settings"
        window.styleMask               = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed    = false
        window.delegate                = self
        window.setContentSize(NSSize(width: 520, height: 620))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        // Re-arm key monitor with latest settings after settings window closes
        KeyMonitor.shared.updateMode(settings.recordingMode, keyCode: settings.holdKeyCode)
    }
}
