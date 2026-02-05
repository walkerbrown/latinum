import SwiftUI

/// Latinum - A Predictive Latin Keyboard
///
/// This is the main app that hosts the keyboard extension.
/// The app itself provides setup instructions and keyboard settings.
@main
struct LatinumApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                SettingsSync.syncToAppGroup()
            }
        }
    }
}

/// Syncs Settings.bundle values from standard UserDefaults to the shared App Group.
enum SettingsSync {
    private static let standardDefaults = UserDefaults.standard
    private static let sharedDefaults = UserDefaults(suiteName: "group.org.walkerbrown.latinum.shared")

    static func syncToAppGroup() {
        let soundEnabled = standardDefaults.object(forKey: "sound_feedback_enabled") as? Bool ?? true
        let hapticEnabled = standardDefaults.object(forKey: "haptic_feedback_enabled") as? Bool ?? true

        sharedDefaults?.set(soundEnabled, forKey: "sound_feedback_enabled")
        sharedDefaults?.set(hapticEnabled, forKey: "haptic_feedback_enabled")
    }
}
