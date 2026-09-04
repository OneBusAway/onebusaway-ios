//
//  BookmarkWidgetRefresher.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import WidgetKit
import OBAKitCore

/// Reloads the bookmarks widget's timeline whenever the bookmark set changes,
/// from wherever it changed.
///
/// The widget renders bookmarks, so it goes stale the moment one is added,
/// deleted, or pinned. Five places in the app perform those writes — the
/// Bookmarks tab, the Bookmarks index sheet, the home sheet's bookmarks
/// section, Manage Bookmarks, and the stop page's add-bookmark flow — and
/// asking each of them to remember a widget call is how they came to disagree
/// in the first place. Observing the store's own `.bookmarksDidChange` instead
/// means a new surface gets this for free and cannot forget it.
///
/// Deliberately app-scoped: the widget must be refreshed even when the screen
/// that made the change has already gone away, so this outlives every view
/// controller. `Application` creates it eagerly for exactly that reason.
///
/// This is not the whole story for widget freshness — `BookmarksViewController`
/// separately reloads on each completed arrival-data batch, which is what keeps
/// the *times* current. This type covers changes to the bookmark set itself.
@MainActor
final class BookmarkWidgetRefresher {

    /// Matches the `kind` the widget extension registers under.
    static let widgetKind = "OBAWidget"

    /// Invoked instead of `WidgetCenter` when set. Tests inject a spy here;
    /// production leaves it nil and reloads for real.
    private let reload: (() -> Void)?

    /// Observes `NotificationCenter.default` because that is where
    /// `UserDefaultsStore` posts — see its `delete(bookmark:)`, `setPinned(_:for:)`,
    /// and `add(_:to:index:)`. Selector-based observation is auto-removed on
    /// dealloc, so no token/deinit is needed.
    init(reload: (() -> Void)? = nil) {
        self.reload = reload

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(bookmarksDidChange),
            name: .bookmarksDidChange,
            object: nil
        )
    }

    /// `.bookmarksDidChange` may be posted off the main actor, so hop rather than
    /// assuming the poster's isolation — the same pattern `MapStopsObserver` and
    /// `HomeBookmarksSectionModel` use for this notification.
    @objc private nonisolated func bookmarksDidChange() {
        Task { @MainActor in
            self.reloadTimelines()
        }
    }

    func reloadTimelines() {
        if let reload {
            reload()
            return
        }
        WidgetCenter.shared.reloadTimelines(ofKind: Self.widgetKind)
    }
}
