//
//  TripMapFocusFixture.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import UIKit
import OBAKitCore
@testable import OBAKit

/// The trip values shared by the suites that draw one: `TripFocusMapLayerTests`
/// on the map tab's `MKMapView`, and `TripFocusMapDisplayModelTests` on the
/// panel's SwiftUI map. Both draw from the same `TripMapFocus.Content`, so they
/// build it one way.
@MainActor
enum TripMapFocusFixture {

    /// A straight line running east, one point per hundredth of a degree.
    static func shape(points: Int = 5) -> [CLLocationCoordinate2D] {
        (0..<points).map { CLLocationCoordinate2D(latitude: 47, longitude: -122 + Double($0) * 0.01) }
    }

    static func row(
        _ index: Int,
        stopID: StopID,
        coordinate: CLLocationCoordinate2D?,
        isPassed: Bool = false,
        isVehicleHere: Bool = false,
        isUserStop: Bool = false,
        isTerminal: Bool = false
    ) -> TripStopListModel.Row {
        TripStopListModel.Row(
            id: "\(index)-\(stopID)",
            stopID: stopID,
            name: "Stop \(stopID)",
            coordinate: coordinate,
            date: nil,
            isPassed: isPassed,
            isVehicleHere: isVehicleHere,
            isUserStop: isUserStop,
            isTerminal: isTerminal
        )
    }

    static func content(
        tripID: String = "trip_1",
        shape: [CLLocationCoordinate2D],
        progress: Double?,
        stops: [TripStopListModel.Row] = [],
        vehicle: TripStatus? = nil
    ) -> TripMapFocus.Content {
        TripMapFocus.Content(
            tripID: tripID,
            routeColor: .systemRed,
            routeType: .bus,
            shape: shape,
            progress: progress,
            stops: stops,
            vehicle: vehicle
        )
    }

    /// A real `TripStatus`, which only decodes from JSON — see
    /// `StopVehicleAnnotationTests.makeTripStatus` for why this fixture and why
    /// the reference-loading step matters.
    static func vehicle() throws -> TripStatus {
        try Fixtures.loadRESTAPIPayload(
            type: VehicleStatus.self,
            fileName: "api_where_vehicle_1_4351.json"
        ).tripStatus
    }
}
