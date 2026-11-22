//
//  TransitAlertSheetHost.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit
import OBAKitCore

/// UIKit wiring wrapper: presents `TransitAlertDetailViewController` inside
/// a `UINavigationController` so its navigation bar and close action render
/// cleanly when reached via `AppSheetRoute.transitAlert`.
struct TransitAlertSheetHost: UIViewControllerRepresentable {
    let alert: TransitAlertViewModel
    var onClose: () -> Void = {}

    func makeUIViewController(context: Context) -> UINavigationController {
        Self.makeNavigationController(
            alert: alert,
            onClose: onClose
        )
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) { }

    /// Internal factory seam: mirrors what `makeUIViewController` does but
    /// takes no `Context`, so tests can drive the wiring without going
    /// through `UIHostingController`.
    static func makeNavigationController(
        alert: TransitAlertViewModel,
        onClose: (() -> Void)? = nil
    ) -> UINavigationController {
        let detail = TransitAlertDetailViewController(alert, onClose: onClose)
        if let onClose {
            detail.navigationItem.rightBarButtonItem = UIBarButtonItem(
                systemItem: .close,
                primaryAction: UIAction { _ in onClose() }
            )
        }
        return UINavigationController(rootViewController: detail)
    }
}
