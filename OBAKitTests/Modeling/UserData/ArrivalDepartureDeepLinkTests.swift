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

    // MARK: - Codable Round-Trip

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

    func test_roundTripping_withDestinationStopID() {
        let deepLink1 = ArrivalDepartureDeepLink(
            title: "Route 550 - Bellevue",
            regionID: 1,
            stopID: "1_75403",
            tripID: "1_550_trip",
            serviceDate: Date(timeIntervalSince1970: 1_710_273_600),
            stopSequence: 12,
            vehicleID: "1_v100",
            destinationStopID: "1_431"
        )
        let deepLink2 = try! Fixtures.roundtripCodable(type: ArrivalDepartureDeepLink.self, model: deepLink1)

        expect(deepLink2) == deepLink1
        expect(deepLink2.destinationStopID) == "1_431"
        expect(deepLink2.title) == "Route 550 - Bellevue"
        expect(deepLink2.regionID) == 1
        expect(deepLink2.stopID) == "1_75403"
        expect(deepLink2.tripID) == "1_550_trip"
        expect(deepLink2.serviceDate) == Date(timeIntervalSince1970: 1_710_273_600)
        expect(deepLink2.stopSequence) == 12
        expect(deepLink2.vehicleID) == "1_v100"
    }

    func test_roundTripping_withoutDestinationStopID_isNil() {
        let deepLink1 = ArrivalDepartureDeepLink(
            title: "Route 545",
            regionID: 2,
            stopID: "1_29261",
            tripID: "1_545_trip",
            serviceDate: Date(timeIntervalSince1970: 1_710_360_000),
            stopSequence: 3,
            vehicleID: nil
        )
        let deepLink2 = try! Fixtures.roundtripCodable(type: ArrivalDepartureDeepLink.self, model: deepLink1)

        expect(deepLink2) == deepLink1
        expect(deepLink2.destinationStopID).to(beNil())
        expect(deepLink2.vehicleID).to(beNil())
    }

    // MARK: - Equality

    func test_isEqual_matchingDestinationStopID() {
        let link1 = ArrivalDepartureDeepLink(
            title: "10", regionID: 1, stopID: "A", tripID: "T",
            serviceDate: Date(timeIntervalSince1970: 1_500_000_000),
            stopSequence: 1, vehicleID: nil, destinationStopID: "Z"
        )
        let link2 = ArrivalDepartureDeepLink(
            title: "10", regionID: 1, stopID: "A", tripID: "T",
            serviceDate: Date(timeIntervalSince1970: 1_500_000_000),
            stopSequence: 1, vehicleID: nil, destinationStopID: "Z"
        )
        expect(link1.isEqual(link2)) == true
    }

    func test_isEqual_differentDestinationStopID() {
        let link1 = ArrivalDepartureDeepLink(
            title: "10", regionID: 1, stopID: "A", tripID: "T",
            serviceDate: Date(timeIntervalSince1970: 1_500_000_000),
            stopSequence: 1, vehicleID: nil, destinationStopID: "Z"
        )
        let link2 = ArrivalDepartureDeepLink(
            title: "10", regionID: 1, stopID: "A", tripID: "T",
            serviceDate: Date(timeIntervalSince1970: 1_500_000_000),
            stopSequence: 1, vehicleID: nil, destinationStopID: "Y"
        )
        expect(link1.isEqual(link2)) == false
    }

    func test_isEqual_nilVsNonNilDestinationStopID() {
        let link1 = ArrivalDepartureDeepLink(
            title: "10", regionID: 1, stopID: "A", tripID: "T",
            serviceDate: Date(timeIntervalSince1970: 1_500_000_000),
            stopSequence: 1, vehicleID: nil, destinationStopID: nil
        )
        let link2 = ArrivalDepartureDeepLink(
            title: "10", regionID: 1, stopID: "A", tripID: "T",
            serviceDate: Date(timeIntervalSince1970: 1_500_000_000),
            stopSequence: 1, vehicleID: nil, destinationStopID: "Z"
        )
        expect(link1.isEqual(link2)) == false
    }

    // MARK: - Hashing

    func test_hash_includesDestinationStopID() {
        let link1 = ArrivalDepartureDeepLink(
            title: "10", regionID: 1, stopID: "A", tripID: "T",
            serviceDate: Date(timeIntervalSince1970: 1_500_000_000),
            stopSequence: 1, vehicleID: nil, destinationStopID: "Z"
        )
        let link2 = ArrivalDepartureDeepLink(
            title: "10", regionID: 1, stopID: "A", tripID: "T",
            serviceDate: Date(timeIntervalSince1970: 1_500_000_000),
            stopSequence: 1, vehicleID: nil, destinationStopID: "Y"
        )
        expect(link1.hash) != link2.hash
    }

    func test_hash_nilDestinationStopID_consistentWithEquality() {
        let link1 = ArrivalDepartureDeepLink(
            title: "10", regionID: 1, stopID: "A", tripID: "T",
            serviceDate: Date(timeIntervalSince1970: 1_500_000_000),
            stopSequence: 1, vehicleID: nil
        )
        let link2 = ArrivalDepartureDeepLink(
            title: "10", regionID: 1, stopID: "A", tripID: "T",
            serviceDate: Date(timeIntervalSince1970: 1_500_000_000),
            stopSequence: 1, vehicleID: nil
        )
        expect(link1.isEqual(link2)) == true
        expect(link1.hash) == link2.hash
    }
}
