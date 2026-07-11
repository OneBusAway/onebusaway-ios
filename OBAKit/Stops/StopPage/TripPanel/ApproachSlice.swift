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
struct ApproachSlice<S: ApproachTimelineStop> {
    let stops: [S]
    let vehicleIndex: Int?

    static func make(stopTimes: [S], userStopID: StopID, closestStopID: StopID?) -> ApproachSlice? {
        guard let userIndex = stopTimes.firstIndex(where: { $0.stopID == userStopID }) else { return nil }

        if let closestStopID,
           let vehicleAbsolute = stopTimes.firstIndex(where: { $0.stopID == closestStopID }),
           vehicleAbsolute > userIndex {
            return nil // vehicle already past the user's stop
        }

        let start = max(0, userIndex - 4)
        let window = Array(stopTimes[start...userIndex])
        let vehicleIndex = closestStopID.flatMap { closest in
            window.firstIndex(where: { $0.stopID == closest })
        }
        return ApproachSlice(stops: window, vehicleIndex: vehicleIndex)
    }
}

/// Adapts the real REST model to the timeline windowing logic. `stopName`
/// reads through the resolved `stop` reference — the same access
/// `TripStopListItem`/`TripStopViewModel` use (`stopTime.stop.name`), which
/// is populated by `loadReferences` before the trip panel ever renders.
extension TripStopTime: ApproachTimelineStop {
    var stopName: String { stop.name }
}
