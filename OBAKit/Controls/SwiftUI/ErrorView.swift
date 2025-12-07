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
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.red)
            Text(headline)
                .font(.headline)
            Text(error.localizedDescription)
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
#endif
