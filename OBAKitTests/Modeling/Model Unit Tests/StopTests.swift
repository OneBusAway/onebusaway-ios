//
//  StopTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Testing
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try

class StopTests: OBATestCase {

    func test_RoundtrippingStops() {
        let stopOne = try! Fixtures.loadSomeStops().first!
        let data = try! PropertyListEncoder().encode(stopOne)
        let stopTwo = try! PropertyListDecoder().decode(Stop.self, from: data)

        // `routes` is `[Route]!`, populated by reference-reconnection rather than
        // by decoding, so these two are real nil checks -- not the tautologies
        // that the other `!= nil` assertions in this test were.
        #expect(stopTwo.routes != nil)

        #expect(stopOne.routeIDs.count == 12)
        #expect(stopOne.routes != nil)
        #expect(stopOne.routes.count == 12)

        #expect(stopOne == stopTwo)
        #expect(stopOne.routes == stopTwo.routes)
    }
}
