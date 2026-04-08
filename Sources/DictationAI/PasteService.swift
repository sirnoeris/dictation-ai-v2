import AppKit
import ApplicationServices

// MARK: - PasteService
// Writes text to the clipboard and simulates Cmd+V in the previously-focused app.

@MainActor
final class PasteService {

    static let shared = PasteService()
    private init() {}

    private var prevFrontAppName: String?

    // MARK: - Capture Front App

    /// Call this BEFORE showing the pill so we remember where to paste.
    func captureFrontApp() {
        prevFrontAppName = NSWorkspace.shared.frontmostApplication?.localizedName
    }

    // MARK: - Paste

    func paste(_ text: String) async {
        let previous = NSPasteboard.general.string(forType: .string)

        // Write to clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        guard checkAccessibility() else {
            requestAccessibilityIfNeeded()
            return
        }

        // Re-activate the app that was in front when recording started
        if let appName = prevFrontAppName,
           let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }) {
            app.activate(options: [])
            try? await Task.sleep(nanoseconds: 80_000_000) // 80 ms
        }

        // Simulate Cmd+V via CGEvent
        simulateCmdV()

        // Restore previous clipboard after 3 s
        let prev = previous ?? ""
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            NSPasteboard.general.clearContents()
            if !prev.isEmpty {
                NSPasteboard.general.setString(prev, forType: .string)
            }
        }
    }

    // MARK: - CGEvent Cmd+V

    private func simulateCmdV() {
        let src = CGEventSource(stateID: .hidSystemState)
        // V = keycode 9
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true),
              let up   = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        else { return }

        down.flags = .maskCommand
        up.flags   = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    // MARK: - Accessibility

    func checkAccessibility() -> Bool {
        AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt: false] as CFDictionary
        )
    }

    func requestAccessibilityIfNeeded() {
        guard !checkAccessibility() else { return }

        let alert = NSAlert()
        alert.messageText     = "Accessibility Access Required"
        alert.informativeText = """
            Dictation AI needs Accessibility access to auto-paste text at your cursor.

            1. Open System Settings → Privacy & Security → Accessibility
            2. Add Dictation AI and enable it.

            Your text has been copied to the clipboard — press ⌘V to paste manually.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            )
        }
    }
}
