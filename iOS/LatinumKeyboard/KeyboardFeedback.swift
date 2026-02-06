import AudioToolbox

/// Unified audio and haptic feedback for the keyboard.
///
/// Uses AudioToolbox for both click sounds and haptic feedback, which works
/// reliably in keyboard extensions. Call `prepare()` once at startup to load
/// the click sound, then `provideFeedback()` on key events.
final class KeyboardFeedback {

    /// Whether sound feedback is enabled.
    var soundEnabled: Bool = true

    /// Whether haptic feedback is enabled.
    var hapticEnabled: Bool = true

    private var soundID: SystemSoundID = 0
    private var soundLoaded = false

    /// System sound ID for a light haptic tap (Peek).
    private let hapticSoundID: SystemSoundID = 1519

    /// Load the click sound from the keyboard extension bundle.
    func prepare() {
        guard !soundLoaded else { return }
        guard let url = Bundle.main.url(forResource: "key-down", withExtension: "wav") else { return }

        let status = AudioServicesCreateSystemSoundID(url as CFURL, &soundID)
        guard status == kAudioServicesNoError else { return }

        // Mark as a UI sound so playback respects the silent switch.
        var isUISound: UInt32 = 1
        AudioServicesSetProperty(
            kAudioServicesPropertyIsUISound,
            UInt32(MemoryLayout<SystemSoundID>.size),
            &soundID,
            UInt32(MemoryLayout<UInt32>.size),
            &isUISound
        )

        soundLoaded = true
    }

    /// Play click sound and haptic feedback based on enabled settings.
    func provideFeedback() {
        if soundEnabled, soundLoaded {
            AudioServicesPlaySystemSound(soundID)
        }
        if hapticEnabled {
            AudioServicesPlaySystemSound(hapticSoundID)
        }
    }

    /// Play only haptic feedback (for events like popup appearance).
    func provideHapticOnly() {
        guard hapticEnabled else { return }
        AudioServicesPlaySystemSound(hapticSoundID)
    }
}
