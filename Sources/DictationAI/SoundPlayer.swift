import AppKit
import AudioToolbox

// MARK: - SoundPlayer
// Uses macOS system sounds for subtle audio feedback.

final class SoundPlayer {

    static let shared = SoundPlayer()
    private init() {}

    // Subtle system sound IDs (tested in Sonoma / Sequoia)
    private let startSoundID:  SystemSoundID = 1113   // Frog
    private let stopSoundID:   SystemSoundID = 1114   // Pop
    private let pasteSoundID:  SystemSoundID = 1519   // Tink
    private let errorSoundID:  SystemSoundID = 1006   // Basso

    func playStart()  { AudioServicesPlaySystemSound(startSoundID) }
    func playStop()   { AudioServicesPlaySystemSound(stopSoundID) }
    func playPaste()  { AudioServicesPlaySystemSound(pasteSoundID) }
    func playError()  { AudioServicesPlaySystemSound(errorSoundID) }
}
