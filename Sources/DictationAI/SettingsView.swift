import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {

    @ObservedObject var settings: AppSettings

    // Key-learning state
    @State private var isLearningKey    = false
    @State private var learnButtonLabel = ""

    // WhisperKit model download progress
    @ObservedObject var transcriber = WhisperTranscriber.shared

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            ScrollView {
                VStack(spacing: 20) {
                    transcriptionSection
                    enhancementSection
                    hotkeySection
                    behaviourSection
                }
                .padding(20)
            }
            Divider().opacity(0.3)
            footer
        }
        .frame(width: 520, height: 620)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            learnButtonLabel = settings.holdKeyLabel
            KeyMonitor.shared.onKeyLearned = { code, label in
                settings.holdKeyCode  = code
                settings.holdKeyLabel = label
                learnButtonLabel      = label
                isLearningKey         = false
                KeyMonitor.shared.cancelLearning()
                KeyMonitor.shared.updateMode(settings.recordingMode, keyCode: code)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "mic.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            Text("Dictation AI")
                .font(.title2.bold())
            Spacer()
            Text("v2.0  ·  Swift + WhisperKit")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Transcription

    private var transcriptionSection: some View {
        SettingsSection(title: "Transcription") {
            SettingsRow(label: "On-device model") {
                Picker("", selection: $settings.whisperModel) {
                    ForEach(AppSettings.whisperModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .frame(width: 180)
                .onChange(of: settings.whisperModel) { _, newModel in
                    Task {
                        await WhisperTranscriber.shared.loadModel(newModel)
                    }
                }
            }

            SettingsRow(label: "Model status") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(modelStatusColor)
                        .frame(width: 7, height: 7)
                    Text(transcriber.modelState.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsRow(label: "Language") {
                TextField("Auto-detect", text: $settings.language)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .help("ISO code, e.g. 'en', 'fr', 'de'. Leave blank for auto-detect.")
            }
        }
    }

    // MARK: - Enhancement

    private var enhancementSection: some View {
        SettingsSection(title: "AI Text Cleanup") {
            SettingsRow(label: "Enable Grok cleanup") {
                Toggle("", isOn: $settings.enhancementEnabled)
                    .labelsHidden()
            }

            if settings.enhancementEnabled {
                SettingsRow(label: "xAI API key") {
                    SecureField("sk-…", text: $settings.xaiApiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }

                SettingsRow(label: "Model") {
                    Picker("", selection: $settings.xaiModel) {
                        ForEach(AppSettings.grokModels, id: \.self) { m in
                            Text(m).tag(m)
                        }
                    }
                    .frame(width: 180)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Cleanup prompt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $settings.enhancementPrompt)
                        .font(.caption)
                        .frame(height: 72)
                        .scrollContentBackground(.hidden)
                        .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.secondary.opacity(0.2))
                        )
                    Button("Reset to default") {
                        settings.enhancementPrompt = AppSettings.defaultPrompt
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    // MARK: - Hotkey

    private var hotkeySection: some View {
        SettingsSection(title: "Hotkey") {
            SettingsRow(label: "Recording mode") {
                Picker("", selection: $settings.recordingMode) {
                    ForEach(RecordingMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .frame(width: 180)
                .onChange(of: settings.recordingMode) { _, mode in
                    KeyMonitor.shared.updateMode(mode, keyCode: settings.holdKeyCode)
                }
            }

            if settings.recordingMode == .hold {
                // Configurable hold key
                SettingsRow(label: "Hold key") {
                    HStack(spacing: 8) {
                        Text(isLearningKey ? "Press a key…" : learnButtonLabel)
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(isLearningKey ? Color.accentColor : Color.secondary.opacity(0.3))
                            )

                        Button(isLearningKey ? "Cancel" : "Change…") {
                            if isLearningKey {
                                isLearningKey = false
                                KeyMonitor.shared.cancelLearning()
                            } else {
                                isLearningKey = true
                                KeyMonitor.shared.beginLearning()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if settings.holdKeyCode == 63 {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                        Text("For Globe/Fn: set System Settings → Keyboard → Press Globe key to → Do Nothing")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                // Fixed toggle shortcut — Carbon RegisterEventHotKey, no permissions needed
                SettingsRow(label: "Toggle key") {
                    HStack(spacing: 8) {
                        Text("⌃⌥Space")
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.secondary.opacity(0.3))
                            )
                        Text("(fixed shortcut)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Behaviour

    private var behaviourSection: some View {
        SettingsSection(title: "Behaviour") {
            SettingsRow(label: "Auto-paste at cursor") {
                Toggle("", isOn: $settings.autoPaste)
                    .labelsHidden()
                    .onChange(of: settings.autoPaste) { _, on in
                        if on { PasteService.shared.requestAccessibilityIfNeeded() }
                    }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Link("Get xAI key →", destination: URL(string: "https://console.x.ai")!)
                .font(.caption)
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    private var modelStatusColor: Color {
        switch transcriber.modelState {
        case .ready:       return .green
        case .failed:      return .red
        case .loading,
             .downloading: return .orange
        case .notLoaded:   return .gray
        }
    }
}

// MARK: - Reusable layout components

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
            content
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.15))
        )
    }
}

struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 160, alignment: .leading)
                .foregroundStyle(.primary)
            content
            Spacer()
        }
    }
}
