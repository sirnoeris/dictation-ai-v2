# 🎙 Dictation AI v2

> Native macOS Swift app — hold Fn/Globe, speak, text appears at your cursor.
> On-device transcription via **WhisperKit**. Smart cleanup via **xAI Grok**.

Built as a complete rewrite of [v1 (Electron)](https://github.com/sirnoeris/dictation-ai) using native macOS APIs: WhisperKit + SwiftUI + CGEventTap.

---

## Why v2?

| | v1 (Electron) | v2 (Swift) |
|---|---|---|
| Transcription | Groq/OpenAI API (cloud) | WhisperKit (on-device, free) |
| Privacy | Audio sent to cloud | Audio never leaves your Mac |
| Binary size | ~250 MB | ~8 MB |
| Memory | ~250 MB | ~60 MB |
| Startup | ~3 s | ~0.3 s |
| Offline | ✗ | ✓ |

---

## Features

- **Hold-to-talk or toggle mode** — hold Fn/Globe (or any key), release to transcribe
- **On-device transcription** — WhisperKit runs Whisper via CoreML on Apple Silicon
- **Live audio waveform** — animated bars respond to your voice while recording
- **AI cleanup** — Grok removes fillers, fixes punctuation (skip if ≤5 words)
- **Auto-paste** — text lands at your cursor via CGEvent Cmd+V simulation
- **Draggable pill UI** — floating translucent pill, position remembered across relaunches
- **Sound cues** — subtle macOS system sounds on start, stop, paste
- **Any hold key** — configure any modifier key including Fn/Globe, Right ⌘, Caps Lock
- **Menu bar app** — no Dock icon, always available, right-click for menu
- **Settings window** — full UI for all config options

---

## Quick Start

```bash
git clone https://github.com/sirnoeris/dictation-ai-v2.git
cd dictation-ai-v2
bash setup.sh          # installs XcodeGen, generates .xcodeproj
open DictationAI.xcodeproj
```

Then in Xcode: set your Team in Signing & Capabilities, then **⌘R**.

---

## Setup

### 1. Globe/Fn key

**System Settings → Keyboard → Press Globe key to → Do Nothing**

Without this, macOS intercepts the key before the app sees it.

### 2. Accessibility (for auto-paste)

On first launch you'll be prompted. Or run:
```bash
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
```
Add **Dictation AI** and enable it.

### 3. Microphone

Prompted automatically on first recording.

### 4. xAI API key (optional)

Get a free key at [console.x.ai](https://console.x.ai) for Grok text cleanup. The app works without it — just no cleanup step.

---

## Architecture

```
Sources/DictationAI/
├── DictationAIApp.swift          @main — SwiftUI App (menu-bar only)
├── AppDelegate.swift             Orchestrates the full pipeline
├── AppSettings.swift             UserDefaults-backed settings model
├── AppState.swift                @Observable state machine (idle/recording/processing/done)
├── AudioRecorder.swift           AVAudioEngine → 16 kHz mono PCM → temp WAV
├── WhisperTranscriber.swift      WhisperKit wrapper (lazy model load, DecodingOptions)
├── GrokEnhancer.swift            xAI REST API client (OpenAI-compatible)
├── KeyMonitor.swift              CGEventTap — Fn/Globe flagsChanged + keyDown
├── PasteService.swift            CGEvent Cmd+V auto-paste, tracks previous front app
├── SoundPlayer.swift             macOS system sounds via AudioToolbox
├── PillWindowController.swift    NSPanel (non-activating, floating, .canJoinAllSpaces)
├── PillView.swift                SwiftUI pill content — adapts to each state
├── WaveformView.swift            5-bar animated audio visualiser
├── SettingsWindowController.swift NSWindow for settings
└── SettingsView.swift            Full SwiftUI settings form
```

**Recording pipeline:**
1. Fn/Globe keydown → `CGEventTap` fires `onHoldBegan`
2. `AVAudioEngine` tap captures 16 kHz mono PCM into thread-safe buffer
3. Fn/Globe release → stop engine, write buffer to temp WAV
4. `WhisperKit.transcribe()` → raw text
5. `GrokEnhancer.enhance()` → cleaned text (if xAI key present & >5 words)
6. Write to clipboard → CGEvent Cmd+V → restore previous clipboard after 3 s
7. Pill auto-hides after 2.5 s

---

## Settings

| Setting | Default | Description |
|---------|---------|-------------|
| Whisper model | `base` | `tiny` → fast, `large-v3` → accurate |
| xAI API key | — | Optional; enables Grok cleanup |
| Grok model | `grok-3-mini` | Fast and cheap |
| Cleanup prompt | Built-in | Customisable |
| Recording mode | Hold | Hold or Toggle |
| Hold key | Fn / Globe | Any modifier key |
| Auto-paste | ✓ | CGEvent Cmd+V |
| Language | Auto-detect | ISO code e.g. `en` |

---

## Building a .app bundle

```bash
xcodebuild -project DictationAI.xcodeproj \
           -scheme DictationAI \
           -configuration Release \
           -archivePath ./build/DictationAI.xcarchive \
           archive

xcodebuild -exportArchive \
           -archivePath ./build/DictationAI.xcarchive \
           -exportPath ./dist \
           -exportOptionsPlist ExportOptions.plist
```

---

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon (M1+) for WhisperKit CoreML acceleration
- Xcode 15.0+ to build

---

## Cost

| Component | Cost |
|-----------|------|
| WhisperKit transcription | Free (on-device) |
| xAI Grok cleanup | ~$0.01–0.15/month at typical usage |

---

## License

MIT
