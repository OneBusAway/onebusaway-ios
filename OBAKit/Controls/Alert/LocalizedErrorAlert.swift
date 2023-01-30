//
//  LocalizedErrorAlert.swift
//  OBAKit
//
//  Created by Alan Chu on 1/20/23.
//

import SwiftUI
import OBAKitCore

struct LocalizedAlertError: LocalizedError {
    let underlyingError: Error
    let errorDescription: String?
    let recoverySuggestion: String?

    init?(error: Error?) {
        guard let error else {
            return nil
        }

        underlyingError = error

        if let localizedError = error as? LocalizedError {
            errorDescription = localizedError.errorDescription ?? localizedError.localizedDescription
            recoverySuggestion = localizedError.recoverySuggestion
        } else {
            errorDescription = error.localizedDescription
            recoverySuggestion = nil
        }
    }
}

// MARK: - SwiftUI
extension View {
    /// Presents an error as an alert. The error should be `LocalizedError`, but will also display non-localized error.
    func errorAlert(error: Binding<Error?>, buttonTitle: String = Strings.ok) -> some View {
        let localizedAlertError = LocalizedAlertError(error: error.wrappedValue)

        return alert(isPresented: .constant(localizedAlertError != nil), error: localizedAlertError) { _ in
            Button(buttonTitle) {
                error.wrappedValue = nil
            }
        } message: { error in
            Text(error.recoverySuggestion ?? "")
        }
    }
}

#if DEBUG
private struct PreviewError: Error, LocalizedError {
    var errorDescription: String? = "Preview error description"
    var recoverySuggestion: String? = "Preview recovery suggestion"
}

private enum NotLocalizedError: Error {
    case somethingWentWrong
}

struct ErrorAlertPreview: View {
    @State var error: Error?

    var body: some View {
        VStack(spacing: 16) {
            Button("make error") {
                error = PreviewError()
            }

            Button("make no-localization error") {
                error = NotLocalizedError.somethingWentWrong
            }

            Button("make Cocoa error") {
                error = CocoaError(.coderReadCorrupt)
            }
        }
        .buttonStyle(.bordered)
        .errorAlert(error: $error)
    }
}

struct ErrorAlert_Preview: PreviewProvider {
    static var previews: some View {
        ErrorAlertPreview()
    }
}

#endif
