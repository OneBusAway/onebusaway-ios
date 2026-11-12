//
//  ManageBookmarksHost.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit
import OBAKitCore

/// Presents `ManageBookmarksAndGroupsViewController` from the Bookmarks sheet:
/// reordering bookmarks, and adding, renaming and deleting groups.
///
/// The Bookmarks tab presents the same controller from its Edit button through
/// `viewRouter.present(_:from:)`, which needs a presenting `UIViewController`
/// the sheet doesn't have. Same shape as `BookmarkEditorHost`.
struct ManageBookmarksHost: UIViewControllerRepresentable {
    let application: Application
    /// Fires when bookmarks or groups changed, so the list can rebuild.
    let onChange: () -> Void
    /// Fires when the controller's Close is tapped.
    let onClose: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        Self.makeNavigationController(application: application, delegate: context.coordinator)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange, onClose: onClose)
    }

    /// Internal factory seam, for the reason `MoreSheetHost.makeNavigationController`
    /// gives: tests can inspect the wiring without a `UIHostingController`.
    static func makeNavigationController(
        application: Application,
        delegate: ModalDelegate & ManageBookmarksDelegate
    ) -> UINavigationController {
        UINavigationController(rootViewController: ManageBookmarksAndGroupsViewController(
            application: application,
            delegate: delegate
        ))
    }

    /// The controller's delegates are UIKit-era protocols, so the representable's
    /// coordinator adopts them and forwards to the closures.
    @MainActor
    final class Coordinator: NSObject, ModalDelegate, ManageBookmarksDelegate {
        private let onChange: () -> Void
        private let onClose: () -> Void

        init(onChange: @escaping () -> Void, onClose: @escaping () -> Void) {
            self.onChange = onChange
            self.onClose = onClose
        }

        func dismissModalController(_ controller: UIViewController) {
            onClose()
        }

        func manageBookmarksReloadData(_ controller: ManageBookmarksAndGroupsViewController) {
            onChange()
        }
    }
}
