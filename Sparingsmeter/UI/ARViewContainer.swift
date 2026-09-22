import ARKit
import RealityKit
import SwiftUI
import UIKit

struct ARViewContainer: UIViewRepresentable {
    let controller: ARScanController

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.session = controller.arSession()
        view.automaticallyConfigureSession = false
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    final class Coordinator {
        private weak var view: ARView?
        private var observer: NSObjectProtocol?
        private var acceptedObserver: NSObjectProtocol?
        private var anchors: [AnchorEntity] = []

        // Debug rendering must stay lightweight. The previous implementation
        // created thousands of RealityKit ModelEntities per second and could
        // make iOS terminate the app under memory/GPU pressure.
        private let maximumVisibleBatches = 6
        private let yellowMesh = MeshResource.generateSphere(radius: 0.004)
        private let greenMesh = MeshResource.generateSphere(radius: 0.006)
        private let yellowMaterial = SimpleMaterial(color: .systemYellow, roughness: 0.25, isMetallic: false)
        private let greenMaterial = SimpleMaterial(color: .systemGreen, roughness: 0.25, isMetallic: false)
        private var lastYellowRender = Date.distantPast
        private var lastGreenRender = Date.distantPast
        private let minimumRenderInterval: TimeInterval = 0.30

        func attach(to view: ARView) {
            self.view = view
            observer = NotificationCenter.default.addObserver(
                forName: .sparingsmeterDebugPoints, object: nil, queue: .main
            ) { [weak self] note in
                guard let points = note.object as? [SIMD3<Float>] else { return }
                self?.show(points, accepted: false)
            }
            acceptedObserver = NotificationCenter.default.addObserver(
                forName: .sparingsmeterAcceptedDebugPoints, object: nil, queue: .main
            ) { [weak self] note in
                guard let points = note.object as? [SIMD3<Float>] else { return }
                self?.show(points, accepted: true)
            }
        }

        private func show(_ points: [SIMD3<Float>], accepted: Bool) {
            guard let view, !points.isEmpty else { return }

            let now = Date()
            if accepted {
                guard now.timeIntervalSince(lastGreenRender) >= minimumRenderInterval else { return }
                lastGreenRender = now
            } else {
                guard now.timeIntervalSince(lastYellowRender) >= minimumRenderInterval else { return }
                lastYellowRender = now
            }

            // Keep only a small representative sample per update.
            let cap = accepted ? 35 : 45
            let step = max(1, points.count / cap)
            let sampled = Array(points.enumerated().compactMap { index, point in
                index.isMultiple(of: step) ? point : nil
            }.prefix(cap))

            let anchor = AnchorEntity(world: .zero)
            let mesh = accepted ? greenMesh : yellowMesh
            let material = accepted ? greenMaterial : yellowMaterial

            for point in sampled {
                let dot = ModelEntity(mesh: mesh, materials: [material])
                dot.position = point
                anchor.addChild(dot)
            }

            view.scene.addAnchor(anchor)
            anchors.append(anchor)

            while anchors.count > maximumVisibleBatches {
                let old = anchors.removeFirst()
                view.scene.removeAnchor(old)
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            if let acceptedObserver { NotificationCenter.default.removeObserver(acceptedObserver) }
        }
    }
}
