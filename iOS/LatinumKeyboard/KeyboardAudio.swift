import AudioToolbox

/// Low-latency click sound using AudioToolbox.
///
/// Marked as a UI sound so playback respects the silent switch.
/// Call `prepare()` once to load the sound file, then
/// `playClickSound()` on each key touch-down or selection change.
final class KeyboardAudio {

    /// Whether sound feedback is enabled. Defaults to true.
    /// Set to false to disable all click sounds.
    var isEnabled: Bool = true

    private var soundID: SystemSoundID = 0
    private var loaded = false

    /// Load key-down.wav from the keyboard extension bundle.
    func prepare() {
        guard let url = Bundle.main.url(forResource: "key-down", withExtension: "wav") else { return }

        let status = AudioServicesCreateSystemSoundID(url as CFURL, &soundID)
        guard status == kAudioServicesNoError else { return }

        // Mark as a UI sound so playback is silenced by the mute switch.
        var isUISound: UInt32 = 1
        AudioServicesSetProperty(
            kAudioServicesPropertyIsUISound,
            UInt32(MemoryLayout<SystemSoundID>.size),
            &soundID,
            UInt32(MemoryLayout<UInt32>.size),
            &isUISound
        )

        loaded = true
    }

    /// Play the pre-loaded click sound if enabled.
    func playClickSound() {
        guard isEnabled, loaded else { return }
        AudioServicesPlaySystemSound(soundID)
    }
}
