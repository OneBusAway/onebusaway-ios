//
//  BookmarkPinning.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

// MARK: - Menu item

/// The pin/unpin context-menu item, shared by the Bookmarks tab and the home
/// sheet's bookmarks section.
///
/// Defined once so both surfaces show the same verb and glyph — a user who pins
/// from the tab and unpins from the home sheet shouldn't meet two vocabularies
/// for one piece of state.
struct BookmarkPinButton: View {
    let isPinned: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            if isPinned {
                Label(Strings.unpinBookmark, systemImage: "pin.slash")
            } else {
                Label(Strings.pinBookmark, systemImage: "pin")
            }
        }
    }
}

// MARK: - Row indicator

/// The glyph marking a pinned bookmark in a list row.
///
/// `accessibilityHidden` on purpose: both bookmark cells flatten themselves with
/// `.accessibilityElement(children: .ignore)` and build one label, so the pinned
/// state is announced through `BookmarkRowViewModel.accessibilityLabel(base:)`
/// instead of as a stray element.
struct BookmarkPinIndicator: View {
    var body: some View {
        Image(systemName: "pin.fill")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }
}

// MARK: - Accessibility

extension BookmarkRowViewModel {
    /// `base` with the pinned state appended, for cells that collapse themselves
    /// into a single accessibility element.
    func accessibilityLabel(base: String) -> String {
        guard isPinned else { return base }
        return "\(base), \(Strings.pinnedBookmarkAccessibilityLabel)"
    }
}

// MARK: - Strings

extension Strings {

    static let pinBookmark = OBALoc(
        "bookmarks_controller.context_menu.pin",
        value: "Pin",
        comment: "Context menu action that pins a bookmark to the top of the home sheet's bookmarks section."
    )

    static let unpinBookmark = OBALoc(
        "bookmarks_controller.context_menu.unpin",
        value: "Unpin",
        comment: "Context menu action that removes a bookmark's pin, returning it to the normal ordering."
    )

    static let pinnedBookmarkAccessibilityLabel = OBALoc(
        "bookmarks_controller.pinned.a11y_label",
        value: "Pinned",
        comment: "VoiceOver suffix announcing that a bookmark row is pinned."
    )
}
