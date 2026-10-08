//
//  VehicleProblemView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// What the rider filled in on the vehicle problem form.
struct VehicleProblemInput {
    let code: TripProblemCode
    let isOnVehicle: Bool
    let vehicleID: String?
    let comment: String?
    let shareLocation: Bool
}

/// The "Report a Problem" form for a trip: pick a problem, say whether you're
/// aboard (and which vehicle), choose whether to share location, optionally
/// comment, send. Failures keep the form up with the rider's input intact;
/// success hands off to `onSent`.
///
/// Reads the share-location preference through `@AppStorage`, so the host must
/// apply `.defaultAppStorage(application.userDefaults)`.
struct VehicleProblemView: View {
    /// The key predates this view; it's kept so riders' saved choice carries over.
    private static let shareLocationKey = "VehicleProblemViewController.shareLocationForVehicleProblemReporting"

    let send: (VehicleProblemInput) async throws -> Void
    let onSent: () -> Void

    @AppStorage(Self.shareLocationKey) private var shareLocation = true
    @State private var code = TripProblemCode.allCases[0]
    @State private var isOnVehicle = false
    @State private var vehicleID: String
    @State private var comment = ""
    @State private var error: Error?

    init(vehicleID: String?, send: @escaping (VehicleProblemInput) async throws -> Void, onSent: @escaping () -> Void) {
        self.send = send
        self.onSent = onSent
        self._vehicleID = State(initialValue: vehicleID ?? "")
    }

    private var vehicleIDTitle: String { OBALoc("vehicle_problem_controller.on_vehicle_section.vehicle_id_title", value: "Vehicle ID", comment: "Title of the vehicle ID text field in the Vehicle Problem Controller.") }

    private var commentsTitle: String { OBALoc("vehicle_problem_controller.comments_section.section_title", value: "Additional comments (optional)", comment: "The section header to a free-form comments field that the user does not have to add text to in order to submit this form.") }

    var body: some View {
        Form {
            Section {
                Picker(
                    OBALoc("vehicle_problem_controller.problem_section.row_label", value: "Pick one", comment: "Title label for the 'choose a problem type' row."),
                    selection: $code
                ) {
                    ForEach(TripProblemCode.allCases, id: \.self) { code in
                        Text(code.userFriendlyStringValue).tag(code)
                    }
                }
            } header: {
                Text(OBALoc("vehicle_problem_controller.problem_section.section_title", value: "What seems to be the problem?", comment: "Title of the first section in the Vehicle Problem Controller."))
            }

            Section {
                Toggle(
                    OBALoc("vehicle_problem_controller.on_vehicle_section.switch_title", value: "On the vehicle", comment: "Title of the 'on the vehicle' switch in the Vehicle Problem Controller."),
                    isOn: $isOnVehicle
                )
                LabeledContent(vehicleIDTitle) {
                    TextField(vehicleIDTitle, text: $vehicleID)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            } header: {
                Text(OBALoc("vehicle_problem_controller.on_vehicle_section.section_title", value: "Are you on this vehicle?", comment: "Title of the 'on the vehicle' section in the Vehicle Problem Controller."))
            }

            Section {
                Toggle(
                    OBALoc("vehicle_problem_controller.location_section.switch_title", value: "Share location", comment: "Title of the Share Location switch"),
                    isOn: $shareLocation
                )
            } header: {
                Text(OBALoc("vehicle_problem_controller.location_section.section_title", value: "Share your location?", comment: "Title of the Share Location section in the Vehicle Problem Controller."))
            } footer: {
                Text(OBALoc("vehicle_problem_controller.location_section.section_footer", value: "Sharing your location can help your transit agency fix this problem.", comment: "Footer text of the Share Location section in the Vehicle Problem Controller"))
            }

            Section {
                TextField("", text: $comment, axis: .vertical)
                    .lineLimit(3...8)
                    .accessibilityLabel(commentsTitle)
            } header: {
                Text(commentsTitle)
            }

            Section {
                TaskButton(action: submit) {
                    Text(OBALoc("vehicle_problem_controller.send_button", value: "Send Message", comment: "The 'send' button that actually sends along the problem report."))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .errorAlert(error: $error, buttonTitle: Strings.dismiss)
    }

    private func submit() async {
        let input = VehicleProblemInput(
            code: code,
            isOnVehicle: isOnVehicle,
            vehicleID: String.nilifyBlankValue(vehicleID.strip()),
            comment: String.nilifyBlankValue(comment.strip()),
            shareLocation: shareLocation
        )
        do {
            try await send(input)
            onSent()
        } catch {
            self.error = ErrorClassifier.classify(error, regionName: nil)
        }
    }
}
