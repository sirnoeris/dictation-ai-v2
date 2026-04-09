import AppKit
import AVFoundation
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

        // Request microphone permission up-front via the native system dialog.
        // Only triggers the dialog if status is .notDetermined — no custom alert at launch.
        AVCaptureDevice.requestAccess(for: .audio) { _ in }

        // Warm up WhisperKit in background so the first recording is fast
        Task {
            await WhisperTranscriber.shared.loadModel(settings.whisperModel)
        }

        // First launch: open settings if no API key.
        // Use Task instead of DispatchQueue.asyncAfter — DispatchQueue closures
        // are not @MainActor-isolated in Swift 6, causing the compiler error.
        if !settings.hasXAIKey {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 800_000_000)
                self?.openSettings()
            }
        }

        // Accessibility is requested lazily when the first paste fails,
        // not proactively at launch — avoids the popup every time the binary changes.
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
            Task { @MainActor [weak self] in
                self?.openSettings()
            }
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

        AudioRecorder.shared.stop { [weak self] samples in
            guard let self else { return }
            Task { await self.runPipeline(audioSamples: samples) }
        }
    }

    func toggleRecording() {
        appState.isRecording ? stopRecording() : startRecording()
    }

    private func runPipeline(audioSamples: [Float]?) async {
        defer {
            updateTrayIcon()
            let delay: Double = appState.state.isError ? 4.0 : 2.5
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                self?.pillController.hide()
                try? await Task.sleep(nanoseconds: 300_000_000)
                self?.appState.transition(to: .idle)
            }
        }

        guard let samples = audioSamples else {
            appState.transition(to: .error("Audio capture failed"))
            SoundPlayer.shared.playError()
            return
        }

        do {
            // 1 ── Transcribe with WhisperKit (direct audioArray, no WAV file)
            let rawText = try await WhisperTranscriber.shared.transcribe(
                audioSamples: samples,
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
