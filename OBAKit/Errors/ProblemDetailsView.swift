//
//  ProblemDetailsView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit
import OBAKitCore

/// The page behind an error toast's Details button. Written for the rider
/// first (what happened, in plain words) and for support second: a screenshot
/// of the "For support" section is everything support needs (#1582).
struct ProblemDetailsView: View {
    let report: ErrorReport
    var onDone: () -> Void
    var onContactSupport: () -> Void

    @State private var showsCopied = false
    @State private var revertTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(report.title)
                            .font(.title2.weight(.bold))
                            .accessibilityAddTraits(.isHeader)
                        Text(report.explanation)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                }

                Section {
                    supportRow(ErrorStrings.supportError, report.errorCode)
                    supportRow(ErrorStrings.supportTime, formattedDate)
                    if let regionName = report.regionName {
                        supportRow(ErrorStrings.supportRegion, regionName)
                    }
                    if let request = report.displayRequest {
                        supportRow(ErrorStrings.supportRequest, request)
                    }
                    supportRow(ErrorStrings.supportApp, report.appSummary)
                    supportRow(ErrorStrings.supportReference, report.reference)
                } header: {
                    Text(ErrorStrings.forSupport)
                } footer: {
                    Text(ErrorStrings.supportFooter)
                }

                Section {
                    Button(showsCopied ? ErrorStrings.copied : ErrorStrings.copyDetails, action: copy)
                    Button(ErrorStrings.contactSupport, action: onContactSupport)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(ErrorStrings.problemDetailsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.done, action: onDone)
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: report.shareText) {
                        Label(Strings.share, systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .onDisappear { revertTask?.cancel() }
    }

    private var formattedDate: String {
        report.date.formatted(
            .dateTime.month(.abbreviated).day().year().hour().minute().second(.twoDigits).timeZone()
        )
    }

    /// Label over value rather than side by side: the request URL and the
    /// error code are long, and wrap badly in a trailing column.
    private func supportRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func copy() {
        UIPasteboard.general.string = report.shareText
        AccessibilityAnnouncement.post(ErrorStrings.copied)
        showsCopied = true
        revertTask?.cancel()
        revertTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            showsCopied = false
        }
    }
}

/// Copy for the error toast and the Problem Details page.
enum ErrorStrings {
    static let details = OBALoc("error_toast.details", value: "Details", comment: "Button on an error notice that opens a page explaining the problem.")
    static let problemDetailsTitle = OBALoc("problem_details.title", value: "Problem Details", comment: "Title of the page that explains an error in detail.")
    static let forSupport = OBALoc("problem_details.for_support", value: "For Support", comment: "Section header above technical details meant for the support team.")
    static let supportFooter = OBALoc("problem_details.support_footer", value: "A screenshot of this page has everything support needs. No personal info or location is included.", comment: "Footer under the technical details on the problem details page.")
    static let supportError = OBALoc("problem_details.row.error", value: "Error", comment: "Row label: the technical error code.")
    static let supportTime = OBALoc("problem_details.row.time", value: "Time", comment: "Row label: when the error happened.")
    static let supportRegion = OBALoc("problem_details.row.region", value: "Region", comment: "Row label: the transit region in use.")
    static let supportRequest = OBALoc("problem_details.row.request", value: "Request", comment: "Row label: the web address of the request that failed.")
    static let supportApp = OBALoc("problem_details.row.app", value: "App", comment: "Row label: app version, iOS version and device model.")
    static let supportReference = OBALoc("problem_details.row.reference", value: "Ref", comment: "Row label: a short reference code for this error that the rider can quote to support. Abbreviation of 'Reference'.")
    static let copyDetails = OBALoc("problem_details.copy_details", value: "Copy Details", comment: "Button that copies the technical details of an error to the clipboard.")
    static let copied = CopyableValueRow.confirmation
    static let contactSupport = OBALoc("problem_details.contact_support", value: "Contact Support", comment: "Button that starts an email to the app's support team about an error.")
    static let supportEmailSubjectFmt = OBALoc("problem_details.email_subject_fmt", value: "%@ problem report %@", comment: "Subject of a support email about an error. The first value is the app name, the second a short reference code like 7F3K-Q2.")
}

#if DEBUG
#Preview {
    ProblemDetailsView(
        report: ErrorReport(
            error: APIError.requestFailure(HTTPURLResponse(
                url: URL(string: "https://api.pugetsound.onebusaway.org/api/where/trip-details/1_871781411.json?key=secret")!,
                statusCode: 429, httpVersion: nil, headerFields: nil
            )!),
            regionName: "Puget Sound",
            systemVersion: "26.1",
            deviceModel: "iPhone16,1"
        ),
        onDone: {}, onContactSupport: {}
    )
}
#endif
