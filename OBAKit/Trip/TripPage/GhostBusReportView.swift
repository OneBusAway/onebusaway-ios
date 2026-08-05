//
//  GhostBusReportView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Context shown read-only at the top of the ghost bus report sheet, so the
/// rider can confirm what they're reporting before they submit.
struct GhostBusReportContext {
    let routeAndHeadsign: String
    let stopName: String?
    let scheduledTime: Date?
    let vehicleID: String?
}

/// The "Report Ghost Bus" form: confirm the trip, say how long you waited,
/// optionally add detail, submit. Failures keep the sheet up with the rider's
/// input intact; success dismisses.
struct GhostBusReportView: View {
    let context: GhostBusReportContext
    let defaultShareLocation: Bool
    let submit: (_ waitDurationMinutes: Int, _ comment: String?, _ shareLocation: Bool) async throws -> Void
    let onDismiss: () -> Void

    static let waitChoices = [5, 10, 15, 20, 30]

    @State private var waitDurationMinutes = 15
    @State private var comment = ""
    @State private var shareLocation = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(
                        OBALoc("ghost_bus_report.context.route", value: "Route", comment: "Label for the route being reported on the ghost bus form."),
                        value: context.routeAndHeadsign
                    )
                    if let stopName = context.stopName {
                        LabeledContent(
                            OBALoc("ghost_bus_report.context.stop", value: "Stop", comment: "Label for the stop being reported on the ghost bus form."),
                            value: stopName
                        )
                    }
                    if let scheduledTime = context.scheduledTime {
                        LabeledContent(
                            OBALoc("ghost_bus_report.context.scheduled", value: "Scheduled", comment: "Label for the scheduled time on the ghost bus form."),
                            value: scheduledTime.formatted(date: .omitted, time: .shortened)
                        )
                    }
                    if let vehicleID = context.vehicleID {
                        LabeledContent(
                            OBALoc("ghost_bus_report.context.vehicle", value: "Vehicle", comment: "Label for the vehicle ID on the ghost bus form."),
                            value: vehicleID
                        )
                    }
                } header: {
                    Text(OBALoc("ghost_bus_report.context.header", value: "Reporting", comment: "Header over the trip summary on the ghost bus form."))
                }

                Section {
                    Picker(
                        OBALoc("ghost_bus_report.wait.label", value: "How long did you wait?", comment: "Label for the wait-duration picker on the ghost bus form."),
                        selection: $waitDurationMinutes
                    ) {
                        ForEach(Self.waitChoices, id: \.self) { minutes in
                            Text(minutes == 30
                                 ? OBALoc("ghost_bus_report.wait.thirty_plus", value: "30+ min", comment: "Longest wait-duration choice on the ghost bus form.")
                                 : String(format: OBALoc("ghost_bus_report.wait.minutes_fmt", value: "%d min", comment: "Wait-duration choice on the ghost bus form."), minutes))
                                .tag(minutes)
                        }
                    }
                } header: {
                    Text(OBALoc("ghost_bus_report.wait.header", value: "Past the scheduled time", comment: "Header over the wait-duration picker on the ghost bus form."))
                }

                Section {
                    TextField(
                        OBALoc("ghost_bus_report.comment.placeholder", value: "Anything else we should know? (optional)", comment: "Placeholder for the optional comment field on the ghost bus form."),
                        text: $comment,
                        axis: .vertical
                    )
                    .lineLimit(3...6)

                    Toggle(
                        OBALoc("ghost_bus_report.share_location", value: "Share my location", comment: "Toggle on the ghost bus form for including the rider's location with the report."),
                        isOn: $shareLocation
                    )
                }

                Section {
                    Button {
                        Task { await performSubmit() }
                    } label: {
                        if isSubmitting {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text(OBALoc("ghost_bus_report.submit", value: "Submit Report", comment: "Submit button on the ghost bus form."))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isSubmitting)
                } footer: {
                    Text(OBALoc("ghost_bus_report.footer", value: "Your report is anonymous and goes to the agency that runs this service.", comment: "Footer text under the submit button on the ghost bus form."))
                }
            }
            .navigationTitle(OBALoc("ghost_bus_report.title", value: "Report Ghost Bus", comment: "Title of the ghost bus report sheet."))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.cancel, action: onDismiss)
                }
            }
            .alert(
                OBALoc("ghost_bus_report.error.title", value: "Unable to Submit", comment: "Title of the ghost bus submission error alert."),
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button(Strings.dismiss, role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear { shareLocation = defaultShareLocation }
            .interactiveDismissDisabled(isSubmitting)
        }
    }

    private func performSubmit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
            try await submit(waitDurationMinutes, trimmed.isEmpty ? nil : trimmed, shareLocation)
            onDismiss()
        } catch let error as APIError {
            if case .requestFailure(let response) = error, response.statusCode == 422 {
                errorMessage = OBALoc("ghost_bus_report.error.already_reported", value: "It looks like this trip has already been reported from this device.", comment: "Error message when the server rejects a duplicate ghost bus report.")
            } else {
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
