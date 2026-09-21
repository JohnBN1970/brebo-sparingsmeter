import Foundation

enum MeasurementSource: String, Codable, Sendable {
    /// Rechtstreeks uit sensors / gereconstrueerde sensorwaarnemingen.
    case measured
    /// Door beeld-/geometrieherkenning gevonden kenmerk.
    case detected
    /// Uit andere gegevens berekende waarde.
    case calculated
    /// Expliciet door gebruiker gekozen of ingevoerd.
    case user
}
