//
//  StopTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
import Testing
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try

class StopTests: OBATestCase {

    func test_RoundtrippingStops() {
        let stopOne = try! Fixtures.loadSomeStops().first!
        let data = try! PropertyListEncoder().encode(stopOne)
        let stopTwo = try! PropertyListDecoder().decode(Stop.self, from: data)

        #expect(stopTwo.routes != nil)

        #expect(stopOne.code != nil)
        #expect(stopOne.direction != nil)
        #expect(stopOne.id != nil)
        #expect(stopOne.location != nil)
        #expect(stopOne.locationType != nil)
        #expect(stopOne.name != nil)
        #expect(stopOne.routeIDs != nil)
        #expect(stopOne.routeIDs.count == 12)
        #expect(stopOne.routes != nil)
        #expect(stopOne.routes.count == 12)
        #expect(stopOne.routeTypes != nil)
        #expect(stopOne.prioritizedRouteTypeForDisplay != nil)
        #expect(stopOne.wheelchairBoarding != nil)

        #expect(stopOne == stopTwo)
        #expect(stopOne.routes == stopTwo.routes)
    }
}
