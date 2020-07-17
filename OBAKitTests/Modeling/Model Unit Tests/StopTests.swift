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
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try

class StopTests: OBATestCase {

    func test_RoundtrippingStops() {
        let stopOne = try! Fixtures.loadSomeStops().first!
        let data = try! PropertyListEncoder().encode(stopOne)
        let stopTwo = try! PropertyListDecoder().decode(Stop.self, from: data)

        expect(stopTwo.routes).toNot(beNil())

        expect(stopOne.code).toNot(beNil())
        expect(stopOne.direction).toNot(beNil())
        expect(stopOne.id).toNot(beNil())
        expect(stopOne.location).toNot(beNil())
        expect(stopOne.locationType).toNot(beNil())
        expect(stopOne.name).toNot(beNil())
        expect(stopOne.routeIDs).toNot(beNil())
        expect(stopOne.routeIDs.count) == 12
        expect(stopOne.routes).toNot(beNil())
        expect(stopOne.routes.count) == 12
        expect(stopOne.routeTypes).toNot(beNil())
        expect(stopOne.prioritizedRouteTypeForDisplay).toNot(beNil())
        expect(stopOne.wheelchairBoarding).toNot(beNil())

        expect(stopOne) == stopTwo
        expect(stopOne.routes) == stopTwo.routes
    }
}
