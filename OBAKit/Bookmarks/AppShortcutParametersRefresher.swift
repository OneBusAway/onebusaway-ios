//
//  AppShortcutParametersRefresher.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import AppIntents
import Foundation
import OBAKitCore

/// Keeps the App Shortcuts' bookmark parameter list current: refreshes it on
/// creation, on every `.bookmarksDidChange`, and whenever `refresh()` is called.
///
/// The parameter list is process-wide, so `Application` creates one of these at
/// launch rather than in `init`. The unit-test host builds thousands of
/// `Application`s that never launch; each refresh there fails and logs a line.
@MainActor
final class AppShortcutParametersRefresher {

    /// The app's provider, from `AppConfig.appShortcutsProvider`.
    private let provider: any AppShortcutsProvider.Type

    /// Observes `NotificationCenter.default` because that is where
    /// `UserDefaultsStore` posts. Selector-based observation is auto-removed on
    /// dealloc, so no token/deinit is needed.
    init(provider: any AppShortcutsProvider.Type) {
        self.provider = provider
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(bookmarksDidChange),
            name: .bookmarksDidChange,
            object: nil
        )
        refresh()
    }

    /// `.bookmarksDidChange` may be posted off the main actor. The refresh is
    /// nonisolated, so it runs on the posting thread.
    @objc private nonisolated func bookmarksDidChange() {
        provider.updateAppShortcutParameters()
    }

    func refresh() {
        provider.updateAppShortcutParameters()
    }
}
