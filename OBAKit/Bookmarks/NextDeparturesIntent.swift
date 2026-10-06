//
//  NextDeparturesIntent.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import AppIntents
import OBAKitCore

/// Answers "when is my next bus?" from Siri or Shortcuts without opening the app (#456).
///
/// Takes the same `BookmarkEntity` as Track Bookmark — trip bookmarks in the
/// current region — so Siri offers one list for both. The parameter is optional
/// so "when is my next bus" works with a single bookmark and can say why it
/// cannot answer with none, instead of Siri prompting for an empty list.
///
/// Not `nonisolated`, for the same `@Parameter` reason as `TrackBookmarkIntent`.
/// The `AppIntent` conformance still leaves members nonisolated, so `perform`
/// opts into the main actor to use `NextDeparturesLoader`.
///
/// Strings come from `AppIntents.strings`; see `TrackBookmarkIntent` for why.
struct NextDeparturesIntent: AppIntent {
    static let title = LocalizedStringResource("next_departures_intent.title", defaultValue: "Next Departures", table: "AppIntents", bundle: #bundle)
    static let description = IntentDescription(LocalizedStringResource("next_departures_intent.description", defaultValue: "Hear when a bookmarked trip departs next.", table: "AppIntents", bundle: #bundle))
    static let openAppWhenRun = false

    @Parameter(title: LocalizedStringResource("bookmark_entity.parameter_title", defaultValue: "Bookmark", table: "AppIntents", bundle: #bundle))
    var bookmark: BookmarkEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let outcome = try await resolveOutcome()
        let text = NextDeparturesSummary.text(for: outcome, now: Date())
        return .result(value: text, dialog: "\(text)")
    }

    @MainActor
    private func resolveOutcome() async throws -> NextDeparturesSummary.Outcome {
        guard let loader = NextDeparturesLoader(bundle: .main) else {
            Logger.error("Next Departures Shortcut: app group UserDefaults unavailable.")
            return .noRegion
        }

        if let bookmark {
            return await loader.outcome(bookmarkID: bookmark.id)
        }

        let candidates = try await BookmarkEntityQuery().suggestedEntities()
        switch candidates.count {
        case 0:
            return .noBookmarks
        case 1:
            return await loader.outcome(bookmarkID: candidates[0].id)
        default:
            let prompt = OBALoc("next_departures_intent.choose_bookmark", value: "Which bookmark?", comment: "Siri asks which trip bookmark to report departures for when the user has more than one.")
            throw $bookmark.needsValueError("\(prompt)")
        }
    }
}

/// Fetches one trip bookmark's departures from the app-group suite, the way
/// `WidgetDataProvider` does. The intent has no route to `Application`, and the
/// system may launch the app in the background just to run it.
struct NextDeparturesLoader {
    let userDefaults: UserDefaults
    let bundledRegionsFilePath: String?
    let apiKey: String?
    let appVersion: String
    let dataLoader: URLDataLoader

    init(userDefaults: UserDefaults, bundledRegionsFilePath: String?, apiKey: String?, appVersion: String, dataLoader: URLDataLoader = URLSession.shared) {
        self.userDefaults = userDefaults
        self.bundledRegionsFilePath = bundledRegionsFilePath
        self.apiKey = apiKey
        self.appVersion = appVersion
        self.dataLoader = dataLoader
    }

    init?(bundle: Bundle) {
        guard let suite = bundle.appGroup,
              let defaults = UserDefaults(suiteName: suite) else { return nil }
        self.init(
            userDefaults: defaults,
            bundledRegionsFilePath: bundle.bundledRegionsFilePath,
            apiKey: bundle.restServerAPIKey,
            appVersion: bundle.appVersion
        )
    }

    func outcome(bookmarkID: UUID) async -> NextDeparturesSummary.Outcome {
        guard let region = ResolvedRegionStore(userDefaults: userDefaults).region(bundledRegionsFilePath: bundledRegionsFilePath) else {
            return .noRegion
        }

        guard
            let bookmark = UserDefaultsStore(userDefaults: userDefaults).bookmarks.first(where: { $0.id == bookmarkID }),
            bookmark.regionIdentifier == region.regionIdentifier,
            bookmark.isTripBookmark,
            let routeShortName = bookmark.routeShortName,
            let headsign = bookmark.tripHeadsign
        else {
            return .bookmarkUnavailable
        }

        guard let apiKey else {
            Logger.error("Next Departures Shortcut: no REST API key in Info.plist.")
            return .loadFailed(bookmarkName: bookmark.name)
        }

        let service = RESTAPIService.standalone(
            region: region,
            apiKey: apiKey,
            appVersion: appVersion,
            uuid: UserUUID.value(in: userDefaults),
            dataLoader: dataLoader
        )

        // No entry means the fetch failed; an empty array means nothing is coming.
        guard let departures = await BookmarkArrivalsLoader().departuresByBookmark(for: [bookmark], using: service)[bookmark.id] else {
            return .loadFailed(bookmarkName: bookmark.name)
        }

        return .departures(
            bookmarkName: bookmark.name,
            routeShortName: routeShortName,
            headsign: headsign,
            dates: departures.map(\.arrivalDepartureDate)
        )
    }
}
