//
//  StopDetailSheetHost.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit
import OBAKitCore

/// UIKit wiring wrapper: presents the existing `StopViewController` inside a
/// `UINavigationController` so its `navigationItem` bar buttons render correctly
/// when reached via `AppSheetRoute.stopDetails`.
///
/// Deliberately minimal — a future SwiftUI stop-detail view will replace this
/// wrapper in `AppSheetViewFactory` without touching the coordinator or route enum.
struct StopDetailSheetHost: UIViewControllerRepresentable {
    let application: Application
    let stopID: Stop.ID

    func makeUIViewController(context: Context) -> UINavigationController {
        // `dismiss` clears the stacked `.sheet(item:)` binding, which the
        // coordinator observes to pop this route — the same path the drag-down
        // gesture takes, so storage stays in sync.
        let dismiss = context.environment.dismiss
        return Self.makeNavigationController(application: application, stopID: stopID, onClose: { dismiss() })
    }

    // `StopPageViewController` reads `application`, `stopID`, and stores directly,
    // so nothing SwiftUI-side changes over the sheet's lifetime.
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) { }

    /// Internal factory seam mirroring `MoreSheetHost`: builds the same
    /// controller hierarchy without a `Context`, so tests can drive the wiring
    /// without going through `UIHostingController`.
    static func makeNavigationController(
        application: Application,
        stopID: Stop.ID,
        onClose: @escaping () -> Void
    ) -> UINavigationController {
        let stopPageController = StopPageViewController(application: application, stopID: stopID)
        let closeButton = UIBarButtonItem(
            primaryAction: UIAction(title: Strings.close) { _ in onClose() }
        )
        for state: UIControl.State in [.normal, .highlighted] {
            closeButton.setTitleTextAttributes([.foregroundColor: UIColor.label], for: state)
        }
        stopPageController.navigationItem.leftBarButtonItem = closeButton
        return UINavigationController(rootViewController: stopPageController)
    }
}
