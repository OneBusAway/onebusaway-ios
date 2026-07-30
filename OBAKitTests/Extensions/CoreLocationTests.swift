//
//  CoreLocationTests.swift
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

@MainActor
@Suite(.serialized)
final class CoreLocationTests {

    // MARK: - CLCircularRegion

    @Test func `Creation from map rect`() {
        let region = CLCircularRegion(mapRect: TestData.seattleMapRect)

        expectClose(region.center.latitude, TestData.seattleMapRectCenter.latitude)
        expectClose(region.center.longitude, TestData.seattleMapRectCenter.longitude)
        expectClose(region.radius, TestData.seattleMapRectRadius, within: 0.1)
    }

    // MARK: - Distance

    @Test func `Distance calculation`() {
        let pt1 = CLLocationCoordinate2D(latitude: 47.62365100, longitude: -122.31257200)
        let pt2 = CLLocationCoordinate2D(latitude: 47.632352, longitude: -122.312526)

        let distance = pt1.distance(from: pt2)
        expectClose(distance, 967.4102, within: 0.1)
    }
}
