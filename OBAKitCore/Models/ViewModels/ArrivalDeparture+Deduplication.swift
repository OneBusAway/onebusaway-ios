//
//  ArrivalDeparture+Deduplication.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

// MARK: - Terminal Duplicate Filtering

/// A composite key identifying a single vehicle visit at a single stop.
/// Uses the same (tripID, stopID, routeID) pattern as `TripBookmarkKey`
/// to uniquely identify a trip at a stop.
/// Two `ArrivalDeparture` objects with the same `VisitIdentity` represent the
/// arrival/departure pair at a terminal and should be merged into one row.
private struct VisitIdentity: Hashable {
    let tripID: TripIdentifier
    let stopID: StopID
    let routeID: RouteID
}

extension Sequence where Element == ArrivalDeparture {

    /// Collapses entries that describe the same arrival/departure — identical `id`
    /// (stop, trip, route, service date, stop sequence, and arrival/departure status) —
    /// into a single entry, keeping the most recently updated report.
    ///
    /// Real-time feeds occasionally assign two vehicles to one trip (e.g. an AVL ghost
    /// alongside the actual coach), and the server then emits one entry per vehicle for
    /// the same trip visit. Riders should only ever see one row per visit, and duplicate
    /// `id`s also break identity-keyed UI downstream (SwiftUI `ForEach`, alarm indexes),
    /// so this runs at ingestion when `StopArrivals` is decoded.
    ///
    /// Unlike `filteringTerminalDuplicates()`, entries that differ in stop sequence or
    /// arrival/departure status are never merged, so loop-route double visits and
    /// terminal arrival/departure pairs pass through untouched.
    ///
    /// - Returns: A filtered array preserving the original order, with each duplicate's
    ///   first-occurrence position retained.
    public func filteringDuplicateVehicleReports() -> [ArrivalDeparture] {
        var seen = [String: Int]()
        var result: [ArrivalDeparture] = []

        for arrDep in self {
            if let existingIndex = seen[arrDep.id] {
                if arrDep.lastUpdated > result[existingIndex].lastUpdated {
                    result[existingIndex] = arrDep
                }
            } else {
                seen[arrDep.id] = result.count
                result.append(arrDep)
            }
        }

        return result
    }

    /// Filters out visually duplicate arrival/departure entries that occur at terminal or loop stops.
    ///
    /// At terminal stops, the OBA API returns two separate `ArrivalDeparture` objects for the
    /// same vehicle on the same trip at the same stop: one for the arrival (drop-off, `stopSequence > 0`)
    /// and one for the departure (pick-up, `stopSequence == 0`). These have different internal IDs
    /// (the `id` property includes `arrivalDepartureStatus`) but display nearly identically to the
    /// user, causing confusing duplicate rows.
    ///
    /// This method groups entries by `(tripID, stopID, routeID)` — which uniquely identifies a
    /// single vehicle visit at a single stop — and keeps only one entry per group. When choosing
    /// which entry to keep:
    /// 1. Prefer entries with real-time data (`predicted == true`) over scheduled-only entries.
    /// 2. If both or neither have real-time data, prefer the **departure** (pick-up), since that's
    ///    the more actionable information for a rider waiting at the stop.
    ///
    /// - Important: This does **not** merge entries that differ by `tripID`, `stopID`, or `routeID`.
    ///   Two entries for different trips, or for the same trip at different stops, are always preserved.
    ///
    /// - Returns: A filtered array with terminal duplicates removed, preserving the original order.
    public func filteringTerminalDuplicates() -> [ArrivalDeparture] {
        var seen = [VisitIdentity: Int]()
        var result: [ArrivalDeparture] = []

        for arrDep in self {
            let identity = VisitIdentity(
                tripID: arrDep.tripID,
                stopID: arrDep.stopID,
                routeID: arrDep.routeID
            )

            if let existingIndex = seen[identity] {
                // A duplicate exists for the same vehicle visit at this stop.
                // Decide which entry provides more useful information to the rider.
                let existing = result[existingIndex]
                if shouldReplace(existing: existing, with: arrDep) {
                    result[existingIndex] = arrDep
                }
            } else {
                seen[identity] = result.count
                result.append(arrDep)
            }
        }

        return result
    }

    /// Determines whether `candidate` should replace `existing` when both represent
    /// the same vehicle visit at a terminal stop.
    ///
    /// Preference order:
    /// 1. Real-time data wins over scheduled-only.
    /// 2. If tied on real-time availability, departure wins over arrival.
    private func shouldReplace(existing: ArrivalDeparture, with candidate: ArrivalDeparture) -> Bool {
        // Prefer real-time data over scheduled-only.
        if !existing.predicted && candidate.predicted {
            return true
        }

        if existing.predicted && !candidate.predicted {
            return false
        }

        // Both have the same real-time status. Prefer the departure
        // (stopSequence == 0 → departing) since riders care about when
        // the vehicle leaves, not when it arrived.
        if existing.arrivalDepartureStatus == .arriving && candidate.arrivalDepartureStatus == .departing {
            return true
        }

        // Otherwise keep the existing entry (first-in wins).
        return false
    }
}
