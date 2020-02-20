//
//  ArrivalDepartureDeepLinkTests.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 1/30/20.
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
        let deepLink2 = try! roundtripCodable(type: ArrivalDepartureDeepLink.self, model: deepLink1)

        expect(deepLink2) == deepLink1

        expect(deepLink2.title) == deepLink1.title
        expect(deepLink2.stopID) == deepLink1.stopID
        expect(deepLink2.tripID) == deepLink1.tripID
        expect(deepLink2.serviceDate) == deepLink1.serviceDate
        expect(deepLink2.stopSequence) == deepLink1.stopSequence
        expect(deepLink2.vehicleID) == deepLink1.vehicleID
    }
}
