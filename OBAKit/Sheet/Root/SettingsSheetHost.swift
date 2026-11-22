//
//  SettingsSheetHost.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit
import OBAKitCore

/// UIKit wiring wrapper: presents `SettingsViewController` inside a
/// `UINavigationController` so its Done button can pop the route when reached
/// via `AppSheetRoute.settings`.
struct SettingsSheetHost: UIViewControllerRepresentable {
    let application: Application
    var onClose: () -> Void = {}

    func makeUIViewController(context: Context) -> UINavigationController {
        Self.makeNavigationController(
            application: application,
            onClose: onClose
        )
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) { }

    /// Internal factory seam: mirrors what `makeUIViewController` does but
    /// takes no `Context`, so tests can drive the wiring without going
    /// through `UIHostingController`.
    static func makeNavigationController(
        application: Application,
        onClose: (() -> Void)? = nil
    ) -> UINavigationController {
        let settings = SettingsViewController(application: application, onClose: onClose)
        return UINavigationController(rootViewController: settings)
    }
}
