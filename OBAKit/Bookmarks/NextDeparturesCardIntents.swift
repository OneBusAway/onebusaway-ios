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
// `NextDeparturesCardIntent`, which hands the system the snippet. Opening a
// second intent, rather than returning the snippet itself, keeps
// `NextDeparturesIntent`'s result type the same on every OS, so its phrases
// and the shortcuts people have saved keep working and keep outputting a
// `String`.
//
// None of these are Shortcuts actions of their own (`isDiscoverable`), and
// each takes the bookmark as a plain id string rather than a `BookmarkEntity`,
// so `perform()` still runs, and can say the bookmark is unavailable, if it
// has been deleted since the card appeared.
//
// Titles reuse Next Departures' strings where the action is Next Departures;
// see `TrackBookmarkIntent` for why they name the `AppIntents` table.

/// Hands the system the Next Departures card.
@available(iOS 26.0, *)
struct NextDeparturesCardIntent: AppIntent {
    static let title = LocalizedStringResource("next_departures_intent.title", defaultValue: "Next Departures", table: "AppIntents")
    static let isDiscoverable = false
    static let supportedModes: IntentModes = .background

    @Parameter(title: LocalizedStringResource("bookmark_entity.parameter_title", defaultValue: "Bookmark", table: "AppIntents"))
    var bookmarkID: String

    init() {}

    /// `nil` for the answer about no bookmark.
    init(bookmarkID: UUID?) {
        self.bookmarkID = bookmarkID?.uuidString ?? ""
    }

    func perform() async throws -> some IntentResult & ShowsSnippetIntent {
        .result(snippetIntent: NextDeparturesSnippetIntent(bookmarkID: bookmarkID))
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

    @Parameter(title: LocalizedStringResource("bookmark_entity.parameter_title", defaultValue: "Bookmark", table: "AppIntents"))
    var bookmarkID: String

    init() {}

    init(bookmarkID: String) {
        self.bookmarkID = bookmarkID
    }

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let outcome: NextDeparturesSummary.Outcome
        switch NextDeparturesCardKey(bookmarkID) {
        case .bookmark(let id):
            outcome = await NextDeparturesStore.shared.outcome(bookmarkID: id)
        case .noBookmark:
            outcome = await NextDeparturesStore.shared.outcome(bookmarkID: nil)
        case .invalid:
            outcome = .bookmarkUnavailable
        }

        let model = NextDeparturesCardModel(
            outcome: outcome,
            now: Date(),
            liveActivitiesEnabled: ActivityAuthorizationInfo().areActivitiesEnabled
        )
        let bookmarkID = bookmarkID
        let trackedBookmark: BookmarkEntity? = {
            guard case .bookmark(let id) = NextDeparturesCardKey(bookmarkID), let name = model.bookmarkName else { return nil }
            return BookmarkEntity(id: id, name: name)
        }()

        return .result(view: NextDeparturesCardView(model: model) {
            if model.showsRefresh {
                Button(intent: RefreshNextDeparturesIntent(bookmarkID: bookmarkID)) {
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

    @Parameter(title: LocalizedStringResource("bookmark_entity.parameter_title", defaultValue: "Bookmark", table: "AppIntents"))
    var bookmarkID: String

    init() {}

    init(bookmarkID: String) {
        self.bookmarkID = bookmarkID
    }

    func perform() async throws -> some IntentResult {
        if case .bookmark(let id) = NextDeparturesCardKey(bookmarkID) {
            _ = await NextDeparturesStore.shared.refresh(bookmarkID: id)
        }
        return .result()
    }
}

/// How the card intents read their `bookmarkID` string: empty for the answer
/// about no bookmark, otherwise a bookmark's UUID.
nonisolated enum NextDeparturesCardKey: Equatable {
    case bookmark(UUID)
    case noBookmark
    /// Not a UUID. Only another shortcut passing its own value could cause it.
    case invalid

    init(_ bookmarkID: String) {
        if bookmarkID.isEmpty {
            self = .noBookmark
        } else if let id = UUID(uuidString: bookmarkID) {
            self = .bookmark(id)
        } else {
            self = .invalid
        }
    }
}
