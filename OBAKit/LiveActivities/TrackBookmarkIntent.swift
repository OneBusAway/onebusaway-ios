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
/// the app (`openAppWhenRun`). `BookmarksViewController` starts the activity
/// on the existing Track path once arrivals load — ActivityKit is not called
/// from the intent, and no `Activity` is captured into a `Task`. See #1222.
struct TrackBookmarkIntent: AppIntent {
    static var title: LocalizedStringResource = "Track Bookmark"
    static var description = IntentDescription("Start a Live Activity for a bookmarked trip.")
    static var openAppWhenRun = true

    @Parameter(title: "Bookmark")
    var bookmark: BookmarkEntity

    func perform() async throws -> some IntentResult {
        guard let suite = Bundle.main.appGroup,
              let defaults = UserDefaults(suiteName: suite) else {
            return .result()
        }
        LiveActivityShortcutRequest.store(bookmark.id, userDefaults: defaults)
        return .result()
    }
}

struct BookmarkEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Bookmark")
    static var defaultQuery = BookmarkEntityQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct BookmarkEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [BookmarkEntity] {
        tripBookmarkEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [BookmarkEntity] {
        tripBookmarkEntities()
    }

    /// Trip bookmarks only. A whole-stop bookmark has no single route to Track.
    private func tripBookmarkEntities() -> [BookmarkEntity] {
        guard let suite = Bundle.main.appGroup,
              let defaults = UserDefaults(suiteName: suite) else { return [] }
        let store = UserDefaultsStore(userDefaults: defaults)
        return BookmarkIntentMapping.entities(from: store.bookmarks)
    }
}

enum BookmarkIntentMapping {
    static func entities(from bookmarks: [Bookmark]) -> [BookmarkEntity] {
        bookmarks.filter(\.isTripBookmark).map {
            BookmarkEntity(id: $0.id, name: $0.name)
        }
    }
}

struct OBAAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TrackBookmarkIntent(),
            phrases: [
                "Track \(.applicationName) bookmark",
                "Start \(.applicationName) Live Activity"
            ],
            shortTitle: "Track bookmark",
            systemImageName: "bell"
        )
    }
}
