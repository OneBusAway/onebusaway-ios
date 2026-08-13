//
//  TestData.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import MapKit

public class TestData: NSObject {

    public static let seattleCoordinate = CLLocationCoordinate2D(latitude: 47.623651, longitude: -122.312572)
    public static let tampaCoordinate = CLLocationCoordinate2D(latitude: 27.976911, longitude: -82.445851)

    // `let`, not `var`: nothing assigns to these, and as `var` they were
    // nonisolated global mutable state, which is what Swift 6 flagged. (They
    // were already evaluated once — the old form was a stored property with a
    // `= { ... }()` initializer, not a computed property.)
    //
    // Whatever else changes here, they must stay single shared instances rather
    // than become computed properties: `LocationServiceTests` compares against
    // them with `==` (lines 42, 56, 60), and `CLLocation`/`CLHeading` inherit
    // NSObject identity comparison, so a fresh instance per access would fail.
    public static let mockSeattleLocation = CLLocation(coordinate: seattleCoordinate, altitude: 100.0, horizontalAccuracy: 10.0, verticalAccuracy: 10.0, timestamp: Date())

    public static let mockTampaLocation = CLLocation(coordinate: tampaCoordinate, altitude: 100.0, horizontalAccuracy: 10.0, verticalAccuracy: 10.0, timestamp: Date())

    public static let mockHeading = OBAMockHeading(heading: 45.0)

    public static let seattleMapRect = MKMapRect(x: 43013871.99811534, y: 93728205.2278356, width: 1984.0073646754026, height: 3397.6126077622175)
    public static let seattleMapRectCenter = CLLocationCoordinate2D(latitude: 47.62365100, longitude: -122.31257200)
    public static let seattleMapRectRadius = 197.86
}
