//
//  TransitAlertViewModel.swift
//  OBAKitCore
//
//  Created by Alan Chu on 1/18/21.
//

/// Wraps `AgencyAlert` and `ServiceAlert` into a common view model for displaying alert details in-app.
public protocol TransitAlertViewModel {
    /// The closest matching localized title text for the specified `Locale`.
    func title(forLocale locale: Locale) -> String?

    /// The closest matching localized body text describing the alert in full detail for the specified `Locale`.
    func body(forLocale locale: Locale) -> String?

    /// The closest matching localized URL for the specified `Locale`.
    func url(forLocale locale: Locale) -> URL?
}

extension AgencyAlert: TransitAlertViewModel {
    // nop. already conforms to transitalertdata.
}
