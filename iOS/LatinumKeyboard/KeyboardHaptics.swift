import CoreHaptics

/// Low-latency haptic feedback using CoreHaptics.
///
/// Call `prepare()` once the keyboard view is in the hierarchy,
/// then `playHaptic()` on each key touch-down or popup open.
final class KeyboardHaptics {

    /// Whether haptic feedback is enabled. Defaults to true.
    /// Set to false to disable all haptics.
    var isEnabled: Bool = true

    private var engine: CHHapticEngine?
    private var player: CHHapticPatternPlayer?

    /// Create the haptic engine, start it, and build the transient player.
    func prepare() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = true

            engine.resetHandler = { [weak self] in
                do {
                    try self?.engine?.start()
                    self?.buildPlayer()
                } catch {}
            }

            try engine.start()
            self.engine = engine
            buildPlayer()
        } catch {}
    }

    /// Fire a short transient haptic event if enabled.
    func playHaptic() {
        guard isEnabled else { return }
        do {
            try player?.start(atTime: CHHapticTimeImmediate)
        } catch {}
    }

    // MARK: - Private

    private func buildPlayer() {
        guard let engine else { return }

        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9),
            ],
            relativeTime: 0
        )

        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            player = try engine.makePlayer(with: pattern)
        } catch {}
    }
}
