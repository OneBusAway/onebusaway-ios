//
//  CoreLocationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import XCTest
import CoreLocation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@MainActor
class CoreLocationTests: XCTestCase {

    // MARK: - CLCircularRegion

    func test_creation_fromMapRect() {
        let region = CLCircularRegion(mapRect: TestData.seattleMapRect)

        expectClose(region.center.latitude, TestData.seattleMapRectCenter.latitude)
        expectClose(region.center.longitude, TestData.seattleMapRectCenter.longitude)
        expectClose(region.radius, TestData.seattleMapRectRadius, within: 0.1)
    }

    // MARK: - Distance

    func test_distanceCalculation() {
        let pt1 = CLLocationCoordinate2D(latitude: 47.62365100, longitude: -122.31257200)
        let pt2 = CLLocationCoordinate2D(latitude: 47.632352, longitude: -122.312526)

        let distance = pt1.distance(from: pt2)
        expectClose(distance, 967.4102, within: 0.1)
    }
}
