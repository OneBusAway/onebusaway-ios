//
//  NearbyCoordinateResolverTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class NearbyCoordinateResolverTests: OBATestCase {

    private let viewport = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)
    private let device = CLLocation(latitude: 40.7, longitude: -74.0)

    /// The map's viewport wins: the user asked for "nearby" from a sheet over
    /// the map they're looking at, not from wherever the device happens to be.
    @Test func `Viewport center wins when present`() {
        let resolved = NearbyCoordinateResolver.coordinate(
            viewportCenter: viewport,
            currentLocation: device,
            region: Fixtures.pugetSoundRegion
        )

        #expect(resolved?.latitude == viewport.latitude)
        #expect(resolved?.longitude == viewport.longitude)
    }

    /// Before the map's first settle there is no viewport center, so the
    /// device's own location is the next best anchor.
    @Test func `Device location is used when there is no viewport center`() {
        let resolved = NearbyCoordinateResolver.coordinate(
            viewportCenter: nil,
            currentLocation: device,
            region: Fixtures.pugetSoundRegion
        )

        #expect(resolved?.latitude == device.coordinate.latitude)
        #expect(resolved?.longitude == device.coordinate.longitude)
    }

    /// Location permission denied and no settle yet: the region's center is
    /// still somewhere the user has transit data for.
    @Test func `Region center is the last resort`() {
        let region = Fixtures.pugetSoundRegion

        let resolved = NearbyCoordinateResolver.coordinate(
            viewportCenter: nil,
            currentLocation: nil,
            region: region
        )

        #expect(resolved?.latitude == region.centerCoordinate.latitude)
        #expect(resolved?.longitude == region.centerCoordinate.longitude)
    }

    /// Nothing to anchor on. Returning nil is what makes the view render its
    /// empty state instead of fetching stops around (0, 0) in the Gulf of Guinea.
    @Test func `Nil is returned when nothing can anchor the search`() {
        let resolved = NearbyCoordinateResolver.coordinate(
            viewportCenter: nil,
            currentLocation: nil,
            region: nil
        )

        #expect(resolved == nil)
    }
}
