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

    static func make(stopTimes: [S], userStopID: StopID, closestStopID: StopID?) -> ApproachSlice? {
        guard let userIndex = stopTimes.firstIndex(where: { $0.stopID == userStopID }) else { return nil }

        let vehicleAbsolute = closestStopID.flatMap { closest in
            stopTimes.firstIndex(where: { $0.stopID == closest })
        }
        if let vehicleAbsolute, vehicleAbsolute > userIndex {
            return nil // vehicle already past the user's stop
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
}

/// Adapts the real REST model to the timeline windowing logic. `stopName`
/// reads through the resolved `stop` reference — the same access
/// `TripStopListItem`/`TripStopViewModel` use (`stopTime.stop.name`), which
/// is populated by `loadReferences` before the trip panel ever renders.
extension TripStopTime: ApproachTimelineStop {
    var stopName: String { stop.name }
}
