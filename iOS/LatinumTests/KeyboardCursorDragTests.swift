import XCTest
import UIKit

/// Integration tests for the spacebar cursor drag at the KeyboardView↔delegate
/// boundary. A mock delegate models a text buffer with a clamped insertion
/// point (mirroring KeyboardViewController.moveCursor), so these exercise the
/// real CursorDragTracker + clamp-recalibration loop end to end.
final class KeyboardCursorDragTests: XCTestCase {

    /// Mock that mimics the controller: cursor index in a fixed-length buffer,
    /// movement clamped to [0, length], returning the offset actually applied.
    private final class MockDelegate: NSObject, KeyboardViewDelegate {
        let length: Int
        var cursor: Int
        var endCalls = 0

        init(length: Int, cursor: Int) {
            self.length = length
            self.cursor = cursor
        }

        func keyboardView(_ view: KeyboardView, didMoveCursorBy offset: Int) -> Int {
            let target = max(0, min(length, cursor + offset))
            let applied = target - cursor
            cursor = target
            return applied
        }

        func keyboardViewDidEndCursorDrag(_ view: KeyboardView) { endCalls += 1 }

        // Unused delegate requirements.
        func keyboardView(_ view: KeyboardView, didTapKey key: String) {}
        func keyboardView(_ view: KeyboardView, didTapSpecialKey key: String) {}
        func keyboardViewDidTapBackspace(_ view: KeyboardView) -> Bool { false }
        func keyboardViewDidDeleteWord(_ view: KeyboardView) -> Bool { false }
        func keyboardViewDidTapSpace(_ view: KeyboardView) {}
        func keyboardViewDidDoubleTapSpace(_ view: KeyboardView) {}
        func keyboardViewDidTapReturn(_ view: KeyboardView) {}
        func keyboardViewDidTapShift(_ view: KeyboardView) {}
        func keyboardViewDidDoubleTapShift(_ view: KeyboardView) {}
        func keyboardView(_ view: KeyboardView, didSelectPrediction prediction: String) {}
        func keyboardViewDidTapGlobe(_ view: KeyboardView) {}
        func keyboardViewDidTapDismiss(_ view: KeyboardView) {}
    }

    private func makeKeyboard(_ delegate: MockDelegate) -> KeyboardView {
        let kb = KeyboardView()
        kb.delegate = delegate
        return kb
    }

    // pointsPerStep is 8 in KeyboardView.

    func testDragRightMovesCursorForward() {
        let mock = MockDelegate(length: 20, cursor: 5)
        let kb = makeKeyboard(mock)

        kb.handleCursorDrag(state: .began, locationX: 100)
        kb.handleCursorDrag(state: .changed, locationX: 132) // +32pt → +4 chars
        kb.handleCursorDrag(state: .ended, locationX: 132)

        XCTAssertEqual(mock.cursor, 9)
        XCTAssertEqual(mock.endCalls, 1)
    }

    func testDragLeftMovesCursorBackward() {
        let mock = MockDelegate(length: 20, cursor: 10)
        let kb = makeKeyboard(mock)

        kb.handleCursorDrag(state: .began, locationX: 200)
        kb.handleCursorDrag(state: .changed, locationX: 176) // -24pt → -3 chars
        kb.handleCursorDrag(state: .ended, locationX: 176)

        XCTAssertEqual(mock.cursor, 7)
    }

    func testIncrementalDragAccumulates() {
        let mock = MockDelegate(length: 50, cursor: 0)
        let kb = makeKeyboard(mock)

        kb.handleCursorDrag(state: .began, locationX: 0)
        kb.handleCursorDrag(state: .changed, locationX: 8)   // +1
        kb.handleCursorDrag(state: .changed, locationX: 24)  // +2 more
        kb.handleCursorDrag(state: .changed, locationX: 40)  // +2 more
        kb.handleCursorDrag(state: .ended, locationX: 40)

        XCTAssertEqual(mock.cursor, 5)
    }

    /// Drag past the end (clamped), then reverse — the cursor must start moving
    /// back immediately with no dead zone from the unapplied overshoot.
    func testClampAtEndThenReverseHasNoDeadZone() {
        let mock = MockDelegate(length: 10, cursor: 8)
        let kb = makeKeyboard(mock)

        kb.handleCursorDrag(state: .began, locationX: 0)
        // Ask for +10 (to x=80) but only +2 available → clamps at end (10).
        kb.handleCursorDrag(state: .changed, locationX: 80)
        XCTAssertEqual(mock.cursor, 10)

        // Reverse by one step width: should immediately go to 9, not sit dead.
        kb.handleCursorDrag(state: .changed, locationX: 72)
        XCTAssertEqual(mock.cursor, 9)

        kb.handleCursorDrag(state: .ended, locationX: 72)
        XCTAssertEqual(mock.endCalls, 1)
    }

    /// A press-and-hold with no horizontal movement must not move the cursor
    /// (and must not insert anything — that path isn't even invoked).
    func testHoldWithoutMovementDoesNotMoveCursor() {
        let mock = MockDelegate(length: 20, cursor: 6)
        let kb = makeKeyboard(mock)

        kb.handleCursorDrag(state: .began, locationX: 150)
        kb.handleCursorDrag(state: .changed, locationX: 152) // 2pt < half step
        kb.handleCursorDrag(state: .ended, locationX: 152)

        XCTAssertEqual(mock.cursor, 6)
        XCTAssertEqual(mock.endCalls, 1)
    }
}
