//
//  ArrivalDepartureDeepLinkTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try

@Suite(.serialized)
final class ArrivalDepartureDeepLinkTests: OBATestCase {

    // MARK: - Codable Round-Trip

    @Test func `Round tripping success`() {
        let deepLink1 = ArrivalDepartureDeepLink(title: "Title", regionID: 1, stopID: "1234", tripID: "9876", serviceDate: Date(timeIntervalSinceReferenceDate: 0), stopSequence: 7, vehicleID: "3456")
        let deepLink2 = try! Fixtures.roundtripCodable(type: ArrivalDepartureDeepLink.self, model: deepLink1)

        #expect(deepLink2 == deepLink1)

        #expect(deepLink2.title == deepLink1.title)
        #expect(deepLink2.regionID == deepLink1.regionID)
        #expect(deepLink2.stopID == deepLink1.stopID)
        #expect(deepLink2.tripID == deepLink1.tripID)
        #expect(deepLink2.serviceDate == deepLink1.serviceDate)
        #expect(deepLink2.stopSequence == deepLink1.stopSequence)
        #expect(deepLink2.vehicleID == deepLink1.vehicleID)
    }

    @Test func `Round tripping with destination stop ID`() {
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

        #expect(deepLink2 == deepLink1)
        #expect(deepLink2.destinationStopID == "1_431")
        #expect(deepLink2.title == "Route 550 - Bellevue")
        #expect(deepLink2.regionID == 1)
        #expect(deepLink2.stopID == "1_75403")
        #expect(deepLink2.tripID == "1_550_trip")
        #expect(deepLink2.serviceDate == Date(timeIntervalSince1970: 1_710_273_600))
        #expect(deepLink2.stopSequence == 12)
        #expect(deepLink2.vehicleID == "1_v100")
    }

    @Test func `Round tripping without destination stop ID is nil`() {
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

        #expect(deepLink2 == deepLink1)
        #expect(deepLink2.destinationStopID == nil)
        #expect(deepLink2.vehicleID == nil)
    }

    // MARK: - Equality

    @Test func `Is equal matching destination stop ID`() {
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
        #expect(link1.isEqual(link2) == true)
    }

    @Test func `Is equal different destination stop ID`() {
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
        #expect(link1.isEqual(link2) == false)
    }

    @Test func `Is equal nil vs non nil destination stop ID`() {
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
        #expect(link1.isEqual(link2) == false)
    }

    // MARK: - Hashing

    @Test func `Hash includes destination stop ID`() {
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
        #expect(link1.hash != link2.hash)
    }

    @Test func `Hash nil destination stop ID consistent with equality`() {
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
        #expect(link1.isEqual(link2) == true)
        #expect(link1.hash == link2.hash)
    }
}
