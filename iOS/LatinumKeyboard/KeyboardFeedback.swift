import UIKit

/// Centralized haptic and click feedback for the keyboard.
///
/// Pre-allocates feedback generators to eliminate first-tap latency.
/// Haptics automatically respect Settings > Sounds & Haptics > System Haptics.
/// Key click sound automatically respects Settings > Sounds & Haptics > Keyboard Clicks.
final class KeyboardFeedback {

    static let shared = KeyboardFeedback()

    private let keyImpact = UIImpactFeedbackGenerator(style: .light)
    private let popupImpact = UIImpactFeedbackGenerator(style: .medium)
    private let deleteImpact = UIImpactFeedbackGenerator(style: .rigid)
    private let selectionFeedback = UISelectionFeedbackGenerator()

    private init() {}

    /// Prime the Taptic Engine. Call when the keyboard becomes visible.
    func prepare() {
        keyImpact.prepare()
        popupImpact.prepare()
        deleteImpact.prepare()
        selectionFeedback.prepare()
    }

    /// Touch-down on any key: light haptic + system click sound.
    func playKeyDown() {
        keyImpact.impactOccurred()
        keyImpact.prepare()
        UIDevice.current.playInputClick()
    }

    /// Accent popover opened: medium haptic.
    func playPopupOpen() {
        popupImpact.impactOccurred()
        popupImpact.prepare()
    }

    /// Selection changed within accent popover: selection tick.
    func playSelectionChanged() {
        selectionFeedback.selectionChanged()
        selectionFeedback.prepare()
    }

    /// Character or word deleted during backspace hold: rigid haptic.
    func playDelete() {
        deleteImpact.impactOccurred()
        deleteImpact.prepare()
    }
}
