import CoreGraphics
import XCTest
@testable import Sparingsmeter

final class MultiFrameOpeningTrackerTests: XCTestCase {
    func testTrackerRequiresMultipleFrames() {
        var tracker = MultiFrameOpeningTracker()
        tracker.add(.init(
            boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.7, height: 0.8),
            confidence: 0.9,
            timestamp: 1
        ))

        XCTAssertNil(tracker.trackedOpening)
    }

    func testTrackerCombinesStableObservations() {
        var tracker = MultiFrameOpeningTracker()

        for index in 0..<10 {
            let offset = CGFloat(index % 2) * 0.001
            tracker.add(.init(
                boundingBox: CGRect(
                    x: 0.10 + offset,
                    y: 0.10,
                    width: 0.70,
                    height: 0.80
                ),
                confidence: 0.9,
                timestamp: Double(index)
            ))
        }

        let tracked = tracker.trackedOpening
        XCTAssertNotNil(tracked)
        XCTAssertEqual(tracked?.observationCount, 10)
        XCTAssertGreaterThan(tracked?.stability ?? 0, 0.95)
    }
}
