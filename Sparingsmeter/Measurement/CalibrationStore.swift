import Foundation

@MainActor
final class CalibrationStore: ObservableObject {
    @Published private(set) var samples: [CalibrationSample] = []
    @Published private(set) var profile = CalibrationProfile()

    func reset() {
        samples = []
        profile = CalibrationProfile()
    }

    func add(measuredMM: Double, referenceMM: Double) {
        guard measuredMM > 0, referenceMM > 0 else { return }
        samples.append(.init(measuredMM: measuredMM, referenceMM: referenceMM))
        if let solved = CalibrationSolver.solve(samples: samples) {
            profile = solved
        }
    }
}
