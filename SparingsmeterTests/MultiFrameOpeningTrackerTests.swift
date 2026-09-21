import CoreGraphics
import XCTest
@testable import Sparingsmeter

final class MultiFrameOpeningTrackerTests: XCTestCase {
    private func observation(
        boundingBox: CGRect,
        confidence: Float,
        timestamp: TimeInterval
    ) -> OpeningObservation {
        OpeningObservation(
            topLeft: CGPoint(x: boundingBox.minX, y: boundingBox.maxY),
            topRight: CGPoint(x: boundingBox.maxX, y: boundingBox.maxY),
            bottomLeft: CGPoint(x: boundingBox.minX, y: boundingBox.minY),
            bottomRight: CGPoint(x: boundingBox.maxX, y: boundingBox.minY),
            confidence: confidence,
            timestamp: timestamp
        )
    }

    func testTrackerRequiresMultipleFrames() {
        var tracker = MultiFrameOpeningTracker()
        tracker.add(observation(
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
            tracker.add(observation(
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
