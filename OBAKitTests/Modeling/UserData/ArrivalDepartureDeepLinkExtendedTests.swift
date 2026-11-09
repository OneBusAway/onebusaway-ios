//
//  ArrivalDepartureDeepLinkExtendedTests.swift
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

/// Tests for `ArrivalDepartureDeepLink` Codable round-tripping, property preservation,
/// equality invariance, and nil destination optional handling.
@Suite(.serialized)
final class ArrivalDepartureDeepLinkExtendedTests: OBATestCase {

    private let testDate = Date(timeIntervalSince1970: 1_650_000_000)

    // MARK: - Direct Initialization and Equality

    @Test func `initialization populates all fields accurately`() {
        let link = ArrivalDepartureDeepLink(
            title: "44 - Ballard",
            regionID: 1,
            stopID: "1_10020",
            tripID: "1_409849",
            serviceDate: testDate,
            stopSequence: 4,
            vehicleID: "1_4321",
            destinationStopID: "1_10914"
        )

        #expect(link.title == "44 - Ballard")
        #expect(link.regionID == 1)
        #expect(link.stopID == "1_10020")
        #expect(link.tripID == "1_409849")
        #expect(link.serviceDate == testDate)
        #expect(link.stopSequence == 4)
        #expect(link.vehicleID == "1_4321")
        #expect(link.destinationStopID == "1_10914")
    }

    @Test func `equality and hash behavior across identical and differing links`() {
        let l1 = ArrivalDepartureDeepLink(
            title: "10 - Downtown",
            regionID: 1,
            stopID: "1_500",
            tripID: "trip_1",
            serviceDate: testDate,
            stopSequence: 2,
            vehicleID: "v_10"
        )

        let l2 = ArrivalDepartureDeepLink(
            title: "10 - Downtown",
            regionID: 1,
            stopID: "1_500",
            tripID: "trip_1",
            serviceDate: testDate,
            stopSequence: 2,
            vehicleID: "v_10"
        )

        let lDiffVehicle = ArrivalDepartureDeepLink(
            title: "10 - Downtown",
            regionID: 1,
            stopID: "1_500",
            tripID: "trip_1",
            serviceDate: testDate,
            stopSequence: 2,
            vehicleID: "v_99"
        )

        let lDiffSeq = ArrivalDepartureDeepLink(
            title: "10 - Downtown",
            regionID: 1,
            stopID: "1_500",
            tripID: "trip_1",
            serviceDate: testDate,
            stopSequence: 5,
            vehicleID: "v_10"
        )

        #expect(l1.isEqual(l2))
        #expect(l1.hash == l2.hash)
        #expect(!l1.isEqual(lDiffVehicle))
        #expect(!l1.isEqual(lDiffSeq))
        #expect(!l1.isEqual("string_object"))
        #expect(!l1.isEqual(nil))
    }

    // MARK: - Codable Serialization

    @Test func `ArrivalDepartureDeepLink round-trips via JSONEncoder and JSONDecoder`() throws {
        let original = ArrivalDepartureDeepLink(
            title: "RapidRide E Line",
            regionID: 2,
            stopID: "1_9910",
            tripID: "trip_rapid",
            serviceDate: testDate,
            stopSequence: 12,
            vehicleID: nil,
            destinationStopID: "1_9999"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ArrivalDepartureDeepLink.self, from: data)

        #expect(decoded.title == original.title)
        #expect(decoded.regionID == original.regionID)
        #expect(decoded.stopID == original.stopID)
        #expect(decoded.tripID == original.tripID)
        #expect(decoded.stopSequence == original.stopSequence)
        #expect(decoded.vehicleID == nil)
        #expect(decoded.destinationStopID == "1_9999")
        #expect(decoded.isEqual(original))
    }

    // MARK: - Initialization from ArrivalDeparture

    @Test func `convenience init from ArrivalDeparture correctly copies properties`() throws {
        let arrDep = try Fixtures.arrivalDeparture(stopID: "1_100", routeID: "1_44", tripID: "1_trip_44")
        let link = ArrivalDepartureDeepLink(arrivalDeparture: arrDep, regionID: 1, destinationStopID: "1_dest")

        #expect(link.stopID == "1_100")
        #expect(link.tripID == "1_trip_44")
        #expect(link.regionID == 1)
        #expect(link.destinationStopID == "1_dest")
    }
}
