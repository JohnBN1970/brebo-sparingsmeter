import ARKit
import Foundation
import SwiftUI

@MainActor
final class ARScanController: NSObject, ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var coverage: Double = 0
    @Published private(set) var estimatedUncertaintyMM: Double?
    @Published private(set) var geometry = OpeningGeometry()

    @Published private(set) var openingDetected = false
    @Published private(set) var openingDetectionConfidence: Float = 0
    @Published private(set) var openingTrackingStability: Double = 0
    @Published private(set) var openingObservationCount: Int = 0
    @Published private(set) var liveWidthMM: Double?
    @Published private(set) var liveHeightMM: Double?
    @Published private(set) var live3DPointCount: Int = 0

    @Published private(set) var depthFrameCount = 0
    @Published private(set) var accepted3DFrameCount = 0
    @Published private(set) var lastEdgePointCounts = (left: 0, right: 0, top: 0, bottom: 0)
    @Published private(set) var partialVerticalPointCount = 0
    @Published private(set) var partialHorizontalPointCount = 0
    @Published private(set) var pipelineState = "Wacht op scan"

    private let session = ARSession()
    private let openingDetector = VisionOpeningDetector()
    private var openingTracker = MultiFrameOpeningTracker()
    private var opening3D = Opening3DAccumulator()
    private var partialOpening = PartialOpeningAccumulator()
    private var frameCount = 0
    private var acceptedDepthFrameCount = 0
    private var latestTrackedOpening: TrackedOpening?

    override init() { super.init(); session.delegate = self }

    var quality: ScanQualityStatus {
        ScanQualityEvaluator.evaluate(coverage: coverage, uncertaintyMM: estimatedUncertaintyMM)
    }

    func start() {
        guard ARWorldTrackingConfiguration.isSupported else { pipelineState = "ARKit niet ondersteund"; return }
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.environmentTexturing = .none
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) { configuration.frameSemantics.insert(.sceneDepth) }
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) { configuration.sceneReconstruction = .mesh }
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        frameCount = 0; acceptedDepthFrameCount = 0; coverage = 0; estimatedUncertaintyMM = nil
        geometry = OpeningGeometry(); openingTracker.reset(); opening3D.reset(); partialOpening.reset()
        latestTrackedOpening = nil; openingDetected = false; openingDetectionConfidence = 0
        openingTrackingStability = 0; openingObservationCount = 0; liveWidthMM = nil; liveHeightMM = nil
        live3DPointCount = 0; depthFrameCount = 0; accepted3DFrameCount = 0
        lastEdgePointCounts = (0,0,0,0); partialVerticalPointCount = 0; partialHorizontalPointCount = 0
        pipelineState = "Deelscan actief - gele punten = opgenomen LiDAR-randen"
        isRunning = true
    }

    func stop() { session.pause(); isRunning = false; pipelineState = "Scan gestopt" }
    func arSession() -> ARSession { session }

    private func handleOpeningObservation(_ observation: OpeningObservation?) {
        guard let observation else { return }
        openingTracker.add(observation)
        guard let tracked = openingTracker.trackedOpening else { return }
        latestTrackedOpening = tracked; openingDetected = true
        openingDetectionConfidence = tracked.meanConfidence; openingTrackingStability = tracked.stability
        openingObservationCount = tracked.observationCount
    }

    private func ingestPartial3D(frame: ARFrame) {
        guard let candidates = DepthSweepSampler.sampleWorldEdgeCandidates(frame: frame) else { return }
        partialOpening.add(candidates)
        partialVerticalPointCount = partialOpening.vertical.count
        partialHorizontalPointCount = partialOpening.horizontal.count

        // Publish a thinned sample to the AR overlay. These are exactly the
        // world-space LiDAR edge candidates entering the partial scan engine.
        let combined = candidates.vertical + candidates.horizontal
        if !combined.isEmpty {
            let step = max(1, combined.count / 140)
            let visible = Array(combined.enumerated().compactMap { index, point in
                index.isMultiple(of: step) ? point : nil
            }.prefix(160))
            NotificationCenter.default.post(name: .sparingsmeterDebugPoints, object: visible)
        }

        guard let measurement = partialOpening.measurement else {
            if latestTrackedOpening == nil { pipelineState = "Deelscan: lokale 3D-randen verzamelen" }
            return
        }
        if opening3D.measurement == nil {
            liveWidthMM = measurement.widthMM; liveHeightMM = measurement.heightMM
            live3DPointCount = measurement.verticalPointCount + measurement.horizontalPointCount
            pipelineState = "Deelscan 3D actief"
        }
    }

    private func ingestVisionGuided3D(frame: ARFrame) {
        guard frame.sceneDepth != nil, let tracked = latestTrackedOpening, tracked.observationCount >= 5,
              let clouds = DepthEdgeSampler.sampleWorldPoints(tracked: tracked, frame: frame) else { return }
        lastEdgePointCounts = (clouds.left.count, clouds.right.count, clouds.top.count, clouds.bottom.count)
        let minimumPerEdge = 4
        guard clouds.left.count >= minimumPerEdge, clouds.right.count >= minimumPerEdge,
              clouds.top.count >= minimumPerEdge, clouds.bottom.count >= minimumPerEdge else { return }
        opening3D.add(clouds); accepted3DFrameCount += 1
        live3DPointCount = opening3D.measurement?.pointCount ?? live3DPointCount
        guard let measurement = opening3D.measurement else { return }
        liveWidthMM = measurement.widthMM; liveHeightMM = measurement.heightMM
        pipelineState = "Volledige 3D-meting actief"
        estimatedUncertaintyMM = max(2.5, measurement.fitResidualMM)
    }
}

extension Notification.Name {
    static let sparingsmeterDebugPoints = Notification.Name("nl.brebo.sparingsmeter.debugPoints")
}

extension ARScanController: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let depthData = frame.sceneDepth
        let capturedImage = frame.capturedImage
        let timestamp = frame.timestamp
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.frameCount += 1
            if depthData != nil { self.acceptedDepthFrameCount += 1; self.depthFrameCount = self.acceptedDepthFrameCount }
            self.ingestPartial3D(frame: frame); self.ingestVisionGuided3D(frame: frame)
            let depthCoverage = min(1.0, Double(self.acceptedDepthFrameCount) / 120.0)
            let visionCoverage = min(1.0, Double(self.openingObservationCount) / 45.0)
            let partialCoverage = min(1.0, Double(min(self.partialVerticalPointCount, self.partialHorizontalPointCount)) / 900.0)
            let cloudCoverage = min(1.0, Double(self.live3DPointCount) / 800.0)
            self.coverage = min(depthCoverage, max(max(visionCoverage * 0.8, partialCoverage), cloudCoverage))
        }
        if Int(timestamp * 10) % 2 == 0 {
            openingDetector.detectOpening(pixelBuffer: capturedImage) { [weak self] observation in
                Task { @MainActor in self?.handleOpeningObservation(observation) }
            }
        }
    }
}
