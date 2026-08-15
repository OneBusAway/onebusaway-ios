//
//  BookmarkEditorHost.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit
import OBAKitCore

/// Presents `EditBookmarkViewController` from a SwiftUI sheet.
///
/// The Bookmarks tab reaches the same editor through `viewRouter.present(_:from:)`,
/// which needs a presenting `UIViewController` the sheet doesn't have. Both
/// paths build the controller with `BookmarkActions.makeBookmarkEditor`.
struct BookmarkEditorHost: UIViewControllerRepresentable {
    let application: Application
    let bookmark: Bookmark
    /// Fires when the editor is dismissed, whether saved or cancelled, so the
    /// list can rebuild.
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let coordinator = context.coordinator
        return BookmarkActions(application: application)
            .makeBookmarkEditor(for: bookmark, delegate: coordinator)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    /// `BookmarkEditorDelegate` is a UIKit-era protocol, so the representable's
    /// coordinator adopts it and forwards both outcomes to one closure.
    @MainActor
    final class Coordinator: NSObject, BookmarkEditorDelegate {
        private let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func bookmarkEditorCancelled(_ viewController: UIViewController) {
            onFinish()
        }

        func bookmarkEditor(_ viewController: UIViewController, editedBookmark bookmark: Bookmark, isNewBookmark: Bool) {
            onFinish()
        }
    }
}
