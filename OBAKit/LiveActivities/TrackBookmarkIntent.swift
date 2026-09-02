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
struct TrackBookmarkIntent: AppIntent {
    static let title: LocalizedStringResource = "Track Bookmark"
    static let description = IntentDescription("Start a Live Activity for a bookmarked trip.")
    static let openAppWhenRun = true

    @Parameter(title: "Bookmark")
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
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Bookmark")
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

nonisolated struct OBAAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TrackBookmarkIntent(),
            phrases: [
                "Track \(\.$bookmark) with \(.applicationName)",
                "Track \(.applicationName) bookmark",
                "Start \(.applicationName) Live Activity"
            ],
            shortTitle: "Track bookmark",
            systemImageName: "bell"
        )
    }
}
