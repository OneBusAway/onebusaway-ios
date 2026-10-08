//
//  StopProblemView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The "Report a Problem" form for a stop: pick a problem, optionally comment,
/// choose whether to share location, send. Failures keep the form up with the
/// rider's input intact and show the error `send` throws, so `send` should
/// throw it already classified; success hands off to `onSent`.
///
/// Reads the share-location preference through `@AppStorage`, so the host must
/// apply `.defaultAppStorage(application.userDefaults)`.
struct StopProblemView: View {
    /// The key predates this view; it's kept so riders' saved choice carries over.
    private static let shareLocationKey = "StopProblemViewController.shareLocationForStopProblemReporting"

    let send: (_ code: StopProblemCode, _ comment: String?, _ shareLocation: Bool) async throws -> Void
    let onSent: () -> Void

    @AppStorage(Self.shareLocationKey) private var shareLocation = true
    @State private var code = StopProblemCode.allCases[0]
    @State private var comment = ""
    @State private var error: Error?
    /// Holds the rider on the form while a send is in flight; the old
    /// full-screen HUD did the same, and leaving would orphan the outcome.
    @State private var isSending = false

    private var commentsTitle: String { OBALoc("stop_problem_controller.comments_section.section_title", value: "Additional comments (optional)", comment: "The section header to a free-form comments field that the user does not have to add text to in order to submit this form.") }

    var body: some View {
        Form {
            Section {
                Picker(
                    OBALoc("stop_problem_controller.problem_section.row_label", value: "Pick one:", comment: "Title label for the 'choose a problem type' row."),
                    selection: $code
                ) {
                    ForEach(StopProblemCode.allCases, id: \.self) { code in
                        Text(code.userFriendlyStringValue).tag(code)
                    }
                }
            } header: {
                Text(OBALoc("stop_problem_controller.problem_section.section_title", value: "What seems to be the problem?", comment: "Title of the first section in the Stop Problem Controller."))
            }

            Section {
                TextField("", text: $comment, axis: .vertical)
                    .lineLimit(3...8)
                    .accessibilityLabel(commentsTitle)
            } header: {
                Text(commentsTitle)
            }

            Section {
                Toggle(
                    OBALoc("stop_problem_controller.location_section.switch_title", value: "Share location", comment: "Title of the Share Location switch on stop problem controller"),
                    isOn: $shareLocation
                )
            } header: {
                Text(OBALoc("stop_problem_controller.location_section.section_title", value: "Share your location?", comment: "Title of the Share Location section in the Stop Problem Controller."))
            } footer: {
                Text(OBALoc("stop_problem_controller.location_section.section_footer", value: "Sharing your location can help your transit agency fix this problem.", comment: "Footer text of the Share Location section in the Stop Problem Controller"))
            }

            Section {
                TaskButton(action: submit) {
                    Text(OBALoc("stop_problem_controller.send_button", value: "Send Message", comment: "The 'send' button that actually sends along the problem report."))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .errorAlert(error: $error, buttonTitle: Strings.dismiss)
        .navigationBarBackButtonHidden(isSending)
    }

    private func submit() async {
        isSending = true
        defer { isSending = false }
        do {
            try await send(code, String.nilifyBlankValue(comment.strip()), shareLocation)
            onSent()
        } catch {
            self.error = error
        }
    }
}
