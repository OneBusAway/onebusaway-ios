//
//  TripBookmarkKeyGroupingTests.swift
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

/// Tests for `TripBookmarkKey` construction, hashing equality,
/// and `Sequence<ArrivalDeparture>.tripKeyGroupedElements` grouping & sorting.
@Suite(.serialized)
final class TripBookmarkKeyGroupingTests: OBATestCase {

    private func makeArrivalDeparture(
        stopID: String = "1_100",
        routeShortName: String = "44",
        routeID: String = "1_44",
        tripHeadsign: String? = "UW Station",
        scheduledArrival: Int = 1_700_000_000
    ) throws -> ArrivalDeparture {
        var dict: [String: Any] = [
            "arrivalEnabled": true,
            "blockTripSequence": 1,
            "departureEnabled": true,
            "distanceFromStop": 100.0,
            "lastUpdateTime": scheduledArrival,
            "numberOfStopsAway": 1,
            "predicted": true,
            "routeId": routeID,
            "routeShortName": routeShortName,
            "scheduledArrivalTime": scheduledArrival,
            "scheduledDepartureTime": scheduledArrival + 60,
            "serviceDate": scheduledArrival,
            "situationIds": [],
            "status": "SCHEDULED",
            "stopId": stopID,
            "stopSequence": 1,
            "tripId": "trip_\(scheduledArrival)",
            "vehicleId": "vehicle_1"
        ]
        if let tripHeadsign {
            dict["tripHeadsign"] = tripHeadsign
        }
        return try Fixtures.dictionaryToModel(type: ArrivalDeparture.self, dictionary: dict)
    }

    // MARK: - Key Equality and Hashing

    @Test func `TripBookmarkKey equality and routeAndHeadsign formatting`() {
        let key1 = TripBookmarkKey(stopID: "stop_1", routeShortName: "44", routeID: "1_44", tripHeadsign: "Ballard")
        let key2 = TripBookmarkKey(stopID: "stop_1", routeShortName: "44", routeID: "1_44", tripHeadsign: "Ballard")
        let key3 = TripBookmarkKey(stopID: "stop_2", routeShortName: "44", routeID: "1_44", tripHeadsign: "Ballard")

        #expect(key1 == key2)
        #expect(key1.hashValue == key2.hashValue)
        #expect(key1 != key3)
        #expect(key1.routeAndHeadsign == "44 - Ballard")
    }

    @Test func `TripBookmarkKey initializes from ArrivalDeparture with fallback for nil headsign`() throws {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        let arrDep = try #require(stopArrivals.arrivalsAndDepartures.first)
        let key = TripBookmarkKey(arrivalDeparture: arrDep)

        #expect(key.stopID == arrDep.stopID)
        #expect(key.routeShortName == arrDep.routeShortName)
        #expect(key.routeID == arrDep.routeID)
        #expect(key.tripHeadsign == (arrDep.tripHeadsign ?? ""))
        #expect(key.routeAndHeadsign == "\(arrDep.routeShortName) - \(arrDep.tripHeadsign ?? "")")

        // Also test direct struct initialization with empty fallback
        let fallbackKey = TripBookmarkKey(stopID: "1_100", routeShortName: "44", routeID: "1_44", tripHeadsign: "")
        #expect(fallbackKey.tripHeadsign == "")
        #expect(fallbackKey.routeAndHeadsign == "44 - ")
    }

    // MARK: - Sequence Grouping and Sorting

    @Test func `tripKeyGroupedElements separates arrivals by key and sorts each group chronologically`() throws {
        let baseTime: Int = 1_700_000_000

        // Route 44 to Ballard (two departures: later, earlier)
        let d44_late = try makeArrivalDeparture(routeShortName: "44", routeID: "1_44", tripHeadsign: "Ballard", scheduledArrival: baseTime + 600)
        let d44_early = try makeArrivalDeparture(routeShortName: "44", routeID: "1_44", tripHeadsign: "Ballard", scheduledArrival: baseTime + 120)

        // Route 44 to UW (different headsign -> different key)
        let d44_uw = try makeArrivalDeparture(routeShortName: "44", routeID: "1_44", tripHeadsign: "UW Station", scheduledArrival: baseTime + 300)

        // Route 10 to Capitol Hill (different route)
        let d10 = try makeArrivalDeparture(routeShortName: "10", routeID: "1_10", tripHeadsign: "Capitol Hill", scheduledArrival: baseTime + 240)

        let departures = [d44_late, d10, d44_early, d44_uw]
        let grouped = departures.tripKeyGroupedElements

        #expect(grouped.count == 3)

        let ballardKey = TripBookmarkKey(stopID: "1_100", routeShortName: "44", routeID: "1_44", tripHeadsign: "Ballard")
        let ballardGroup = try #require(grouped[ballardKey])
        #expect(ballardGroup.count == 2)
        #expect(ballardGroup[0].scheduledArrival == Date(timeIntervalSinceReferenceDate: TimeInterval(baseTime + 120)))
        #expect(ballardGroup[1].scheduledArrival == Date(timeIntervalSinceReferenceDate: TimeInterval(baseTime + 600)))

        let uwKey = TripBookmarkKey(stopID: "1_100", routeShortName: "44", routeID: "1_44", tripHeadsign: "UW Station")
        #expect(grouped[uwKey]?.count == 1)

        let d10Key = TripBookmarkKey(stopID: "1_100", routeShortName: "10", routeID: "1_10", tripHeadsign: "Capitol Hill")
        #expect(grouped[d10Key]?.count == 1)
    }

    @Test func `uniqueTripKeys deduplicates keys across all arrivals`() throws {
        let arr1 = try makeArrivalDeparture(routeShortName: "44", routeID: "1_44", tripHeadsign: "Ballard", scheduledArrival: 1_700_000_100)
        let arr2 = try makeArrivalDeparture(routeShortName: "44", routeID: "1_44", tripHeadsign: "Ballard", scheduledArrival: 1_700_000_200)
        let arr3 = try makeArrivalDeparture(routeShortName: "44", routeID: "1_44", tripHeadsign: "Ballard", scheduledArrival: 1_700_000_300)

        let list = [arr1, arr2, arr3]
        let keys = list.uniqueTripKeys

        #expect(keys.count == 1)
        #expect(keys.first?.routeShortName == "44")
    }

    @Test func `tripKeyGroupedElements on empty list produces empty dictionary`() {
        let empty: [ArrivalDeparture] = []
        #expect(empty.tripKeyGroupedElements.isEmpty)
        #expect(empty.uniqueTripKeys.isEmpty)
    }
}
