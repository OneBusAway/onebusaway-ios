//
//  MoreSheetHost.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit
import OBAKitCore

/// UIKit wiring wrapper: presents the existing `MoreViewController` inside
/// a `UINavigationController` so its `navigationItem` bar buttons render
/// correctly when reached via `AppSheetRoute.more`.
///
/// Deliberately minimal — a future SwiftUI `MoreView` will replace this
/// wrapper in `AppSheetViewFactory` without touching the coordinator or
/// route enum.
struct MoreSheetHost: UIViewControllerRepresentable {
    let application: Application
    /// Closes the sheet. The other index sheets have a Close button; this one
    /// could only be swiped away. Unused as the home sheet's More tab
    /// (`isHomeSheetTab`), which has no sheet of its own to close.
    var onClose: () -> Void = {}

    func makeUIViewController(context: Context) -> UINavigationController {
        Self.makeNavigationController(
            application: application,
            onClose: context.environment.isHomeSheetTab ? nil : onClose
        )
    }

    // `MoreViewController` reads `application` and its stores directly, so
    // nothing SwiftUI-side changes over the sheet's lifetime.
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) { }

    /// Internal factory seam: mirrors what `makeUIViewController` does but
    /// takes no `Context`, so tests can drive the wiring without going
    /// through `UIHostingController` (whose lifecycle doesn't fire the
    /// representable's `makeUIViewController` synchronously in a unit-test
    /// process). Kept `internal` deliberately — production code must go
    /// through `makeUIViewController`.
    static func makeNavigationController(application: Application, onClose: (() -> Void)? = {}) -> UINavigationController {
        let more = MoreViewController(application: application)
        // Beside Settings, at the trailing edge: Contact Us holds the leading
        // slot. Closed through the sheet stack, which owns the sheet, rather
        // than by UIKit dismissing it out from under SwiftUI.
        if let onClose {
            let close = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { _ in onClose() })
            more.navigationItem.rightBarButtonItems = [close] + (more.navigationItem.rightBarButtonItems ?? [])
        }
        more.showsSheetGlass = true
        return UINavigationController(rootViewController: more)
    }
}
