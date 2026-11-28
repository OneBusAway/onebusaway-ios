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

    /// The default action invoked to reload a widget kind. Overridden in tests to spy on
    /// reloads without invoking `WidgetCenter`.
    static var defaultReloadKind: (String) -> Void = { WidgetCenter.shared.reloadTimelines(ofKind: $0) }

    /// The default action invoked to reload the Bookmark control. Overridden in tests
    /// to spy on reloads without invoking `ControlCenter`.
    static var defaultReloadControls: () -> Void = {
        ControlCenter.shared.reloadControls(ofKind: WidgetKinds.bookmarkControl)
    }

    private let reloadControls: () -> Void

    /// Invoked instead of `WidgetCenter` when set. Tests inject a spy here;
    /// production leaves it nil and reloads for real.
    private let reloadKind: ((String) -> Void)?

    /// Observes `NotificationCenter.default` because that is where
    /// `UserDefaultsStore` posts — see its `delete(bookmark:)`, `setPinned(_:for:)`,
    /// and `add(_:to:index:)`. Selector-based observation is auto-removed on
    /// dealloc, so no token/deinit is needed.
    init(reload: (() -> Void)? = nil, reloadControls: @escaping () -> Void = { BookmarkWidgetRefresher.defaultReloadControls() }) {
        self.reloadKind = reload.map { spy in { _ in spy() } }
        self.reloadControls = reloadControls

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(bookmarksDidChange),
            name: .bookmarksDidChange,
            object: nil
        )
    }

    init(reloadKind: @escaping (String) -> Void, reloadControls: @escaping () -> Void = { BookmarkWidgetRefresher.defaultReloadControls() }) {
        self.reloadKind = reloadKind
        self.reloadControls = reloadControls

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
            self.reloadControls()
        }
    }

    func reloadTimelines() {
        if let reloadKind {
            Self.reloadAllTimelines(using: reloadKind)
            return
        }
        Self.reloadAllTimelines()
    }

    /// Reloads the Control Center / Lock Screen / Action button Bookmark control.
    /// Called on bookmark edits and when the persisted region changes (#2006).
    func reloadBookmarkControls() {
        reloadControls()
    }

    static func reloadAllTimelines(
        using reloadKind: (String) -> Void = defaultReloadKind
    ) {
        for kind in WidgetKinds.timelineKinds {
            reloadKind(kind)
        }
    }
}
