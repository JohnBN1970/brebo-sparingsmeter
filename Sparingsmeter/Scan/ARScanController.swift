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
    @Published private(set) var sessionEvent = "Geen sessiegebeurtenis"
    @Published private(set) var interruptionCount = 0
    @Published private(set) var failureCount = 0

    private let session = ARSession()
    private let openingDetector = VisionOpeningDetector()
    private var openingTracker = MultiFrameOpeningTracker()
    private var opening3D = Opening3DAccumulator()
    private var partialOpening = PartialOpeningAccumulator()
    private var frameCount = 0
    private var acceptedDepthFrameCount = 0
    private var latestTrackedOpening: TrackedOpening?
    private var userRequestedStop = false

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
        sessionEvent = "AR-sessie gestart"
        userRequestedStop = false
        isRunning = true
    }

    func stop() {
        userRequestedStop = true
        session.pause()
        isRunning = false
        pipelineState = "Scan gestopt door gebruiker"
        sessionEvent = "Handmatig gestopt"
    }
    func arSession() -> ARSession { session }

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
        guard let observation else { return }
        openingTracker.add(observation)
        guard let tracked = openingTracker.trackedOpening else { return }
        latestTrackedOpening = tracked; openingDetected = true
        openingDetectionConfidence = tracked.meanConfidence; openingTrackingStability = tracked.stability
        openingObservationCount = tracked.observationCount
    }

    private func ingestPartial3D(frame: ARFrame) {
        guard let candidates = DepthSweepSampler.sampleWorldEdgeCandidates(frame: frame) else { return }
        let accepted = candidates.structurallySupported
        partialOpening.add(accepted)
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

        let acceptedCombined = accepted.vertical + accepted.horizontal
        if !acceptedCombined.isEmpty {
            let step = max(1, acceptedCombined.count / 100)
            let visible = Array(acceptedCombined.enumerated().compactMap { index, point in
                index.isMultiple(of: step) ? point : nil
            }.prefix(120))
            NotificationCenter.default.post(name: .sparingsmeterAcceptedDebugPoints, object: visible)
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
    static let sparingsmeterAcceptedDebugPoints = Notification.Name("nl.brebo.sparingsmeter.acceptedDebugPoints")
}

extension ARScanController: ARSessionDelegate {
    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.interruptionCount += 1
            self.sessionEvent = "AR-sessie onderbroken"
            if !self.userRequestedStop {
                self.isRunning = true
                self.pipelineState = "Tijdelijk onderbroken - scan blijft actief"
            }
        }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard !self.userRequestedStop else { return }
            self.sessionEvent = "Onderbreking voorbij - sessie hervat"
            self.isRunning = true
            let configuration = ARWorldTrackingConfiguration()
            configuration.worldAlignment = .gravity
            configuration.environmentTexturing = .none
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                configuration.frameSemantics.insert(.sceneDepth)
            }
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                configuration.sceneReconstruction = .mesh
            }
            session.run(configuration, options: [])
            self.pipelineState = "Scan hervat"
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.failureCount += 1
            self.sessionEvent = "AR-fout: \(error.localizedDescription)"
            guard !self.userRequestedStop else { return }
            self.isRunning = true
            self.pipelineState = "AR-fout - automatisch opnieuw starten"
            let configuration = ARWorldTrackingConfiguration()
            configuration.worldAlignment = .gravity
            configuration.environmentTexturing = .none
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                configuration.frameSemantics.insert(.sceneDepth)
            }
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                configuration.sceneReconstruction = .mesh
            }
            session.run(configuration, options: [])
        }
    }

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
