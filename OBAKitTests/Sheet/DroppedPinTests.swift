//
//  DroppedPinTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Testing
@testable import OBAKit

/// The UIKit map's long-press pin, the way to plan a trip to or find stops near
/// an arbitrary spot, had no counterpart on the panel.
@Suite
struct DroppedPinTests {
    @Test func `A dropped pin opens a place at the pressed spot, named as the UIKit pin`() {
        let coordinate = CLLocationCoordinate2D(latitude: 47.6097, longitude: -122.3422)

        let mapItem = DroppedPin.mapItem(at: coordinate)

        #expect(mapItem.placemark.coordinate.latitude == coordinate.latitude)
        #expect(mapItem.placemark.coordinate.longitude == coordinate.longitude)
        #expect(mapItem.name == UserDroppedPin.defaultTitle)
    }
}
