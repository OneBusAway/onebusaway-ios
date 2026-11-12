//
//  StopArrivalsFixture.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// The arrivals shared by the suites that draw a stop's routes and vehicles:
/// `StopRouteFocusApplyTests` on the map tab's `MKMapView`, and
/// `StopFocusMapDisplayModelTests` on the panel's SwiftUI map.
///
/// Stop 1_10020 has two routes, 1_30 and 1_65, and four departures, each with
/// its own vehicle and a `tripStatus.position`.
enum StopArrivalsFixture {

    static let fileName = "arrivals_and_departures_for_stop_1_10020.json"

    static func load() throws -> StopArrivals {
        try Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: fileName)
    }

    /// The same fixture with its arrival and departure times moved into the near
    /// future.
    ///
    /// Necessary because `StopRouteFocusModel.make` drops anything whose
    /// `temporalState` is `.past`, and the fixture's timestamps are fixed at 2019.
    /// Loaded as-is it yields zero routes and zero vehicles, so a test built on it
    /// would assert an empty map and pass no matter what was drawn.
    ///
    /// The four time keys are rewritten in place and the payload re-decoded through
    /// the same `RESTAPIResponse` path `Fixtures.loadRESTAPIPayload` uses, so
    /// `references`, and therefore each `TripStatus.activeTrip`, still resolve.
    static func upcoming() throws -> StopArrivals {
        var payload = try #require(
            try JSONSerialization.jsonObject(with: Fixtures.loadData(file: fileName)) as? [String: Any]
        )
        var data = try #require(payload["data"] as? [String: Any])
        var entry = try #require(data["entry"] as? [String: Any])
        var departures = try #require(entry["arrivalsAndDepartures"] as? [[String: Any]])

        for index in departures.indices {
            // Minutes apart so `make`'s soonest-per-route ordering stays meaningful.
            let millis = Int((Date().timeIntervalSince1970 + Double((index + 2) * 60)) * 1000)
            for key in ["predictedArrivalTime", "scheduledArrivalTime", "predictedDepartureTime", "scheduledDepartureTime"] {
                departures[index][key] = millis
            }
        }

        entry["arrivalsAndDepartures"] = departures
        data["entry"] = entry
        payload["data"] = data

        let rewritten = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<StopArrivals>.self, from: rewritten).list
    }
}
