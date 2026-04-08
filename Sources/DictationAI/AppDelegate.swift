import AppKit
import SwiftUI

// MARK: - AppDelegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    // ── Shared state ──────────────────────────────────────────────────────────
    let settings   = AppSettings.shared
    let appState   = AppState.shared

    // ── UI controllers ────────────────────────────────────────────────────────
    private var statusItem:         NSStatusItem!
    private var pillController:     PillWindowController!
    private var settingsController: SettingsWindowController!

    // ── App lifecycle ─────────────────────────────────────────────────────────

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar only — no Dock icon
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        pillController     = PillWindowController(appState: appState, settings: settings)
        settingsController = SettingsWindowController(settings: settings)

        startKeyMonitor()
        hookAudioLevel()
        observeSettingsNotification()

        // Warm up WhisperKit in background so the first recording is fast
        Task {
            await WhisperTranscriber.shared.loadModel(settings.whisperModel)
        }

        // First launch: open settings if no API key
        if !settings.hasXAIKey {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.openSettings()
            }
        }

        // Request accessibility if auto-paste is on
        if settings.autoPaste {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                PasteService.shared.requestAccessibilityIfNeeded()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        KeyMonitor.shared.removeTap()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateTrayIcon()

        let menu = NSMenu()
        let settingsItem = NSMenuItem(
            title: "⚙️  Settings…",
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let recordItem = NSMenuItem(
            title: "🎙  Start Recording",
            action: #selector(menuToggleRecording),
            keyEquivalent: ""
        )
        recordItem.target = self
        menu.addItem(recordItem)
        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Dictation AI",
            action: #selector(NSApp.terminate(_:)),
            keyEquivalent: ""
        )
        menu.addItem(quit)

        statusItem.menu = menu
        menu.delegate   = self
    }

    private func updateTrayIcon() {
        let name  = appState.isRecording ? "mic.fill" : "mic"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        if !appState.isRecording { image?.isTemplate = true }
        statusItem.button?.image = image
    }

    // MARK: - Key Monitor

    private func startKeyMonitor() {
        let monitor = KeyMonitor.shared

        monitor.onHoldBegan = { [weak self] in self?.startRecording() }
        monitor.onHoldEnded = { [weak self] in self?.stopRecording() }
        monitor.onToggle    = { [weak self] in self?.toggleRecording() }

        monitor.start(mode: settings.recordingMode, keyCode: settings.holdKeyCode)
    }

    // MARK: - Audio Level → AppState

    private func hookAudioLevel() {
        AudioRecorder.shared.onLevelUpdate = { [weak self] level in
            self?.appState.updateAudioLevel(level)
        }
    }

    // MARK: - Notification: Open Settings

    private func observeSettingsNotification() {
        NotificationCenter.default.addObserver(
            forName: .openSettings,
            object:  nil,
            queue:   .main
        ) { [weak self] _ in
            self?.openSettings()
        }
    }

    // MARK: - Recording Pipeline

    func startRecording() {
        guard !appState.isBusy else { return }

        // Snapshot the frontmost app before the pill appears
        PasteService.shared.captureFrontApp()

        appState.transition(to: .recording)
        updateTrayIcon()
        pillController.show()
        AudioRecorder.shared.start()
        SoundPlayer.shared.playStart()
    }

    func stopRecording() {
        guard appState.isRecording else { return }

        appState.transition(to: .processing)
        SoundPlayer.shared.playStop()
        updateTrayIcon()

        AudioRecorder.shared.stop { [weak self] url in
            guard let self else { return }
            Task { await self.runPipeline(audioFileURL: url) }
        }
    }

    func toggleRecording() {
        appState.isRecording ? stopRecording() : startRecording()
    }

    private func runPipeline(audioFileURL: URL?) async {
        defer {
            updateTrayIcon()
            // Auto-hide pill after 2.5 s unless it was an error
            let delay: Double = appState.state.isError ? 4.0 : 2.5
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.pillController.hide()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.appState.transition(to: .idle)
                }
            }
        }

        guard let url = audioFileURL else {
            appState.transition(to: .error("Audio capture failed"))
            SoundPlayer.shared.playError()
            return
        }

        do {
            // 1 ── Transcribe with WhisperKit
            let rawText = try await WhisperTranscriber.shared.transcribe(
                audioFileURL: url,
                language:     settings.language,
                modelName:    settings.whisperModel
            )

            let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                appState.setResult("(nothing detected)")
                return
            }

            // 2 ── Enhance with xAI Grok
            var finalText = trimmed
            if settings.enhancementEnabled && settings.hasXAIKey {
                // Extract Sendable strings before crossing into the actor
                let key    = settings.xaiApiKey
                let model  = settings.xaiModel
                let prompt = settings.enhancementPrompt
                finalText  = (try? await GrokEnhancer.shared.enhance(
                    trimmed, apiKey: key, model: model, prompt: prompt
                )) ?? trimmed
            }

            appState.setResult(finalText)

            // 3 ── Auto-paste
            if settings.autoPaste {
                await PasteService.shared.paste(finalText)
                SoundPlayer.shared.playPaste()
            }

            // Clean up temp audio file
            try? FileManager.default.removeItem(at: url)

        } catch {
            appState.transition(to: .error(error.localizedDescription))
            SoundPlayer.shared.playError()
        }
    }

    // MARK: - Actions

    @objc func openSettings() {
        settingsController.show()
    }

    @objc func menuToggleRecording() {
        toggleRecording()
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        // Update the recording menu item label dynamically
        if let item = menu.items.first(where: { $0.action == #selector(menuToggleRecording) }) {
            item.title = appState.isRecording
                ? "⏹  Stop Recording"
                : "🎙  Start Recording"
        }
    }
}
