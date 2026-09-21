import SwiftUI

struct CalibrationView: View {
    @ObservedObject var store: CalibrationStore
    let liveMeasuredMM: Double?

    @State private var referenceText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Live meting") {
                    if let liveMeasuredMM {
                        LabeledContent(
                            "Gemeten",
                            value: String(format: "%.1f mm", liveMeasuredMM)
                        )
                    } else {
                        Text("Nog geen bruikbare live maat.")
                    }
                }

                Section("Bekende referentiemaat") {
                    TextField("bijv. 1000.0", text: $referenceText)
                        .keyboardType(.decimalPad)

                    Button("Kalibratiepunt opslaan") {
                        guard
                            let measured = liveMeasuredMM,
                            let reference = Double(referenceText.replacingOccurrences(of: ",", with: "."))
                        else { return }

                        store.add(measuredMM: measured, referenceMM: reference)
                        referenceText = ""
                    }
                    .disabled(liveMeasuredMM == nil)
                }

                Section("Kalibratie") {
                    LabeledContent("Punten", value: "\(store.samples.count)")
                    LabeledContent("Schaal", value: String(format: "%.8f", store.profile.scale))
                    LabeledContent("Offset", value: String(format: "%.2f mm", store.profile.offsetMM))

                    if store.profile.validationRMSErrorMM.isFinite {
                        LabeledContent(
                            "Validatiefout",
                            value: String(format: "%.2f mm RMS", store.profile.validationRMSErrorMM)
                        )

                        if store.profile.isValidatedForProduction {
                            Label("Kalibratie binnen +/-2 mm", systemImage: "checkmark.seal")
                        } else {
                            Label("Nog buiten +/-2 mm", systemImage: "exclamationmark.triangle")
                        }
                    } else {
                        Text("Minimaal 3 referentiematen nodig.")
                    }
                }

                Section {
                    Button("Kalibratie wissen", role: .destructive) {
                        store.reset()
                    }
                }
            }
            .navigationTitle("Kalibreren")
        }
    }
}
