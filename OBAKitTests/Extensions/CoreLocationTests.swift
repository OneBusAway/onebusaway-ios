//
//  CoreLocationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Nimble
import XCTest
import CoreLocation
@testable import OBAKit
@testable import OBAKitCore

class CoreLocationTests: XCTestCase {

    // MARK: - CLCircularRegion

    func test_creation_fromMapRect() {
        let region = CLCircularRegion(mapRect: TestData.seattleMapRect)

        expect(region.center.latitude).to(beCloseTo(TestData.seattleMapRectCenter.latitude))
        expect(region.center.longitude).to(beCloseTo(TestData.seattleMapRectCenter.longitude))
        expect(region.radius).to(beCloseTo(TestData.seattleMapRectRadius, within: 0.1))
    }

    // MARK: - Distance

    func test_distanceCalculation() {
        let pt1 = CLLocationCoordinate2D(latitude: 47.62365100, longitude: -122.31257200)
        let pt2 = CLLocationCoordinate2D(latitude: 47.632352, longitude: -122.312526)

        let distance = pt1.distance(from: pt2)
        expect(distance).to(beCloseTo(967.4102, within: 0.1))
    }
}
