//
//  TripActivityContentBuilder.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

#if os(iOS)

import Foundation

/// Single source of truth for matching Live Activity arrivals and mapping them into
/// `TripAttributes.ContentState`, shared between the foreground app (`BookmarkActions`)
/// and interactive Live Activity intents (`LiveActivityControlHandler`).
public enum TripActivityContentBuilder {

    /// Maps up to the first three arrivals into a Live Activity `ContentState`,
    /// returning `nil` when `arrivalDepartures` is empty so callers never overwrite
    /// or start a blank card.
    public static func buildContentState(from arrivalDepartures: [ArrivalDeparture]) -> TripAttributes.ContentState? {
        guard !arrivalDepartures.isEmpty else {
            return nil
        }

        let arrivals = arrivalDepartures.prefix(3).map { arrDep in
            // `TripAttributes.ContentState.ArrivalInfo.departureTime` is part of the
            // iOS-only ActivityKit wire contract (`Int` epoch seconds).
            let epochSeconds = Int64(arrDep.arrivalDepartureDate.timeIntervalSince1970)
            return TripAttributes.ContentState.ArrivalInfo(
                departureTime: Int(epochSeconds),
                scheduleStatus: .init(arrDep.scheduleStatus),
                scheduleDeviation: arrDep.deviationFromScheduleInMinutes * 60,
                isArrival: arrDep.arrivalDepartureStatus == .arriving
            )
        }
        return TripAttributes.ContentState(arrivals: Array(arrivals))
    }

    /// Selects the primary arrival for OBACloud metadata registration, preferring the
    /// pinned `staticData.tripID` when still present in `arrivalDepartures`.
    public static func primaryArrival(
        for staticData: TripAttributes.StaticData,
        in arrivalDepartures: [ArrivalDeparture]
    ) -> ArrivalDeparture? {
        if !staticData.tripID.isEmpty,
           let tracked = arrivalDepartures.first(where: { $0.tripID == staticData.tripID }) {
            return tracked
        }
        return arrivalDepartures.first
    }

    /// Filters and sorts upcoming arrivals from a full stop response for `staticData`.
    ///
    /// When `staticData.tripID` is pinned and present in the upcoming arrivals, returns
    /// only arrivals for that trip; otherwise matches upcoming arrivals by route short
    /// name and (when non-empty) headsign.
    public static func matchingUpcomingArrivals(
        for staticData: TripAttributes.StaticData,
        from stopArrivals: [ArrivalDeparture],
        now: Date = Date()
    ) -> [ArrivalDeparture] {
        let upcoming = stopArrivals
            .filter { $0.arrivalDepartureDate >= now }
            .sorted { $0.arrivalDepartureDate < $1.arrivalDepartureDate }

        if !staticData.tripID.isEmpty {
            let pinned = upcoming.filter { $0.tripID == staticData.tripID }
            if !pinned.isEmpty {
                return pinned
            }
        }

        return upcoming.filter { arrival in
            guard arrival.routeShortName == staticData.routeShortName else {
                return false
            }
            if staticData.routeHeadsign.isEmpty {
                return true
            }
            return (arrival.tripHeadsign ?? "") == staticData.routeHeadsign
        }
    }

    /// Builds a refreshed `ContentState` from pre-filtered bookmark/stop arrivals,
    /// keeping pinned-trip isolation when `staticData.tripID` is still present.
    public static func buildRefreshContentState(
        for staticData: TripAttributes.StaticData,
        arrivalDepartures: [ArrivalDeparture]
    ) -> TripAttributes.ContentState? {
        guard !arrivalDepartures.isEmpty else {
            return nil
        }

        if !staticData.tripID.isEmpty,
           let tracked = arrivalDepartures.first(where: { $0.tripID == staticData.tripID }) {
            let sameTrip = arrivalDepartures
                .filter { $0.id == tracked.id }
                .sorted { $0.arrivalDepartureDate < $1.arrivalDepartureDate }
            return buildContentState(from: sameTrip.isEmpty ? [tracked] : sameTrip)
        }

        return buildContentState(from: arrivalDepartures)
    }

    /// Builds a refreshed `ContentState` from a raw stop-arrivals response, returning
    /// `nil` if no matching upcoming arrivals exist so callers leave existing content alone.
    public static func refreshContentState(
        for staticData: TripAttributes.StaticData,
        from stopArrivals: [ArrivalDeparture],
        now: Date = Date()
    ) -> TripAttributes.ContentState? {
        let matching = matchingUpcomingArrivals(for: staticData, from: stopArrivals, now: now)
        return buildContentState(from: matching)
    }
}

#endif // os(iOS)
