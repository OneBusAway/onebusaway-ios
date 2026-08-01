//
//  TripStopListModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import OBAKitCore

/// Abstraction over `TripStopTime` so this logic is testable with stubs — the
/// real type only decodes from JSON. Mirrors `ApproachTimelineStop`, which does
/// the same for the stop page's 5-stop window.
protocol TripStopListEntry {
    var stopID: StopID { get }
    var stopName: String { get }
    var scheduledArrival: Date? { get }
    /// Where to draw this stop's dot. Optional so a feed that omits a stop's
    /// location costs one marker rather than the whole trip.
    ///
    /// Named `stopCoordinate`, not `coordinate`: `TripStopTime` is already an
    /// `MKAnnotation` and so already has a non-optional `coordinate`, which
    /// can neither be redeclared nor witness an optional requirement.
    var stopCoordinate: CLLocationCoordinate2D? { get }
}

/// Every stop on a trip, each tagged with what the timeline needs to draw it.
///
/// This is the whole-trip counterpart to `ApproachSlice`. That type answers "what
/// are the few stops leading up to mine", which is a stop-page question; this one
/// answers "what does this entire trip look like, and where is the bus on it",
/// which is the trip page's. They deliberately stay separate: the windowing,
/// elision, and gap-marker rules that make `ApproachSlice` useful are exactly the
/// rules a full list must not apply.
struct TripStopListModel {

    struct Row: Identifiable {
        /// Position-qualified rather than the bare stop ID: a loop route visits
        /// the same stop more than once, and `ForEach` collapses rows that share
        /// an id.
        let id: String
        /// The stop itself. Carried rather than parsed back out of `id`: that
        /// string is a rendering identity, and reversing it to recover data it
        /// happens to embed is the kind of coupling that breaks silently the
        /// first time the identity format changes.
        let stopID: StopID
        let name: String
        let coordinate: CLLocationCoordinate2D?
        /// Optional because `TripStopTime.arrivalDate` is, once it crosses the
        /// module boundary. A row with no time renders without one.
        let date: Date?
        /// Strictly behind the vehicle. The vehicle's own stop is not passed —
        /// it renders active, matching `ApproachTimelineView`.
        let isPassed: Bool
        let isVehicleHere: Bool
        let isUserStop: Bool
        /// The end of the line. Carries the terminal marker on the map and the
        /// end cap on the list's connector.
        let isTerminal: Bool
    }

    let rows: [Row]
    /// Where the vehicle is, or `nil` on a trip with no live position — in which
    /// case no stop is passed, because nothing is known to have happened yet.
    let vehicleIndex: Int?

    static func make<S: TripStopListEntry>(
        stopTimes: [S],
        userStopID: StopID?,
        userStopSequence: Int?,
        closestStopID: StopID?
    ) -> TripStopListModel {
        let userIndex = userStopID.flatMap {
            index(in: stopTimes, stopID: $0, stopSequence: userStopSequence)
        }
        let vehicleIndex = vehicleIndex(in: stopTimes, closestStopID: closestStopID, userIndex: userIndex)

        let rows = stopTimes.enumerated().map { index, stopTime in
            Row(
                id: "\(index)-\(stopTime.stopID)",
                stopID: stopTime.stopID,
                name: stopTime.stopName,
                coordinate: stopTime.stopCoordinate,
                date: stopTime.scheduledArrival,
                isPassed: vehicleIndex.map { index < $0 } ?? false,
                isVehicleHere: index == vehicleIndex,
                isUserStop: index == userIndex,
                isTerminal: index == stopTimes.count - 1
            )
        }

        return TripStopListModel(rows: rows, vehicleIndex: vehicleIndex)
    }

    /// The vehicle's position, resolved from a stop ID that a loop route can
    /// match more than once.
    ///
    /// Anchored to the rider's stop, the occurrence that matters is the last one
    /// at or before it — the leg the vehicle is on now. Without a rider's stop
    /// (a trip reached from vehicle search) there is nothing to anchor to, so the
    /// first visit is the only defensible pick.
    private static func vehicleIndex<S: TripStopListEntry>(
        in stopTimes: [S],
        closestStopID: StopID?,
        userIndex: Int?
    ) -> Int? {
        guard let closestStopID else { return nil }

        if let userIndex {
            if let index = stopTimes[...userIndex].lastIndex(where: { $0.stopID == closestStopID }) {
                return index
            }
            // Every occurrence is downstream of the rider's stop: the vehicle has
            // already been through. Fall through to the unanchored search rather
            // than reporting no vehicle — the trip page still draws the whole
            // trip, including the part the rider has missed.
        }

        return stopTimes.firstIndex { $0.stopID == closestStopID }
    }

    /// Resolves a stop ID to a row. `stopSequence` indexes the trip's stop times,
    /// so it picks the right occurrence when a loop route calls at the stop more
    /// than once; the stop-ID search is the fallback for callers and feeds that
    /// don't supply one.
    private static func index<S: TripStopListEntry>(in stopTimes: [S], stopID: StopID, stopSequence: Int?) -> Int? {
        if let stopSequence, stopTimes.indices.contains(stopSequence), stopTimes[stopSequence].stopID == stopID {
            return stopSequence
        }
        return stopTimes.firstIndex { $0.stopID == stopID }
    }
}

/// Adapts the real REST model.
///
/// `scheduledArrival` exists rather than the protocol just requiring
/// `arrivalDate`: that property is declared `Date!`, which other modules see as
/// `Date?` and which therefore cannot witness a non-optional requirement. Naming
/// the protocol member separately keeps the optionality visible at the call site
/// instead of hiding it behind an implicit unwrap that traps on a feed that
/// omits the time.
extension TripStopTime: TripStopListEntry {
    /// Reads through the resolved `stop` reference, which `loadReferences`
    /// populates before any of this renders — the same access `TripStopListItem`
    /// uses.
    var stopName: String { stop.name }
    var scheduledArrival: Date? { arrivalDate }
    var stopCoordinate: CLLocationCoordinate2D? { stop.location.coordinate }
}
