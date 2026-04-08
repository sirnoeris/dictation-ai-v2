import Cocoa
import Carbon

// MARK: - KeyMonitor
// Uses CGEventTap for hold-to-talk (Fn/Globe flagsChanged) and key-learning.
// Uses NSEvent.addGlobalMonitorForEvents for toggle mode (Ctrl+Opt+Space).
// The NSEvent monitor does NOT require Accessibility permission —
// only Input Monitoring (much easier to grant than Accessibility).

final class KeyMonitor {

    static let shared = KeyMonitor()
    private init() {}

    // Callbacks — always invoked on main queue
    var onHoldBegan: (() -> Void)?
    var onHoldEnded: (() -> Void)?
    var onToggle:    (() -> Void)?

    // Key-learning callback: (keyCode, label)
    var onKeyLearned: ((Int, String) -> Void)?
    var isLearningKey = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var toggleMonitor: Any?           // NSEvent global monitor for toggle

    private var currentMode: RecordingMode = .hold
    private var currentKeyCode: Int        = 63   // Globe/Fn default

    // Bug fix: holdActive is written on the CGEventTap thread and read/written
    // on the main thread (updateMode/removeTap). Protect with a lock.
    private let holdLock                   = NSLock()
    private var _holdActive                = false
    private var holdActive: Bool {
        get { holdLock.withLock { _holdActive } }
        set { holdLock.withLock { _holdActive = newValue } }
    }

    // MARK: - Public API

    func start(mode: RecordingMode, keyCode: Int) {
        currentMode    = mode
        currentKeyCode = keyCode
        installTap()
        installToggleMonitor()
    }

    func updateMode(_ mode: RecordingMode, keyCode: Int) {
        currentMode    = mode
        currentKeyCode = keyCode
        holdActive     = false
        installToggleMonitor()
    }

    func beginLearning() {
        isLearningKey = true
    }

    func cancelLearning() {
        isLearningKey = false
    }

    // MARK: - NSEvent Toggle Monitor (Ctrl+Option+Space)
    // NSEvent.addGlobalMonitorForEvents observes without consuming events and
    // does not require Accessibility — only Input Monitoring in System Settings.

    private func installToggleMonitor() {
        removeToggleMonitor()
        guard currentMode == .toggle else { return }

        toggleMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            // Ctrl+Option+Space: keyCode 49, exactly Control+Option (no Cmd/Shift)
            let maskedFlags = event.modifierFlags.intersection([.control, .option, .command, .shift])
            if event.keyCode == 49 && maskedFlags == [.control, .option] {
                DispatchQueue.main.async { self.onToggle?() }
            }
        }
    }

    private func removeToggleMonitor() {
        if let monitor = toggleMonitor {
            NSEvent.removeMonitor(monitor)
            toggleMonitor = nil
        }
    }

    // MARK: - Event Tap

    private func installTap() {
        guard eventTap == nil else { return }

        let eventMask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap:                .cgSessionEventTap,
            place:              .headInsertEventTap,
            options:            .defaultTap,
            eventsOfInterest:   eventMask,
            callback:           keyMonitorCallback,
            userInfo:           Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("[KeyMonitor] Failed to create CGEventTap — check Accessibility permission")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func removeTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        eventTap      = nil
        runLoopSource = nil
        holdActive    = false
        removeToggleMonitor()
    }

    // MARK: - Event Handling (called from C callback)

    fileprivate func handle(type: CGEventType, event: CGEvent) -> CGEvent? {

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))

        // ── Key-learning mode ─────────────────────────────────────────────────
        if isLearningKey && type == .keyDown {
            isLearningKey = false
            let label = KeyMonitor.labelFor(keyCode: keyCode)
            DispatchQueue.main.async {
                self.onKeyLearned?(keyCode, label)
            }
            return nil  // consume the event
        }

        if isLearningKey && type == .flagsChanged {
            // Accept modifier keys (Globe, Option, Cmd, etc.) as hold keys
            let knownModifiers: Set<Int> = [63, 54, 61, 57, 56, 60, 55, 58, 59]
            if knownModifiers.contains(keyCode) {
                isLearningKey = false
                let label = KeyMonitor.labelFor(keyCode: keyCode)
                DispatchQueue.main.async {
                    self.onKeyLearned?(keyCode, label)
                }
                return nil
            }
        }

        // ── Hold-to-talk mode ─────────────────────────────────────────────────
        if currentMode == .hold && type == .flagsChanged && keyCode == currentKeyCode {
            // For modifier keys, presence in flags means "key is down"
            let isDown = KeyMonitor.isFlagDown(event: event, keyCode: keyCode)

            if isDown && !holdActive {
                holdActive = true
                DispatchQueue.main.async { self.onHoldBegan?() }
            } else if !isDown && holdActive {
                holdActive = false
                DispatchQueue.main.async { self.onHoldEnded?() }
            }
            return event
        }

        // Toggle mode is handled by the NSEvent global monitor (see installToggleMonitor).
        // CGEventTap only serves hold-to-talk and key-learning.

        return event
    }

    // MARK: - Helpers

    /// Determine whether a modifier-key event represents key-down or key-up.
    private static func isFlagDown(event: CGEvent, keyCode: Int) -> Bool {
        let flags = event.flags
        switch keyCode {
        case 63:  // Fn / Globe
            return flags.contains(.maskSecondaryFn)
        case 54:  // Right Command
            return flags.contains(.maskCommand)
        case 61:  // Right Option
            return flags.contains(.maskAlternate)
        case 57:  // Caps Lock
            return flags.contains(.maskAlphaShift)
        case 56, 60:  // Left/Right Shift
            return flags.contains(.maskShift)
        case 55:  // Left Command
            return flags.contains(.maskCommand)
        case 58:  // Left Option
            return flags.contains(.maskAlternate)
        case 59:  // Left Control
            return flags.contains(.maskControl)
        default:
            return flags.rawValue != 0
        }
    }

    static func labelFor(keyCode: Int) -> String {
        let map: [Int: String] = [
            63: "Fn / Globe ⌨",
            54: "Right ⌘ Command",
            61: "Right ⌥ Option",
            57: "Caps Lock",
            56: "Left ⇧ Shift",
            60: "Right ⇧ Shift",
            55: "Left ⌘ Command",
            58: "Left ⌥ Option",
            59: "⌃ Control",
            // F-keys
            122: "F1",  120: "F2",  99: "F3",  118: "F4",
            96: "F5",   97: "F6",   98: "F7",  100: "F8",
            101: "F9",  109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15",
        ]
        return map[keyCode] ?? "Key \(keyCode)"
    }
}

// MARK: - C-compatible tap callback

private func keyMonitorCallback(
    proxy:    CGEventTapProxy,
    type:     CGEventType,
    event:    CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let ptr = userInfo else { return Unmanaged.passRetained(event) }
    let monitor = Unmanaged<KeyMonitor>.fromOpaque(ptr).takeUnretainedValue()
    if let passthrough = monitor.handle(type: type, event: event) {
        return Unmanaged.passRetained(passthrough)
    }
    return nil  // consumed
}
