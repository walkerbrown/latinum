import XCTest

/// Unit tests for the pure spacebar cursor-drag accounting.
final class CursorDragTrackerTests: XCTestCase {

    private func makeTracker() -> CursorDragTracker {
        CursorDragTracker(pointsPerStep: 8)
    }

    func testNoMovementBelowHalfStep() {
        var t = makeTracker()
        t.begin(atX: 100)
        // 3pt < half of 8pt → rounds to 0 characters.
        XCTAssertEqual(t.requestedDelta(atX: 103), 0)
    }

    func testForwardStepsByCharacter() {
        var t = makeTracker()
        t.begin(atX: 100)

        let d1 = t.requestedDelta(atX: 108)
        XCTAssertEqual(d1, 1)
        t.commit(applied: d1, requestedDelta: d1, atX: 108)

        let d2 = t.requestedDelta(atX: 116)
        XCTAssertEqual(d2, 1)
        t.commit(applied: d2, requestedDelta: d2, atX: 116)
    }

    func testBackwardMovesNegative() {
        var t = makeTracker()
        t.begin(atX: 100)
        XCTAssertEqual(t.requestedDelta(atX: 92), -1)
        XCTAssertEqual(t.requestedDelta(atX: 84), -2)
    }

    func testRequestedDeltaIsRelativeToAppliedOffset() {
        var t = makeTracker()
        t.begin(atX: 0)

        let d = t.requestedDelta(atX: 16)   // 2 chars
        XCTAssertEqual(d, 2)
        t.commit(applied: d, requestedDelta: d, atX: 16)

        // Further drag asks only for the incremental remainder.
        XCTAssertEqual(t.requestedDelta(atX: 24), 1)
    }

    func testClampRecalibratesSoReverseHasNoDeadZone() {
        var t = makeTracker()
        t.begin(atX: 0)

        // Finger wants 10 chars forward, but only 3 are available (clamped).
        let req = t.requestedDelta(atX: 80)
        XCTAssertEqual(req, 10)
        t.commit(applied: 3, requestedDelta: req, atX: 80)

        // At the same position, no further forward movement is requested.
        XCTAssertEqual(t.requestedDelta(atX: 80), 0)

        // Reversing by one step width immediately yields -1 (no dead zone from
        // the 7 unapplied chars).
        XCTAssertEqual(t.requestedDelta(atX: 72), -1)
    }

    func testExactApplyDoesNotRecalibrate() {
        var t = makeTracker()
        t.begin(atX: 0)

        let d = t.requestedDelta(atX: 24)   // 3 chars
        XCTAssertEqual(d, 3)
        t.commit(applied: d, requestedDelta: d, atX: 24)   // fully applied

        // Mapping is preserved: another 8pt → exactly one more char.
        XCTAssertEqual(t.requestedDelta(atX: 32), 1)
    }
}
