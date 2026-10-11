//
//  TrackBookmarkIntent.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import AppIntents
import OBAKitCore

/// Starts a Live Activity for a trip bookmark via Shortcuts.
///
/// The intent only queues the bookmark id in the app-group defaults and opens
/// the app (`openAppWhenRun`). `Application` starts the activity on the
/// existing Track path once arrivals load — ActivityKit is not called from
/// the intent, and no `Activity` is captured into a `Task`. See #1222.
///
/// Not `nonisolated`: `@Parameter` property wrappers are incompatible with a
/// nonisolated AppIntent type on this SDK (entity/query/provider stay opted out).
///
/// Every user-facing string on the intent surface names an explicit key in
/// OBAKit's `AppIntents.strings`. Shortcuts and Siri resolve them out of
/// process from the metadata `appintentsmetadataprocessor` writes into
/// OBAKit.framework, which records only key, table, and default value; the
/// lookup bundle is implicitly the one holding that metadata. The processor
/// rejects any bundle but the module's own (`#bundle`; `.forClass` fails the
/// build with "requires 'LocalizedStringResource' to use the main bundle").
/// A separate table keeps `scripts/extract_strings`, which regenerates
/// `Localizable.strings` from `OBALoc` calls only, from deleting these keys.
struct TrackBookmarkIntent: AppIntent {
    static let title = LocalizedStringResource("track_bookmark_intent.title", defaultValue: "Track Bookmark", table: "AppIntents", bundle: #bundle)
    static let description = IntentDescription(LocalizedStringResource("track_bookmark_intent.description", defaultValue: "Start a Live Activity for a bookmarked trip.", table: "AppIntents", bundle: #bundle))
    static let openAppWhenRun = true

    @Parameter(title: LocalizedStringResource("bookmark_entity.parameter_title", defaultValue: "Bookmark", table: "AppIntents", bundle: #bundle))
    var bookmark: BookmarkEntity

    func perform() async throws -> some IntentResult {
        guard let suite = Bundle.main.appGroup,
              let defaults = UserDefaults(suiteName: suite) else {
            Logger.error("Track Bookmark Shortcut: app group UserDefaults unavailable; cannot queue a Live Activity.")
            return .result()
        }
        LiveActivityShortcutRequest.store(bookmark.id, userDefaults: defaults)
        return .result()
    }
}

/// App Entity types are extracted off the main actor; OBAKit defaults to `@MainActor`.
nonisolated struct BookmarkEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("bookmark_entity.type_name", defaultValue: "Bookmark", table: "AppIntents", bundle: #bundle)
    )
    static let defaultQuery = BookmarkEntityQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

nonisolated struct BookmarkEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [BookmarkEntity] {
        tripBookmarkEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [BookmarkEntity] {
        tripBookmarkEntities()
    }

    /// Trip bookmarks in the current region only. A whole-stop bookmark has
    /// no single route to Track; an out-of-region trip bookmark never gets
    /// arrivals loaded, so offering it would queue a request that cannot start.
    private func tripBookmarkEntities() -> [BookmarkEntity] {
        guard let suite = Bundle.main.appGroup,
              let defaults = UserDefaults(suiteName: suite) else { return [] }
        let store = UserDefaultsStore(userDefaults: defaults)
        let regionID = defaults.object(forKey: BookmarkIntentMapping.regionIdentifierUserDefaultsKey) as? Int
        return BookmarkIntentMapping.entities(from: store.bookmarks, regionIdentifier: regionID)
    }
}

nonisolated enum BookmarkIntentMapping {
    static let regionIdentifierUserDefaultsKey = RegionsService.currentRegionIdentifierUserDefaultsKey

    static func entities(from bookmarks: [Bookmark], regionIdentifier: Int?) -> [BookmarkEntity] {
        bookmarks.filter { $0.isTripBookmark && $0.regionIdentifier == regionIdentifier }.map {
            BookmarkEntity(id: $0.id, name: $0.name)
        }
    }
}

/// Exports this module's App Intents so the app target can include them.
/// Without an `AppIntentsPackage` chain, `appintentsmetadataprocessor` never
/// indexes intents compiled into OBAKit, and Shortcuts would not see Track.
nonisolated public struct OBAKitAppIntentsPackage: AppIntentsPackage {}

/// Phrases are localized by `AppShortcuts.strings`, keyed by the English phrase
/// with `${applicationName}` / `${bookmark}` tokens, in OBAKit's `.lproj`s:
/// the strings must sit in the bundle that contains this provider (and its
/// `Metadata.appintents`), not the app's. Changing an English phrase changes
/// its key, so update every locale's `AppShortcuts.strings` in the same commit.
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
