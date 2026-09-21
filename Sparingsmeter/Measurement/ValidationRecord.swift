import Foundation

struct ValidationRecord: Codable, Sendable, Equatable {
    let timestamp: Date
    let deviceModel: String
    let measuredWidthMM: Double
    let referenceWidthMM: Double
    let errorMM: Double
    let distanceEstimateMM: Double?
    let pointCount: Int
    let fitResidualMM: Double
}
