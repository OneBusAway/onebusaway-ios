//
//  ArrivalDepartureDeepLinkTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import XCTest
import Nimble
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try

class ArrivalDepartureDeepLinkTests: OBATestCase {

    func test_roundTripping_success() {
        let deepLink1 = ArrivalDepartureDeepLink(title: "Title", regionID: 1, stopID: "1234", tripID: "9876", serviceDate: Date(timeIntervalSinceReferenceDate: 0), stopSequence: 7, vehicleID: "3456")
        let deepLink2 = try! Fixtures.roundtripCodable(type: ArrivalDepartureDeepLink.self, model: deepLink1)

        expect(deepLink2) == deepLink1

        expect(deepLink2.title) == deepLink1.title
        expect(deepLink2.regionID) == deepLink1.regionID
        expect(deepLink2.stopID) == deepLink1.stopID
        expect(deepLink2.tripID) == deepLink1.tripID
        expect(deepLink2.serviceDate) == deepLink1.serviceDate
        expect(deepLink2.stopSequence) == deepLink1.stopSequence
        expect(deepLink2.vehicleID) == deepLink1.vehicleID
    }
}
