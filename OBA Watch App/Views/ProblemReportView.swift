import SwiftUI
import OBASharedCore
import CoreLocation

enum ProblemReportMode {
    case stop(stopID: OBAStopID)
    case trip(tripID: String, vehicleID: String?, stopID: OBAStopID?)
}

struct ProblemReportView: View {
    let mode: ProblemReportMode
    @State private var code: String = ""
    @State private var comment: String = ""
    @State private var includeLocation: Bool = true
    @State private var userOnVehicle: Bool = false
    @State private var serviceDate: Date = Date()
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            switch mode {
            case .stop(let stopID):
                Section("Stop \(stopID)") {
                    TextField("Problem code", text: $code)
                    TextField("Comment (optional)", text: $comment)
                    Toggle("Include location", isOn: $includeLocation)
                }
            case .trip(let tripID, _, let stopID):
                Section("Trip \(tripID)") {
                    TextField("Problem code", text: $code)
                    TextField("Comment (optional)", text: $comment)
                    Toggle("On vehicle", isOn: $userOnVehicle)
                    DatePicker("Service date", selection: $serviceDate, displayedComponents: .date)
                    if let stopID {
                        Text("Stop \(stopID)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundColor(.red)
                }
            }
            Section {
                Button(isSubmitting ? "Submitting..." : "Submit") {
                    Task { await submit() }
                }
                .disabled(isSubmitting || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("Report Problem")
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            switch mode {
            case .stop(let stopID):
                let location = includeLocation ? WatchAppState.shared.currentLocation : nil
                let report = OBAStopProblemReport(stopID: stopID, code: code, comment: comment.isEmpty ? nil : comment, location: location)
                try await WatchAppState.shared.apiClient.submitStopProblem(report)
            case .trip(let tripID, let vehicleID, let stopID):
                let report = OBATripProblemReport(tripID: tripID, serviceDate: serviceDate, vehicleID: vehicleID, stopID: stopID, code: code, comment: comment.isEmpty ? nil : comment, userOnVehicle: userOnVehicle, location: WatchAppState.shared.currentLocation)
                try await WatchAppState.shared.apiClient.submitTripProblem(report)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
