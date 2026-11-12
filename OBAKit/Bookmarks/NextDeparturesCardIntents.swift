//
//  NextDeparturesCardIntents.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import ActivityKit
import AppIntents
import SwiftUI
import OBAKitCore

// The intents behind the Next Departures card on iOS 26 (#1554).
//
// `NextDeparturesIntent` answers as it always has, and on iOS 26 also opens
// `NextDeparturesCardIntent`, which hands the system the snippet.
// `NextDeparturesAtStopIntent` opens the same card for a stop. Opening a
// second intent, rather than returning the snippet itself, keeps
// `NextDeparturesIntent`'s result type the same on every OS, so its phrases
// and the shortcuts people have saved keep working and keep outputting a
// `String`.
//
// None of these are Shortcuts actions of their own (`isDiscoverable`), and
// each takes a plain `NextDeparturesCardKey` string rather than an entity, so
// `perform()` still runs, and can say the bookmark is unavailable, if it has
// been deleted since the card appeared.
//
// Titles reuse Next Departures' strings where the action is Next Departures;
// see `TrackBookmarkIntent` for why they name the `AppIntents` table.

/// Hands the system the Next Departures card.
@available(iOS 26.0, *)
struct NextDeparturesCardIntent: AppIntent {
    static let title = LocalizedStringResource("next_departures_intent.title", defaultValue: "Next Departures", table: "AppIntents")
    static let isDiscoverable = false
    static let supportedModes: IntentModes = .background

    /// A `NextDeparturesCardKey`, as a string.
    @Parameter(title: LocalizedStringResource("bookmark_entity.parameter_title", defaultValue: "Bookmark", table: "AppIntents"))
    var cardKey: String

    init() {}

    /// `nil` for the answer about no bookmark.
    init(bookmarkID: UUID?) {
        self.cardKey = bookmarkID?.uuidString ?? ""
    }

    /// The card for a stop, by its `StopEntity` id.
    init(stopEntityID: String) {
        self.cardKey = stopEntityID
    }

    func perform() async throws -> some IntentResult & ShowsSnippetIntent {
        .result(snippetIntent: NextDeparturesSnippetIntent(cardKey: cardKey))
    }
}

/// Draws the card. The system runs this again whenever it redraws the card,
/// including after one of its buttons runs, so it reads the outcome from
/// `NextDeparturesStore` and leaves fetching to the intents that do it.
@available(iOS 26.0, *)
struct NextDeparturesSnippetIntent: SnippetIntent {
    static let title = LocalizedStringResource("next_departures_intent.title", defaultValue: "Next Departures", table: "AppIntents")
    static let isDiscoverable = false
    static let supportedModes: IntentModes = .background

    /// A `NextDeparturesCardKey`, as a string.
    @Parameter(title: LocalizedStringResource("bookmark_entity.parameter_title", defaultValue: "Bookmark", table: "AppIntents"))
    var cardKey: String

    init() {}

    init(cardKey: String) {
        self.cardKey = cardKey
    }

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let key = NextDeparturesCardKey(cardKey)
        let outcome: NextDeparturesSummary.Outcome
        if case .invalid = key {
            outcome = .bookmarkUnavailable
        } else {
            outcome = await NextDeparturesStore.shared.outcome(key)
        }

        let model = NextDeparturesCardModel(
            outcome: outcome,
            now: Date(),
            liveActivitiesEnabled: ActivityAuthorizationInfo().areActivitiesEnabled
        )
        let cardKey = cardKey
        let trackedBookmark: BookmarkEntity? = {
            guard case .bookmark(let id) = key, let name = model.bookmarkName else { return nil }
            return BookmarkEntity(id: id, name: name)
        }()

        return .result(view: NextDeparturesCardView(model: model) {
            if model.showsRefresh {
                Button(intent: RefreshNextDeparturesIntent(cardKey: cardKey)) {
                    Label(Strings.refresh, systemImage: "arrow.clockwise")
                }
            }
            // The existing Track path: queue the bookmark and open the app,
            // which starts the Live Activity (#1222).
            if model.showsTrack, let trackedBookmark {
                Button(intent: TrackBookmarkIntent(bookmark: trackedBookmark)) {
                    Label(Self.trackTitle, systemImage: "bell")
                }
            }
        })
    }

    /// The Bookmarks list's "Track" action, already translated.
    private static var trackTitle: String {
        OBALoc("bookmarks_controller.context_menu.track_live_activity", value: "Track", comment: "Action to start a Live Activity for a specific bookmark")
    }
}

/// The card's Refresh button. Writes a fresh outcome to `NextDeparturesStore`;
/// the system then re-runs `NextDeparturesSnippetIntent`, which reads it.
@available(iOS 26.0, *)
struct RefreshNextDeparturesIntent: AppIntent {
    static let title = LocalizedStringResource("refresh_next_departures_intent.title", defaultValue: "Refresh Next Departures", table: "AppIntents")
    static let isDiscoverable = false
    static let supportedModes: IntentModes = .background

    /// A `NextDeparturesCardKey`, as a string.
    @Parameter(title: LocalizedStringResource("bookmark_entity.parameter_title", defaultValue: "Bookmark", table: "AppIntents"))
    var cardKey: String

    init() {}

    init(cardKey: String) {
        self.cardKey = cardKey
    }

    func perform() async throws -> some IntentResult {
        let key = NextDeparturesCardKey(cardKey)
        if key.isRefreshable {
            _ = await NextDeparturesStore.shared.refresh(key)
        }
        return .result()
    }
}

/// What a Next Departures card is about, and the `NextDeparturesStore` key
/// for its outcome. The card intents carry it as their `cardKey` string: empty
/// for the answer about no bookmark, a bookmark's UUID, or a `StopEntity` id
/// (`region_<r>_stop_<s>`), which can never parse as a UUID.
nonisolated enum NextDeparturesCardKey: Hashable, Sendable {
    case bookmark(UUID)
    /// A stop, by its `StopEntity` id (#1555).
    case stop(String)
    case noBookmark
    /// Neither. Only another shortcut passing its own value could cause it.
    case invalid

    init(_ cardKey: String) {
        if cardKey.isEmpty {
            self = .noBookmark
        } else if let id = UUID(uuidString: cardKey) {
            self = .bookmark(id)
        } else if StopEntityMapping.destination(fromIdentifier: cardKey) != nil {
            self = .stop(cardKey)
        } else {
            self = .invalid
        }
    }

    /// `nil` is the answer about no bookmark.
    init(bookmarkID: UUID?) {
        self = bookmarkID.map(Self.bookmark) ?? .noBookmark
    }

    /// Whether Refresh fetches for this card: a bookmark's or a stop's. The
    /// answer about no bookmark only changes in the app, and an invalid key
    /// has nothing to fetch.
    var isRefreshable: Bool {
        switch self {
        case .bookmark, .stop: true
        case .noBookmark, .invalid: false
        }
    }
}
