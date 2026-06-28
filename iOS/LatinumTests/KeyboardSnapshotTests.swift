import XCTest
import UIKit

/// Renders KeyboardView at representative device sizes and writes PNGs for
/// visual inspection. Not an assertion-based test: it is a harness used during
/// development to verify layout on iPhone and iPad without installing the
/// keyboard in the simulator.
///
/// Output directory: $SNAPSHOT_DIR (pass via `xcodebuild TEST_RUNNER_SNAPSHOT_DIR=...`),
/// falling back to NSTemporaryDirectory()/latinum-snapshots.
final class KeyboardSnapshotTests: XCTestCase {

    private struct RenderSize {
        let width: CGFloat
        let height: CGFloat
        let name: String
    }

    private var outputDir: URL {
        if let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] {
            return URL(fileURLWithPath: dir, isDirectory: true)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("latinum-snapshots", isDirectory: true)
    }

    private var idiomName: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
    }

    func testRenderKeyboardSnapshots() throws {
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        // iPad sizes track the simulator's actual screen so orientation
        // resolution (which consults window.screen) is exercised faithfully.
        let screen = UIScreen.main.bounds.size
        let sizes: [RenderSize] = UIDevice.current.userInterfaceIdiom == .pad
            ? [
                RenderSize(width: min(screen.width, screen.height), height: 320, name: "portrait"),
                RenderSize(width: max(screen.width, screen.height), height: 392, name: "landscape"),
                RenderSize(width: 320, height: 282, name: "floating"),
            ]
            : [
                RenderSize(width: 393, height: 282, name: "portrait"),
                RenderSize(width: 852, height: 209, name: "landscape"),
            ]

        for size in sizes {
            // Letters plane, light + dark, with predictions populated.
            render(size: size, dark: false) { _ in }
            render(size: size, dark: true) { _ in }

            // Numbers plane (tap "123"), light only.
            render(size: size, dark: false, suffix: "-numbers") { kb in
                _ = kb.perform(Selector(("modeTapped")))
            }

            // Symbols plane (tap "123" then "#+="), light only.
            render(size: size, dark: false, suffix: "-symbols") { kb in
                _ = kb.perform(Selector(("modeTapped")))
                _ = kb.perform(Selector(("symbolToggleTapped")))
            }

            // Shifted letters, light only.
            render(size: size, dark: false, suffix: "-shift") { kb in
                kb.updateShiftState(.uppercase)
            }

            // URL keyboard type (extra bottom-row keys), light only.
            render(size: size, dark: false, suffix: "-url") { kb in
                kb.updateKeyboardType(.URL)
            }
        }

        print("Snapshots written to \(outputDir.path)")
    }

    private func render(size: RenderSize, dark: Bool, suffix: String = "", configure: (KeyboardView) -> Void) {
        let frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)

        let window = UIWindow(frame: frame)
        window.overrideUserInterfaceStyle = dark ? .dark : .light

        // Opaque stand-in for the system keyboard blur background.
        let container = UIView(frame: frame)
        container.backgroundColor = dark
            ? UIColor(white: 0.17, alpha: 1.0)
            : UIColor(red: 0.82, green: 0.835, blue: 0.86, alpha: 1.0)
        window.addSubview(container)

        let keyboard = KeyboardView()
        keyboard.frame = frame
        keyboard.autoresizingMask = []
        container.addSubview(keyboard)

        window.isHidden = false
        // First layout pass may rebuild the keyboard (orientation detection),
        // which clears prediction labels — so lay out before populating them.
        window.layoutIfNeeded()
        configure(keyboard)
        keyboard.updatePredictions(["salvē", "in", "nōn"])
        window.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(bounds: frame)
        let image = renderer.image { ctx in
            container.layer.render(in: ctx.cgContext)
        }

        let style = dark ? "dark" : "light"
        let name = "\(idiomName)-\(size.name)\(suffix)-\(style).png"
        let url = outputDir.appendingPathComponent(name)
        if let data = image.pngData() {
            try? data.write(to: url)
        }
        window.isHidden = true
    }
}
