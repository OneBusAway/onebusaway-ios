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
/// the `AppIntents.strings` table. Shortcuts and Siri resolve them out of
/// process from the app's `Metadata.appintents` (OBAKit's is merged into it),
/// which records only key, table, and default value; the lookup bundle is
/// implicitly the one holding that metadata, so the table ships in the app,
/// from `Apps/Shared/CommonClient`. In-process lookups use the default bundle,
/// `.main`, to read the same table; `#bundle` would name OBAKit's resource
/// bundle, which doesn't have it. (The processor rejects any explicit bundle,
/// even `.main`: "requires 'LocalizedStringResource' to use the main bundle".)
/// A separate table keeps `scripts/extract_strings`, which regenerates
/// `Localizable.strings` from `OBALoc` calls only, from deleting these keys.
public struct TrackBookmarkIntent: AppIntent {
    public static let title = LocalizedStringResource("track_bookmark_intent.title", defaultValue: "Track Bookmark", table: "AppIntents")
    public static let description = IntentDescription(LocalizedStringResource("track_bookmark_intent.description", defaultValue: "Start a Live Activity for a bookmarked trip.", table: "AppIntents"))
    public static let openAppWhenRun = true

    public init() {}

    @Parameter(title: LocalizedStringResource("bookmark_entity.parameter_title", defaultValue: "Bookmark", table: "AppIntents"))
    public var bookmark: BookmarkEntity

    public func perform() async throws -> some IntentResult {
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
nonisolated public struct BookmarkEntity: AppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("bookmark_entity.type_name", defaultValue: "Bookmark", table: "AppIntents")
    )
    public static let defaultQuery = BookmarkEntityQuery()

    public var id: UUID
    public var name: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

nonisolated public struct BookmarkEntityQuery: EntityQuery {
    public init() {}

    public func entities(for identifiers: [UUID]) async throws -> [BookmarkEntity] {
        tripBookmarkEntities().filter { identifiers.contains($0.id) }
    }

    public func suggestedEntities() async throws -> [BookmarkEntity] {
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
