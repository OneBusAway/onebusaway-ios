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
/// Two `ArrivalDeparture` objects with the same `VisitIdentity` represent the
/// arrival/departure pair at a terminal and should be merged into one row.
private struct VisitIdentity: Hashable {
    let tripID: TripIdentifier
    let stopID: StopID
    let routeID: RouteID
}

extension Sequence where Element == ArrivalDeparture {

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
