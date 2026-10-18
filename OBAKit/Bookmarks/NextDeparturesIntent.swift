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
/// On iOS 26 the answer also appears as an interactive card, opened through
/// `NextDeparturesCardIntent` (#1554). The spoken answer and the `String` this
/// returns are the same on every OS, so saved shortcuts are unaffected.
///
/// Strings come from `AppIntents.strings`; see `TrackBookmarkIntent` for why.
public struct NextDeparturesIntent: AppIntent {
    public static let title = LocalizedStringResource("next_departures_intent.title", defaultValue: "Next Departures", table: "AppIntents")
    public static let description = IntentDescription(LocalizedStringResource("next_departures_intent.description", defaultValue: "Hear when a bookmarked trip departs next.", table: "AppIntents"))
    public static let openAppWhenRun = false

    public init() {}

    @Parameter(title: LocalizedStringResource("bookmark_entity.parameter_title", defaultValue: "Bookmark", table: "AppIntents"))
    public var bookmark: BookmarkEntity?

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let bookmarkID = try await resolveBookmarkID()
        // Through the store, so the card can show this outcome without fetching it again.
        let outcome = await NextDeparturesStore.shared.load(bookmarkID: bookmarkID)
        let text = NextDeparturesSummary.text(for: outcome, now: Date())

        // Both branches return `IntentResultContainer<String, Never, Never,
        // IntentDialog>`, which is what lets one `perform()` serve every OS.
        // Siri speaks the full sentence; beside the card, it shows only the
        // short supporting line, so the screen doesn't repeat the card.
        if #available(iOS 26.0, *) {
            return .result(
                value: text,
                opensIntent: NextDeparturesCardIntent(bookmarkID: bookmarkID),
                dialog: IntentDialog(full: "\(text)", supporting: Self.title)
            )
        }
        return .result(value: text, dialog: "\(text)")
    }

    /// The bookmark to answer for: the parameter, else the only trip bookmark.
    /// `nil` when there is none, which the store answers with `noBookmarks` or,
    /// without the app group, `noRegion`.
    @MainActor
    private func resolveBookmarkID() async throws -> UUID? {
        if let bookmark {
            return bookmark.id
        }

        let candidates = try await BookmarkEntityQuery().suggestedEntities()
        switch candidates.count {
        case 0:
            return nil
        case 1:
            return candidates[0].id
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
    /// How long a departures fetch may take. Siri and Shortcuts wait on the
    /// answer, and the card's Refresh button shouldn't spin for URLSession's
    /// 60-second default before saying the load failed (#1554).
    nonisolated static let requestTimeout: TimeInterval = 10

    /// The session fetches use unless a test injects another: request and
    /// resource timeouts both capped at `requestTimeout`.
    nonisolated static let defaultDataLoader: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = requestTimeout
        return URLSession(configuration: configuration)
    }()

    let userDefaults: UserDefaults
    let bundledRegionsFilePath: String?
    let apiKey: String?
    let appVersion: String
    let dataLoader: URLDataLoader

    init(userDefaults: UserDefaults, bundledRegionsFilePath: String?, apiKey: String?, appVersion: String, dataLoader: URLDataLoader = NextDeparturesLoader.defaultDataLoader) {
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
            departures: departures.map(NextDeparturesSummary.Departure.init(arrivalDeparture:))
        )
    }
}
