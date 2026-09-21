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

    // Practical-test diagnostics. These deliberately expose where the live
    // pipeline stops so field testing can diagnose Vision vs LiDAR vs fitting.
    @Published private(set) var depthFrameCount: Int = 0
    @Published private(set) var accepted3DFrameCount: Int = 0
    @Published private(set) var lastEdgePointCounts = (left: 0, right: 0, top: 0, bottom: 0)
    @Published private(set) var pipelineState: String = "Wacht op scan"

    private let session = ARSession()
    private let openingDetector = VisionOpeningDetector()
    private var openingTracker = MultiFrameOpeningTracker()
    private var opening3D = Opening3DAccumulator()

    private var frameCount = 0
    private var acceptedDepthFrameCount = 0
    private var latestTrackedOpening: TrackedOpening?

    override init() {
        super.init()
        session.delegate = self
    }

    var quality: ScanQualityStatus {
        ScanQualityEvaluator.evaluate(
            coverage: coverage,
            uncertaintyMM: estimatedUncertaintyMM
        )
    }

    func start() {
        guard ARWorldTrackingConfiguration.isSupported else {
            pipelineState = "ARKit niet ondersteund"
            return
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.environmentTexturing = .none

        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }

        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }

        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        frameCount = 0
        acceptedDepthFrameCount = 0
        coverage = 0
        estimatedUncertaintyMM = nil
        geometry = OpeningGeometry()

        openingTracker.reset()
        opening3D.reset()
        latestTrackedOpening = nil

        openingDetected = false
        openingDetectionConfidence = 0
        openingTrackingStability = 0
        openingObservationCount = 0
        liveWidthMM = nil
        liveHeightMM = nil
        live3DPointCount = 0

        depthFrameCount = 0
        accepted3DFrameCount = 0
        lastEdgePointCounts = (0, 0, 0, 0)
        pipelineState = "Zoekt sparing"

        isRunning = true
    }

    func stop() {
        session.pause()
        isRunning = false
        pipelineState = "Scan gestopt"
    }

    func arSession() -> ARSession {
        session
    }

    func injectFittedGeometryForDevelopment(
        widthsMM: [Double],
        heightsMM: [Double],
        uncertaintyMM: Double
    ) {
        guard !widthsMM.isEmpty, !heightsMM.isEmpty else { return }

        geometry.widthSections = widthsMM.enumerated().map { index, value in
            OpeningSection(
                normalizedPosition: widthsMM.count == 1 ? 0.5 : Double(index) / Double(widthsMM.count - 1),
                freeSize: MeasuredValue(
                    millimetres: value,
                    uncertaintyMillimetres: uncertaintyMM,
                    source: .calculated
                )
            )
        }

        geometry.heightSections = heightsMM.enumerated().map { index, value in
            OpeningSection(
                normalizedPosition: heightsMM.count == 1 ? 0.5 : Double(index) / Double(heightsMM.count - 1),
                freeSize: MeasuredValue(
                    millimetres: value,
                    uncertaintyMillimetres: uncertaintyMM,
                    source: .calculated
                )
            )
        }

        estimatedUncertaintyMM = uncertaintyMM
    }

    private func handleOpeningObservation(_ observation: OpeningObservation?) {
        guard let observation else {
            if latestTrackedOpening == nil {
                pipelineState = "Vision: nog geen sparing"
            }
            return
        }

        openingTracker.add(observation)
        guard let tracked = openingTracker.trackedOpening else {
            pipelineState = "Vision: meer frames nodig"
            return
        }

        latestTrackedOpening = tracked
        openingDetected = true
        openingDetectionConfidence = tracked.meanConfidence
        openingTrackingStability = tracked.stability
        openingObservationCount = tracked.observationCount
        pipelineState = "Vision OK - LiDAR bemonsteren"
    }

    private func ingest3D(frame: ARFrame) {
        guard frame.sceneDepth != nil else {
            pipelineState = "Geen sceneDepth"
            return
        }

        guard let tracked = latestTrackedOpening else {
            pipelineState = "Wacht op Vision-detectie"
            return
        }

        // Do not require a fixed image-space rectangle. The camera is meant to
        // move around the opening. We use the latest corners and let the 3D
        // robust line fit reject depth outliers.
        guard tracked.observationCount >= 5 else {
            pipelineState = "Te weinig Vision-frames"
            return
        }

        guard let clouds = DepthEdgeSampler.sampleWorldPoints(
            tracked: tracked,
            frame: frame
        ) else {
            pipelineState = "LiDAR: geen punten"
            return
        }

        lastEdgePointCounts = (
            clouds.left.count,
            clouds.right.count,
            clouds.top.count,
            clouds.bottom.count
        )

        // Require usable support on every side, not a high image-space
        // stability percentage.
        let minimumPerEdge = 4
        guard
            clouds.left.count >= minimumPerEdge,
            clouds.right.count >= minimumPerEdge,
            clouds.top.count >= minimumPerEdge,
            clouds.bottom.count >= minimumPerEdge
        else {
            pipelineState = "LiDAR: onvoldoende punten per zijde"
            return
        }

        opening3D.add(clouds)
        accepted3DFrameCount += 1
        live3DPointCount = opening3D.measurement?.pointCount ?? 0

        guard let measurement = opening3D.measurement else {
            pipelineState = "3D: lijnfit opbouwen"
            return
        }

        liveWidthMM = measurement.widthMM
        liveHeightMM = measurement.heightMM
        pipelineState = "3D-meting actief"

        // Fit residual is real, but total metrological uncertainty still needs
        // calibration against known references. Until that validation exists,
        // never publish < 2.5 mm even when the raw fit residual is smaller.
        estimatedUncertaintyMM = max(2.5, measurement.fitResidualMM)

        // Only materialise production geometry when the validated uncertainty
        // gate can actually be satisfied. For now this intentionally remains closed.
        if estimatedUncertaintyMM ?? 999 <= MeasurementRules.maximumMeasurementDeviationMM {
            geometry.widthSections = [
                OpeningSection(
                    normalizedPosition: 0.5,
                    freeSize: MeasuredValue(
                        millimetres: measurement.widthMM,
                        uncertaintyMillimetres: estimatedUncertaintyMM ?? 999,
                        source: .measured
                    )
                )
            ]
            geometry.heightSections = [
                OpeningSection(
                    normalizedPosition: 0.5,
                    freeSize: MeasuredValue(
                        millimetres: measurement.heightMM,
                        uncertaintyMillimetres: estimatedUncertaintyMM ?? 999,
                        source: .measured
                    )
                )
            ]
        }
    }
}

extension ARScanController: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let depthData = frame.sceneDepth
        let capturedImage = frame.capturedImage
        let timestamp = frame.timestamp

        Task { @MainActor [weak self] in
            guard let self else { return }

            self.frameCount += 1
            if depthData != nil {
                self.acceptedDepthFrameCount += 1
                self.depthFrameCount = self.acceptedDepthFrameCount
            }

            self.ingest3D(frame: frame)

            let depthCoverage = min(1.0, Double(self.acceptedDepthFrameCount) / 120.0)
            let edgeCoverage = min(1.0, Double(self.openingObservationCount) / 45.0)
            let cloudCoverage = min(1.0, Double(self.live3DPointCount) / 800.0)

            self.coverage = min(
                depthCoverage,
                max(edgeCoverage * 0.8, cloudCoverage)
            )
        }

        if Int(timestamp * 10) % 2 == 0 {
            openingDetector.detectOpening(pixelBuffer: capturedImage) { [weak self] observation in
                Task { @MainActor in
                    self?.handleOpeningObservation(observation)
                }
            }
        }
    }
}
