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
    @Published private(set) var positionLockProgress: Double = 0
    @Published private(set) var positionLocked = false
    @Published private(set) var positionState = "Positie nog niet bepaald"
    @Published private(set) var positionSideLocks = OpeningSideLocks(left: false, right: false, top: false, bottom: false)
    @Published private(set) var openingValidationScore: Double = 0
    @Published private(set) var openingValidationState = "Opening nog niet gevalideerd"
    @Published private(set) var boundaryRefinementMM: Double = 0
    @Published private(set) var boundaryRefinementSidesMM = (left: 0.0, right: 0.0, top: 0.0, bottom: 0.0)
    @Published private(set) var boundaryRefinementFound = (left: false, right: false, top: false, bottom: false)
    @Published private(set) var boundaryRefinementEvidence = (left: 0.0, right: 0.0, top: 0.0, bottom: 0.0)

    private let session = ARSession()
    private let openingDetector = VisionOpeningDetector()
    private var openingTracker = MultiFrameOpeningTracker()
    private var opening3D = Opening3DAccumulator()
    private var partialOpening = PartialOpeningAccumulator()
    private var positionTracker = OpeningPositionTracker()
    private var frameCount = 0
    private var acceptedDepthFrameCount = 0
    private var latestTrackedOpening: TrackedOpening?
    private var userRequestedStop = false
    private var lastFrameWallClock = Date()
    private var watchdogTask: Task<Void, Never>?

    override init() { super.init(); session.delegate = self }

    var quality: ScanQualityStatus {
        ScanQualityEvaluator.evaluate(coverage: coverage, uncertaintyMM: estimatedUncertaintyMM)
    }

    func start() {
        guard ARWorldTrackingConfiguration.isSupported else { pipelineState = "ARKit niet ondersteund"; return }
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.environmentTexturing = .none
        configuration.planeDetection = [.vertical]
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) { configuration.frameSemantics.insert(.sceneDepth) }
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) { configuration.sceneReconstruction = .mesh }
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        frameCount = 0; acceptedDepthFrameCount = 0; coverage = 0; estimatedUncertaintyMM = nil
        geometry = OpeningGeometry(); openingTracker.reset(); opening3D.reset(); partialOpening.reset(); positionTracker.reset()
        latestTrackedOpening = nil; openingDetected = false; openingDetectionConfidence = 0
        openingTrackingStability = 0; openingObservationCount = 0; liveWidthMM = nil; liveHeightMM = nil
        live3DPointCount = 0; depthFrameCount = 0; accepted3DFrameCount = 0
        lastEdgePointCounts = (0,0,0,0); partialVerticalPointCount = 0; partialHorizontalPointCount = 0
        pipelineState = "Positie zoeken - maatvoering uitgeschakeld"
        positionLockProgress = 0
        positionLocked = false
        positionState = "Zoek vaste positie van de sparing"
        positionSideLocks = OpeningSideLocks(left: false, right: false, top: false, bottom: false)
        openingValidationScore = 0
        openingValidationState = "Opening nog niet gevalideerd"
        boundaryRefinementMM = 0
        boundaryRefinementSidesMM = (0, 0, 0, 0)
        boundaryRefinementFound = (false, false, false, false)
        boundaryRefinementEvidence = (0, 0, 0, 0)
        sessionEvent = "Actief - geen stop geregistreerd"
        userRequestedStop = false
        lastFrameWallClock = Date()
        startWatchdog()
        isRunning = true
    }

    func stop() {
        userRequestedStop = true
        watchdogTask?.cancel()
        watchdogTask = nil
        session.pause()
        isRunning = false
        pipelineState = "Scan gestopt door gebruiker"
        sessionEvent = "Handmatig gestopt"
    }

    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(750))
                guard let self else { return }
                guard self.isRunning, !self.userRequestedStop else { continue }

                let silentFor = Date().timeIntervalSince(self.lastFrameWallClock)
                if silentFor > 2.0 {
                    self.sessionEvent = String(format: "Frame-stilstand %.1fs - sessie herstart", silentFor)
                    self.pipelineState = "AR-frame stilgevallen - automatisch hervatten"

                    let configuration = ARWorldTrackingConfiguration()
                    configuration.worldAlignment = .gravity
                    configuration.environmentTexturing = .none
        configuration.planeDetection = [.vertical]
                    if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                        configuration.frameSemantics.insert(.sceneDepth)
                    }
                    if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                        configuration.sceneReconstruction = .mesh
                    }
                    self.session.run(configuration, options: [])
                    self.lastFrameWallClock = Date()
                }
            }
        }
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
            if latestTrackedOpening == nil { pipelineState = "Positie zoeken - 3D-randen verzamelen" }
            return
        }

        let lock = positionTracker.add(lines: measurement.boundaryLines)
        positionSideLocks = lock.sides
        live3DPointCount = measurement.verticalPointCount + measurement.horizontalPointCount

        let seedLines = measurement.boundaryLines
        let seedValidation = OpeningDepthValidator.validate(
            frame: frame,
            lines: seedLines
        )

        let refinement: OpeningBoundaryRefinement
        if lock.isLocked && !seedValidation.isOpening {
            refinement = OpeningBoundaryRefiner.refine(frame: frame, seed: seedLines)
        } else {
            refinement = OpeningBoundaryRefinement(
                lines: seedLines,
                score: seedValidation.score,
                expansionMetres: 0,
                leftMetres: 0,
                rightMetres: 0,
                topMetres: 0,
                bottomMetres: 0,
                leftFound: false, rightFound: false, topFound: false, bottomFound: false,
                leftEvidence: 0, rightEvidence: 0, topEvidence: 0, bottomEvidence: 0
            )
        }

        let validation = OpeningDepthValidator.validate(
            frame: frame,
            lines: refinement.lines
        )
        openingValidationScore = validation.score
        boundaryRefinementMM = Double(refinement.expansionMetres * 1000)
        boundaryRefinementSidesMM = (
            Double(refinement.leftMetres * 1000),
            Double(refinement.rightMetres * 1000),
            Double(refinement.topMetres * 1000),
            Double(refinement.bottomMetres * 1000)
        )
        boundaryRefinementFound = (
            refinement.leftFound,
            refinement.rightFound,
            refinement.topFound,
            refinement.bottomFound
        )
        boundaryRefinementEvidence = (
            refinement.leftEvidence,
            refinement.rightEvidence,
            refinement.topEvidence,
            refinement.bottomEvidence
        )

        // A geometric line lock is not yet a physical opening lock.
        // Each of the four sides must independently prove a physical boundary.
        let physicalSideCount = [
            refinement.leftFound,
            refinement.rightFound,
            refinement.topFound,
            refinement.bottomFound
        ].filter { $0 }.count
        let physicalSideProgress = Double(physicalSideCount) / 4.0
        let minimumBoundaryEvidence = 0.55
        let allPhysicalSidesProven =
            refinement.leftFound && refinement.leftEvidence >= minimumBoundaryEvidence &&
            refinement.rightFound && refinement.rightEvidence >= minimumBoundaryEvidence &&
            refinement.topFound && refinement.topEvidence >= minimumBoundaryEvidence &&
            refinement.bottomFound && refinement.bottomEvidence >= minimumBoundaryEvidence

        // Stable world-space lines contribute 60%, individually proven physical
        // boundaries 30%, and opening-depth validation the final 10%.
        positionLockProgress = min(
            1.0,
            lock.progress * 0.6 + physicalSideProgress * 0.3 + validation.score * 0.1
        )
        positionLocked = lock.isLocked && allPhysicalSidesProven && validation.isOpening

        if validation.isOpening && allPhysicalSidesProven {
            openingValidationState = "Opening + 4 fysieke randen bevestigd"
        } else if validation.isOpening {
            openingValidationState = "Diepte klopt, fysieke randen nog bewijzen"
        } else if refinement.expansionMetres > 0 {
            openingValidationState = "Randen naar buiten gecorrigeerd, opening nog niet bevestigd"
        } else {
            openingValidationState = "Vier lijnen stabiel, opening nog niet bevestigd"
        }

        // Position first: dimensions stay hidden until the physical opening
        // frame itself is stable in ARKit world space.
        liveWidthMM = nil
        liveHeightMM = nil
        estimatedUncertaintyMM = nil

        if positionLocked {
            positionState = "Positie vast in 3D + opening bevestigd"
            pipelineState = "Positie vergrendeld - maatvoering nog uit"
            NotificationCenter.default.post(name: .sparingsmeterBoundaryLines, object: refinement.lines)
        } else if lock.isLocked {
            positionState = "4/4 stabiel - fysieke randen \(physicalSideCount)/4"
            pipelineState = "Nog geen lock: fysieke sparingsranden bewijzen"
            NotificationCenter.default.post(name: .sparingsmeterBoundaryLines, object: refinement.lines)
        } else {
            positionState = "Positie stabiliseren \(Int(lock.progress * 100))%"
            pipelineState = "Positie zoeken - blijf langs dezelfde sparing bewegen"
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
        guard opening3D.measurement != nil else { return }
        if !positionLocked {
            pipelineState = "Positie zoeken - Vision en LiDAR combineren"
        }
    }
}

extension Notification.Name {
    static let sparingsmeterDebugPoints = Notification.Name("nl.brebo.sparingsmeter.debugPoints")
    static let sparingsmeterAcceptedDebugPoints = Notification.Name("nl.brebo.sparingsmeter.acceptedDebugPoints")
    static let sparingsmeterBoundaryLines = Notification.Name("nl.brebo.sparingsmeter.boundaryLines")
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
        configuration.planeDetection = [.vertical]
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
        configuration.planeDetection = [.vertical]
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
            self.lastFrameWallClock = Date()
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
