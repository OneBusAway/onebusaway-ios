//
//  NextDeparturesSummary.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// What `NextDeparturesIntent` says. Pure, so the wording is testable without
/// App Intents, Siri, or the network.
nonisolated enum NextDeparturesSummary {
    static let maximumDepartures = 3

    nonisolated enum Outcome: Equatable {
        case noBookmarks
        case noRegion
        case bookmarkUnavailable
        case loadFailed(bookmarkName: String)
        /// `dates` may include departures that already left; `text` drops them.
        case departures(bookmarkName: String, routeShortName: String, headsign: String, dates: [Date])
    }

    static func text(for outcome: Outcome, now: Date) -> String {
        switch outcome {
        case .noBookmarks:
            return OBALoc("next_departures_intent.no_bookmarks", value: "You don't have any bookmarked trips. Bookmark a route at a stop first.", comment: "Siri response when the user asks for their next departures but has no trip bookmarks in the current region.")
        case .noRegion:
            return OBALoc("next_departures_intent.no_region", value: "Choose a transit region in the app first.", comment: "Siri response when the user asks for their next departures before the app knows their region.")
        case .bookmarkUnavailable:
            return OBALoc("next_departures_intent.bookmark_unavailable", value: "That bookmark isn't available in your current region.", comment: "Siri response when the requested bookmark was deleted or belongs to a different region.")
        case .loadFailed(let bookmarkName):
            let fmt = OBALoc("next_departures_intent.load_failed_fmt", value: "Couldn't load departures for %@. Check your connection and try again.", comment: "Siri response when departures could not be fetched. {Bookmark name}")
            return String(format: fmt, bookmarkName)
        case let .departures(bookmarkName, routeShortName, headsign, dates):
            if let sentence = departuresSentence(routeShortName: routeShortName, headsign: headsign, dates: dates, now: now) {
                return sentence
            }
            let fmt = OBALoc("next_departures_intent.no_departures_fmt", value: "No departures for %@ in the next hour.", comment: "Siri response when a bookmarked trip has no upcoming departures. {Bookmark name}")
            return String(format: fmt, bookmarkName)
        }
    }

    /// "550 to Seattle departs in 5 minutes. Then in 17 minutes and in 32 minutes."
    /// `nil` when nothing in `dates` is still to come.
    static func departuresSentence(routeShortName: String, headsign: String, dates: [Date], now: Date) -> String? {
        // Truncating division matches `ArrivalDeparture.temporalState`: anything
        // under a minute either side of `now` is "now", earlier is gone.
        let minutes = dates.sorted()
            .map { Int($0.timeIntervalSince(now) / 60) }
            .filter { $0 >= 0 }
            .prefix(maximumDepartures)

        guard let first = minutes.first else { return nil }

        let firstFmt = OBALoc("next_departures_intent.first_departure_fmt", value: "%1$@ to %2$@ departs %3$@.", comment: "Siri response naming the next departure. {Route short name} to {Headsign} departs {'now' or 'in X minutes'}.")
        let sentence = String(format: firstFmt, routeShortName, headsign, relativeTime(minutes: first))

        let later = minutes.dropFirst().map(relativeTime(minutes:))
        guard !later.isEmpty else { return sentence }

        let laterFmt = OBALoc("next_departures_intent.later_departures_fmt", value: "Then %@.", comment: "Siri response listing the departures after the next one. {List of 'in X minutes'}")
        let laterSentence = String(format: laterFmt, ListFormatter.localizedString(byJoining: later))
        // Not `sentence + " " + …`: Chinese runs sentences together after "。".
        let joinFmt = OBALoc("next_departures_intent.sentences_join_fmt", value: "%1$@ %2$@", comment: "Joins two complete Siri sentences: {first departure sentence} {later departures sentence}. Use the language's separator between sentences; Chinese uses none.")
        return String(format: joinFmt, sentence, laterSentence)
    }

    static func relativeTime(minutes: Int) -> String {
        guard minutes > 0 else {
            return OBALoc("next_departures_intent.now", value: "now", comment: "Siri response: a vehicle departs now. Completes 'Route 550 to Seattle departs {now}'.")
        }
        let fmt = OBALoc("next_departures_intent.in_minutes_fmt", value: "in %d minutes", comment: "Siri response: a vehicle departs in {X} minutes. Plural forms in Localizable.stringsdict.")
        // localizedStringWithFormat, not String(format:) — the latter resolves
        // `%#@count@` against the root plural rule, so Slavic few/many are unreachable.
        return String.localizedStringWithFormat(fmt, minutes)
    }
}
