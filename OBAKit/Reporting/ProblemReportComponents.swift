//
//  ProblemReportComponents.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// A full-width form button that swaps its title for a spinner and disables
/// itself while `isSubmitting` is true, so a slow request can't be sent twice.
struct SubmitButton: View {
    let title: String
    let isSubmitting: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isSubmitting {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Text(title).frame(maxWidth: .infinity)
            }
        }
        .disabled(isSubmitting)
    }
}

/// Submission state shared by the stop and vehicle problem forms: runs the
/// send, tracks progress, and turns a failure into an alert message while
/// leaving the rider's input in place.
@Observable
final class ProblemReportSubmission {
    private(set) var isSubmitting = false
    var errorMessage: String?

    /// `nil` for a blank field, so an untouched optional field is omitted from
    /// the report rather than sent as whitespace.
    static func trimmedOrNil(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Returns `true` when `send` succeeded.
    func run(_ send: () async throws -> Void) async -> Bool {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await send()
            return true
        } catch {
            errorMessage = ErrorClassifier.classify(error, regionName: nil).localizedDescription
            return false
        }
    }
}

extension View {
    /// Presents `submission.errorMessage` as a dismissable error alert.
    func problemReportErrorAlert(_ submission: ProblemReportSubmission) -> some View {
        alert(
            Strings.error,
            isPresented: Binding(
                get: { submission.errorMessage != nil },
                set: { if !$0 { submission.errorMessage = nil } }
            )
        ) {
            Button(Strings.dismiss, role: .cancel) {}
        } message: {
            Text(submission.errorMessage ?? "")
        }
    }
}
