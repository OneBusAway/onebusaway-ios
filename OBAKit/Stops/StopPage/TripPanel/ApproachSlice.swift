//
//  ApproachSlice.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// Abstraction over `TripStopTime` so the windowing logic is testable with
/// stubs (the real type only decodes from JSON).
protocol ApproachTimelineStop {
    var stopID: StopID { get }
    var stopName: String { get }
}

/// The trip panel's approach window: the user's stop plus up to 4 upstream
/// stops, with the vehicle's position resolved from `closestStopID` — the
/// same field the Trip screen uses (`TripStopListItem`).
///
/// When the vehicle is further back than the window, its stop is pinned to
/// the top of the slice and the stops between it and the final 3 upstream
/// stops are elided; `skippedStopCount` says how many were dropped so the
/// timeline can render a gap marker.
struct ApproachSlice<S: ApproachTimelineStop> {
    let stops: [S]
    let vehicleIndex: Int?
    /// Stops elided between `stops[0]` (the vehicle's stop) and `stops[1]`.
    /// Zero when the window is contiguous.
    let skippedStopCount: Int

    /// - Parameter userStopSequence: The departure's position in the trip's stop
    ///   times. A loop route visits the same stop at more than one sequence, so
    ///   the stop ID alone can't say which visit this departure is for.
    static func make(stopTimes: [S], userStopID: StopID, userStopSequence: Int? = nil, closestStopID: StopID?) -> ApproachSlice? {
        guard let userIndex = userIndex(in: stopTimes, stopID: userStopID, stopSequence: userStopSequence) else { return nil }

        var vehicleAbsolute: Int?
        if let closest = closestStopID, stopTimes.contains(where: { $0.stopID == closest }) {
            // The vehicle's closest stop can also appear more than once on a loop.
            // The occurrence that matters is the last one at or before the user's
            // stop — the leg the vehicle is on now. If every occurrence is
            // downstream of the user's stop, the vehicle has already been through.
            guard let index = stopTimes[...userIndex].lastIndex(where: { $0.stopID == closest }) else {
                return nil // vehicle already past the user's stop
            }
            vehicleAbsolute = index
        }

        let start = max(0, userIndex - 4)
        if let vehicleAbsolute, vehicleAbsolute < start {
            // Vehicle is beyond the window: pin its stop on top, keep the 3
            // stops nearest the user, and elide everything in between.
            let window = [stopTimes[vehicleAbsolute]] + Array(stopTimes[(userIndex - 3)...userIndex])
            return ApproachSlice(stops: window, vehicleIndex: 0, skippedStopCount: userIndex - 4 - vehicleAbsolute)
        }

        let window = Array(stopTimes[start...userIndex])
        return ApproachSlice(stops: window, vehicleIndex: vehicleAbsolute.map { $0 - start }, skippedStopCount: 0)
    }

    /// Resolves the departure's own visit to the user's stop. `stopSequence`
    /// indexes the trip's stop times, so it picks out the right occurrence when a
    /// loop route calls at the stop more than once; the stop-ID search is the
    /// fallback for callers (and feeds) that don't supply one.
    private static func userIndex(in stopTimes: [S], stopID: StopID, stopSequence: Int?) -> Int? {
        if let stopSequence, stopTimes.indices.contains(stopSequence), stopTimes[stopSequence].stopID == stopID {
            return stopSequence
        }
        return stopTimes.firstIndex(where: { $0.stopID == stopID })
    }
}

/// Adapts the real REST model to the timeline windowing logic. `stopName`
/// reads through the resolved `stop` reference — the same access
/// `TripStopListItem`/`TripStopViewModel` use (`stopTime.stop.name`), which
/// is populated by `loadReferences` before the trip panel ever renders.
extension TripStopTime: ApproachTimelineStop {
    var stopName: String { stop.name }
}
