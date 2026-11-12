//
//  NextDeparturesSummary.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// What `NextDeparturesIntent` and `NextDeparturesAtStopIntent` say. Pure, so
/// the wording is testable without App Intents, Siri, or the network.
nonisolated enum NextDeparturesSummary {
    static let maximumDepartures = 3

    /// One departure of the bookmarked trip: when, and how that time relates
    /// to the timetable. Carries what `DepartureStatus` needs, so the
    /// Next Departures card can show live/scheduled and early/late the way the
    /// stop page does (#1554).
    nonisolated struct Departure: Equatable, Sendable {
        /// The predicted time when `isRealTime`, the timetabled time otherwise.
        let date: Date
        /// `true` when `date` is a real-time prediction.
        let isRealTime: Bool
        let scheduleStatus: ScheduleStatus
        /// Rounded minutes off the timetable; positive is late.
        let deviationMinutes: Int

        init(date: Date, isRealTime: Bool, scheduleStatus: ScheduleStatus, deviationMinutes: Int) {
            self.date = date
            self.isRealTime = isRealTime
            self.scheduleStatus = scheduleStatus
            self.deviationMinutes = deviationMinutes
        }

        init(arrivalDeparture: ArrivalDeparture) {
            self.init(
                date: arrivalDeparture.arrivalDepartureDate,
                isRealTime: arrivalDeparture.predicted,
                scheduleStatus: arrivalDeparture.scheduleStatus,
                deviationMinutes: arrivalDeparture.deviationFromScheduleInMinutes
            )
        }
    }

    /// One departure from a stop, for the stop-level answer: unlike a trip
    /// bookmark's, each can be a different route and headsign.
    nonisolated struct StopDeparture: Equatable, Sendable {
        let routeShortName: String
        /// `nil` when the feed names none.
        let headsign: String?
        let departure: Departure

        init(routeShortName: String, headsign: String?, departure: Departure) {
            self.routeShortName = routeShortName
            self.headsign = headsign
            self.departure = departure
        }

        init(arrivalDeparture: ArrivalDeparture) {
            self.init(
                routeShortName: arrivalDeparture.routeShortName,
                headsign: String.nilifyBlankValue(arrivalDeparture.tripHeadsign),
                departure: Departure(arrivalDeparture: arrivalDeparture)
            )
        }
    }

    nonisolated enum Outcome: Equatable, Sendable {
        case noBookmarks
        case noRegion
        case bookmarkUnavailable
        /// The stop belongs to another region, or its id doesn't name one.
        case stopUnavailable
        /// The fetch failed. `name` is the bookmark's or the stop's.
        case loadFailed(name: String)
        /// `departures` may include ones that already left; `text` drops them.
        case departures(bookmarkName: String, routeShortName: String, headsign: String, departures: [Departure])
        /// A stop's departures across all its routes. `departures` may include
        /// ones that already left; `text` drops them.
        case stopDepartures(stopName: String, departures: [StopDeparture])
    }

    static func text(for outcome: Outcome, now: Date) -> String {
        switch outcome {
        case .noBookmarks:
            return OBALoc("next_departures_intent.no_bookmarks", value: "You don't have any bookmarked trips. Bookmark a route at a stop first.", comment: "Siri response when the user asks for their next departures but has no trip bookmarks in the current region.")
        case .noRegion:
            return OBALoc("next_departures_intent.no_region", value: "Choose a transit region in the app first.", comment: "Siri response when the user asks for their next departures before the app knows their region.")
        case .bookmarkUnavailable:
            return OBALoc("next_departures_intent.bookmark_unavailable", value: "That bookmark isn't available in your current region.", comment: "Siri response when the requested bookmark was deleted or belongs to a different region.")
        case .stopUnavailable:
            return OBALoc("next_departures_intent.stop_unavailable", value: "That stop isn't in your current region.", comment: "Siri response when the requested stop belongs to a different region than the one the app is using.")
        case .loadFailed(let name):
            let fmt = OBALoc("next_departures_intent.load_failed_fmt", value: "Couldn't load departures for %@. Check your connection and try again.", comment: "Siri response when departures could not be fetched. {Bookmark or stop name}")
            return String(format: fmt, name)
        case let .departures(bookmarkName, routeShortName, headsign, departures):
            if let sentence = departuresSentence(routeShortName: routeShortName, headsign: headsign, dates: departures.map(\.date), now: now) {
                return sentence
            }
            let fmt = OBALoc("next_departures_intent.no_departures_fmt", value: "No departures for %@ in the next hour.", comment: "Siri response when a bookmarked trip has no upcoming departures. {Bookmark name}")
            return String(format: fmt, bookmarkName)
        case let .stopDepartures(stopName, departures):
            if let sentence = stopDeparturesSentence(stopName: stopName, departures: departures, now: now) {
                return sentence
            }
            // Not the bookmark's sentence: "for" a stop reads as "to" it in some languages.
            let fmt = OBALoc("next_departures_intent.stop_no_departures_fmt", value: "No departures from %@ in the next hour.", comment: "Siri response when nothing leaves a stop in the next hour. {Stop name}")
            return String(format: fmt, stopName)
        }
    }

    /// The stop's departures still to come, soonest first, at most
    /// `maximumDepartures`, each with its whole minutes from `now`. Shared
    /// with the card, so the card and the dialog agree on which three.
    static func upcoming(_ departures: [StopDeparture], now: Date) -> [(departure: StopDeparture, minutes: Int)] {
        Array(departures
            .sorted { $0.departure.date < $1.departure.date }
            .map { (departure: $0, minutes: Int($0.departure.date.timeIntervalSince(now) / 60)) }
            .filter { $0.minutes >= 0 }
            .prefix(maximumDepartures))
    }

    /// "Next at 15th Ave E & E Galer St: 10 to Downtown Seattle in 6 minutes
    /// and 49 to Capitol Hill in 12 minutes." `nil` when nothing is still to come.
    static func stopDeparturesSentence(stopName: String, departures: [StopDeparture], now: Date) -> String? {
        let items = upcoming(departures, now: now).map { stopDepartureText($0.departure, minutes: $0.minutes) }
        guard !items.isEmpty else { return nil }

        let fmt = OBALoc("next_departures_intent.stop_departures_fmt", value: "Next at %1$@: %2$@.", comment: "Siri response listing the next departures from a stop. {Stop name}: {list of departures, such as '8 to Downtown in 4 minutes and 49 to Capitol Hill in 12 minutes'}.")
        return String(format: fmt, stopName, ListFormatter.localizedString(byJoining: items))
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

    /// "8 to Downtown in 4 minutes", or "8 in 4 minutes" without a headsign.
    static func stopDepartureText(_ departure: StopDeparture, minutes: Int) -> String {
        let time = relativeTime(minutes: minutes)
        guard let headsign = departure.headsign else {
            let fmt = OBALoc("next_departures_intent.stop_departure_no_headsign_fmt", value: "%1$@ %2$@", comment: "Siri response: one departure from a stop whose trip has no destination name. {Route short name} {'now' or 'in X minutes'}, for example '8 in 4 minutes'.")
            return String(format: fmt, departure.routeShortName, time)
        }
        let fmt = OBALoc("next_departures_intent.stop_departure_fmt", value: "%1$@ to %2$@ %3$@", comment: "Siri response: one departure from a stop. {Route short name} to {Headsign} {'now' or 'in X minutes'}, for example '8 to Downtown in 4 minutes'.")
        return String(format: fmt, departure.routeShortName, headsign, time)
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
