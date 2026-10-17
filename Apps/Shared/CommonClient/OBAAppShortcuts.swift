//
//  OBAAppShortcuts.swift
//  App
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import AppIntents
import OBAKit

/// The app's App Shortcuts, for the intents OBAKit defines.
///
/// This lives in the app target, not OBAKit: the metadata processor drops an
/// `AppShortcutsProvider` compiled into a Swift package, so Siri and Shortcuts
/// would lose both shortcuts. `AppDelegate` hands the type to OBAKit through
/// `AppConfig.appShortcutsProvider` so it can refresh the bookmark parameter.
///
/// Phrases are localized by `AppShortcuts.strings`, keyed by the English phrase
/// with `${applicationName}` / `${bookmark}` tokens, in this directory's
/// `.lproj`s: the strings must sit in the bundle that contains this provider
/// (and its `Metadata.appintents`). Changing an English phrase changes its key,
/// so update every locale's `AppShortcuts.strings` in the same commit.
nonisolated struct OBAAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TrackBookmarkIntent(),
            phrases: [
                "Track \(\.$bookmark) with \(.applicationName)",
                "Track \(.applicationName) bookmark",
                "Start \(.applicationName) Live Activity"
            ],
            shortTitle: LocalizedStringResource("track_bookmark_intent.short_title", defaultValue: "Track bookmark", table: "AppIntents", bundle: #bundle),
            systemImageName: "bell"
        )
        AppShortcut(
            intent: NextDeparturesIntent(),
            phrases: [
                "When is my next \(\.$bookmark) in \(.applicationName)",
                "Next departures for \(\.$bookmark) in \(.applicationName)",
                "When is my next bus in \(.applicationName)",
                "Do I have time to catch the bus with \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("next_departures_intent.short_title", defaultValue: "Next departures", table: "AppIntents", bundle: #bundle),
            systemImageName: "clock"
        )
    }
}
