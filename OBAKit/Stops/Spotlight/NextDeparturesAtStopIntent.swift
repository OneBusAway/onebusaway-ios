//
//  NextDeparturesAtStopIntent.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import AppIntents
import OBAKitCore

/// Answers "when is the next bus at 3rd and Pine?" from Siri or Shortcuts
/// without opening the app: the next few departures from a stop, across all
/// its routes. `NextDeparturesIntent` answers the same question for a trip
/// bookmark; this one takes any `StopEntity` (#1555).
///
/// The parameter is optional so that, without one, Siri asks "Which stop?" and
/// offers the query's suggestions, the bookmarked and recent stops.
///
/// Isolation, the iOS 26 card and the strings follow `NextDeparturesIntent`:
/// the card is the same one, opened through `NextDeparturesCardIntent`.
public struct NextDeparturesAtStopIntent: AppIntent {
    public static let title = LocalizedStringResource("next_departures_at_stop_intent.title", defaultValue: "Next Departures at Stop", table: "AppIntents")
    public static let description = IntentDescription(LocalizedStringResource("next_departures_at_stop_intent.description", defaultValue: "Hear the next departures from a stop.", table: "AppIntents"))
    public static let openAppWhenRun = false

    public init() {}

    @Parameter(title: LocalizedStringResource("stop_entity.parameter_title", defaultValue: "Stop", table: "AppIntents"))
    public var stop: StopEntity?

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let stop else {
            let prompt = OBALoc("next_departures_at_stop_intent.choose_stop", value: "Which stop?", comment: "Siri asks which stop to report departures for when the user didn't name one.")
            throw $stop.needsValueError("\(prompt)")
        }

        // Through the store, so the card can show this outcome without fetching it again.
        let outcome = await NextDeparturesStore.shared.load(.stop(stop.id))
        let text = NextDeparturesSummary.text(for: outcome, now: Date())

        // The same single result type as `NextDeparturesIntent`, for the same reason.
        if #available(iOS 26.0, *) {
            return .result(
                value: text,
                opensIntent: NextDeparturesCardIntent(stopEntityID: stop.id),
                dialog: IntentDialog(full: "\(text)", supporting: Self.title)
            )
        }
        return .result(value: text, dialog: "\(text)")
    }
}

extension NextDeparturesLoader {
    /// The window fetched for a stop. Matches `BookmarkArrivalsLoader`, so the
    /// "no departures in the next hour" answer is true for a stop as well.
    static let stopMinutesBefore: UInt = 0
    static let stopMinutesAfter: UInt = 60

    /// One stop's departures, by its `StopEntity` id. The stop's name comes
    /// from the server when the fetch works, else from the bookmark or recent
    /// stop the app has, else its id, as the entity is titled.
    func outcome(stopEntityID: String) async -> NextDeparturesSummary.Outcome {
        guard let region = ResolvedRegionStore(userDefaults: userDefaults).region(bundledRegionsFilePath: bundledRegionsFilePath) else {
            return .noRegion
        }

        let store = UserDefaultsStore(userDefaults: userDefaults)
        guard
            let destination = StopEntityMapping.destination(fromIdentifier: stopEntityID),
            destination.regionID == region.regionIdentifier,
            let entity = StopEntityMapping.entities(forIdentifiers: [stopEntityID], bookmarks: store.bookmarks, recentStops: store.recentStops).first
        else {
            return .stopUnavailable
        }

        guard let service = service(region: region) else {
            return .loadFailed(name: entity.title)
        }

        let arrivals: StopArrivals
        do {
            arrivals = try await service.getArrivalsAndDeparturesForStop(
                id: destination.stopID,
                minutesBefore: Self.stopMinutesBefore,
                minutesAfter: Self.stopMinutesAfter
            ).entry
        } catch {
            Logger.error("Next Departures Shortcut: arrivals failed for stop \(destination.stopID): \(error.localizedDescription)")
            return .loadFailed(name: entity.title)
        }

        // `stop` is implicitly unwrapped, and nil when the references lack it.
        let stop: Stop? = arrivals.stop
        let departures = Self.boardable(
            arrivals.arrivalsAndDepartures,
            filter: .effective(in: userDefaults, brandDefault: defaultArrivalDepartureFilter),
            preferences: store.preferences(stopID: destination.stopID, region: region),
            stopRouteIDs: stop?.routes?.map(\.id) ?? []
        )
        return .stopDepartures(
            stopName: stop?.name ?? entity.title,
            departures: departures.map(NextDeparturesSummary.StopDeparture.init(arrivalDeparture:))
        )
    }

    /// What a rider at the stop could board, as the stop page would list it:
    /// the rider's departure filter and hidden routes apply, unless every
    /// route the stop serves is hidden, where the stop page drops the hiding
    /// too. Unlike the stop page, a vehicle riders can't board here is left
    /// out: a trip that ends here, or a drop-off-only stop. The server says so
    /// in `departureEnabled`, which, unlike `isLastStopOnTrip`, doesn't need
    /// the feed to send `totalStopsInTrip`.
    static func boardable(_ arrivals: [ArrivalDeparture], filter: ArrivalDepartureFilter, preferences: StopPreferences, stopRouteIDs: [RouteID]) -> [ArrivalDeparture] {
        // As `StopViewModel` does, an empty route list counts as all hidden,
        // so a stop the server sent without routes hides nothing.
        let hidesRoutes = !stopRouteIDs.allSatisfy(preferences.isRouteIDHidden)
        return arrivals
            .filter(by: filter)
            .filter(\.departureEnabled)
            .filter { !hidesRoutes || !preferences.isRouteIDHidden($0.routeID) }
    }
}
