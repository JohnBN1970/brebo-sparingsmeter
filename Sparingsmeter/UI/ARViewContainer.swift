import ARKit
import RealityKit
import SwiftUI

struct ARViewContainer: UIViewRepresentable {
    let controller: ARScanController

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.session = controller.arSession()
        view.automaticallyConfigureSession = false
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
