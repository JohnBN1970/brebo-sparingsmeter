import SwiftUI

struct ScanView: View {
    @StateObject private var scanner = ARScanController()
    @StateObject private var calibration = CalibrationStore()
    @State private var showCalibration = false

    var body: some View {
        ZStack {
            ARViewContainer(controller: scanner)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                statusPanel
                diagnosticPanel
                Spacer()
                instructionPanel
                controls
            }
            .padding()
        }
        .background(.black)
        .sheet(isPresented: $showCalibration) {
            CalibrationView(
                store: calibration,
                liveMeasuredMM: scanner.liveWidthMM
            )
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SPARINGSMETER")
                    .font(.headline)
                Spacer()
                Text("\(Int(scanner.coverage * 100))% dekking")
                    .monospacedDigit()
            }

            if scanner.openingDetected {
                HStack(spacing: 12) {
                    Label(
                        "\(scanner.openingObservationCount) frames",
                        systemImage: "camera.viewfinder"
                    )
                    Spacer()
                    Text("\(Int(scanner.openingTrackingStability * 100))% vormvast")
                        .monospacedDigit()
                }
                .font(.caption)
            } else {
                Label("Zoek de volledige sparing in beeld", systemImage: "viewfinder")
                    .font(.caption)
            }

            if let width = scanner.liveWidthMM,
               let height = scanner.liveHeightMM {
                Divider()
                Text("Live sparingsmaat")
                    .font(.caption)
                Text(String(format: "%.0f x %.0f mm", width, height))
                    .font(.title2.bold())

                if let uncertainty = scanner.estimatedUncertaintyMM {
                    Text(String(format: "berekende onzekerheid +/- %.1f mm", uncertainty))
                        .font(.caption)
                }
            }

            switch scanner.quality {
            case .insufficientCoverage:
                Label("Blijf rustig langs de sparing bewegen", systemImage: "move.3d")
            case .uncertaintyTooHigh(let mm):
                Label(
                    String(format: "Nog onvoldoende nauwkeurig: +/- %.1f mm", mm),
                    systemImage: "exclamationmark.triangle"
                )
            case .ready(let mm):
                Label(
                    String(format: "Meting akkoord: +/- %.1f mm", mm),
                    systemImage: "checkmark.seal"
                )
            }

            if let size = scanner.geometry.productionSize {
                Divider()
                Text("Voorgestelde kozijnmaat")
                    .font(.caption)
                Text(String(format: "%.0f x %.0f mm", size.widthMM, size.heightMM))
                    .font(.title2.bold())
                Text("5 mm aftrek rondom")
                    .font(.caption)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var diagnosticPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(scanner.pipelineState)
                .font(.caption.bold())
            Text(
                "LiDAR \(scanner.depthFrameCount)f | 3D \(scanner.accepted3DFrameCount)f | punten L\(scanner.lastEdgePointCounts.left) R\(scanner.lastEdgePointCounts.right) B\(scanner.lastEdgePointCounts.top) O\(scanner.lastEdgePointCounts.bottom)"
            )
            .font(.caption2.monospaced())
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var instructionPanel: some View {
        Text("Geen punten aanwijzen. Houd eerst de hele sparing in beeld en beweeg daarna rustig langs alle vier zijden. Kijk ook schuin in de negge.")
            .font(.callout)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var controls: some View {
        HStack {
            Button(scanner.isRunning ? "Stop scan" : "Start scan") {
                scanner.isRunning ? scanner.stop() : scanner.start()
            }
            .buttonStyle(.borderedProminent)

            Button("Kalibreren") {
                showCalibration = true
            }
            .buttonStyle(.bordered)

            #if DEBUG
            Button("Testgeometrie") {
                scanner.injectFittedGeometryForDevelopment(
                    widthsMM: [1252, 1249, 1246],
                    heightsMM: [2212, 2210, 2208],
                    uncertaintyMM: 1.4
                )
            }
            .buttonStyle(.bordered)
            #endif
        }
    }
}
