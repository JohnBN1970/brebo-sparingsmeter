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
        private var anchors: [AnchorEntity] = []
        private let maximumVisibleBatches = 18

        func attach(to view: ARView) {
            self.view = view
            observer = NotificationCenter.default.addObserver(
                forName: .sparingsmeterDebugPoints, object: nil, queue: .main
            ) { [weak self] note in
                guard let points = note.object as? [SIMD3<Float>] else { return }
                self?.show(points)
            }
        }

        private func show(_ points: [SIMD3<Float>]) {
            guard let view, !points.isEmpty else { return }
            let anchor = AnchorEntity(world: .zero)
            let mesh = MeshResource.generateSphere(radius: 0.006)
            let material = SimpleMaterial(color: .systemYellow, roughness: 0.25, isMetallic: false)

            for point in points {
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
        }
    }
}
