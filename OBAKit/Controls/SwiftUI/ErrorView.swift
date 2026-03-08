//
//  ErrorView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// A reusable error view that displays an error with an optional retry button.
struct ErrorView: View {
    let headline: String
    let error: Error
    var regionName: String?
    var onRetry: (() -> Void)?

    var body: some View {
        let classified = ErrorClassifier.classify(error, regionName: regionName)

        VStack(spacing: 16) {
            Image(systemName: iconName(for: classified))
                .font(.largeTitle)
                .foregroundStyle(.red)
            Text(headline)
                .font(.headline)
            Text(classified.localizedDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let onRetry {
                Button(Strings.retry) {
                    onRetry()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    /// Returns an appropriate SF Symbol name based on the classified error type.
    private func iconName(for classified: Error) -> String {
        guard let apiError = classified as? APIError else {
            return "exclamationmark.triangle"
        }

        switch apiError {
        case .cellularDataRestricted, .networkFailure:
            return "wifi.slash"
        case .serverError, .serverUnavailable:
            return "server.rack"
        case .captivePortal:
            return "lock.shield"
        default:
            return "exclamationmark.triangle"
        }
    }
}

// MARK: - Preview

#if DEBUG
private struct PreviewError: Error, LocalizedError {
    var errorDescription: String? = "The server returned an invalid response. Please check your network connection and try again."
}

#Preview("With Retry Button") {
    ErrorView(
        headline: "Unable to load schedule",
        error: PreviewError(),
        onRetry: { print("Retry tapped") }
    )
}

#Preview("Without Retry Button") {
    ErrorView(
        headline: "Something went wrong",
        error: PreviewError()
    )
}

#Preview("Server Unavailable") {
    ErrorView(
        headline: "Unable to load data",
        error: APIError.requestFailure(HTTPURLResponse()),
        regionName: "Puget Sound",
        onRetry: { print("Retry tapped") }
    )
}

#Preview("Cellular Data Restricted") {
    ErrorView(
        headline: "No Internet",
        error: APIError.cellularDataRestricted
    )
}
#endif
