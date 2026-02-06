import AudioToolbox

/// Low-latency haptic feedback using AudioToolbox system sounds.
///
/// Uses system haptic sound IDs which work reliably in keyboard extensions.
/// Call `playHaptic()` on each key touch-down or popup open.
final class KeyboardHaptics {

    /// Whether haptic feedback is enabled. Defaults to true.
    /// Set to false to disable all haptics.
    var isEnabled: Bool = true

    /// System sound ID for a light haptic tap (Peek).
    private let hapticSoundID: SystemSoundID = 1519

    /// No preparation needed for system sounds.
    func prepare() {
        // No-op: system sounds don't require preparation
    }

    /// Fire a short haptic event if enabled.
    func playHaptic() {
        guard isEnabled else { return }
        AudioServicesPlaySystemSound(hapticSoundID)
    }
}
