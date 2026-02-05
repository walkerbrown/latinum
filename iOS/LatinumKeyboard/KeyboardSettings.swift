import Foundation

/// Reads keyboard feedback settings from the shared App Group UserDefaults.
///
/// Settings are populated by the Settings.bundle in the main app and read
/// each time the keyboard appears.
enum KeyboardSettings {

    private static let defaults = UserDefaults(suiteName: "group.org.walkerbrown.latinum.shared")

    /// Whether sound feedback is enabled. Defaults to true if not set.
    static var soundEnabled: Bool {
        defaults?.object(forKey: "sound_feedback_enabled") as? Bool ?? true
    }

    /// Whether haptic feedback is enabled. Defaults to true if not set.
    static var hapticEnabled: Bool {
        defaults?.object(forKey: "haptic_feedback_enabled") as? Bool ?? true
    }
}
