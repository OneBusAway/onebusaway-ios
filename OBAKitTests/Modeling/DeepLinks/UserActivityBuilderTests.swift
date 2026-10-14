//
//  UserActivityBuilderTests.swift
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

@MainActor
@Suite(.serialized)
final class UserActivityBuilderTests: OBATestCase {
    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    @Test func `Stop user activity sets target content identifier`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = buildApplication(queue: queue, dataLoader: dataLoader)
        let builder = try #require(UserActivityBuilder(application: app, validatingActivityTypes: false))
        let stop = try #require(Fixtures.loadSomeStops().first)
        let region = Fixtures.pugetSoundRegion

        let activity = builder.userActivity(for: stop, region: region)
        let expectedIdentifier = "region_\(region.regionIdentifier)_stop_\(stop.id)"
        #expect(activity.persistentIdentifier == expectedIdentifier)
        #expect(activity.targetContentIdentifier == expectedIdentifier)
        #expect(activity.isEligibleForHandoff == true)
        #expect(activity.isEligibleForSearch == true)
        #expect(activity.isEligibleForPrediction == true)
        #expect(activity.userInfo?[UserActivityBuilder.UserInfoKeys.stopID] as? String == stop.id)
        #expect(activity.userInfo?[UserActivityBuilder.UserInfoKeys.regionID] as? Int == region.regionIdentifier)
    }

    @Test func `Trip user activity sets target content identifier`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = buildApplication(queue: queue, dataLoader: dataLoader)
        let builder = try #require(UserActivityBuilder(application: app, validatingActivityTypes: false))
        let arrivalData: [String: Any] = [
            "arrivalEnabled": true,
            "blockTripSequence": 1,
            "departureEnabled": true,
            "distanceFromStop": 100.0,
            "lastUpdateTime": 1_700_000_000,
            "numberOfStopsAway": 1,
            "predicted": true,
            "routeId": "route_1",
            "routeShortName": "10",
            "scheduledArrivalTime": 1_700_000_000,
            "scheduledDepartureTime": 1_700_000_000,
            "serviceDate": 1_700_000_000,
            "situationIds": [],
            "status": "SCHEDULED",
            "stopId": "stop_1",
            "stopSequence": 5,
            "tripHeadsign": "Downtown",
            "tripId": "trip_1",
            "vehicleId": "vehicle_1"
        ]
        let arrivalDeparture = try Fixtures.dictionaryToModel(type: ArrivalDeparture.self, dictionary: arrivalData)
        let trip = TripConvertible(arrivalDeparture: arrivalDeparture)
        let region = Fixtures.pugetSoundRegion

        let activity = builder.userActivity(for: trip, region: region)
        let unwrappedActivity = try #require(activity)

        let expectedIdentifier = "region_\(region.regionIdentifier)_trip_\(arrivalDeparture.tripID)"
        #expect(unwrappedActivity.persistentIdentifier == expectedIdentifier)
        #expect(unwrappedActivity.targetContentIdentifier == expectedIdentifier)
        #expect(unwrappedActivity.isEligibleForHandoff == true)
        #expect(unwrappedActivity.title == arrivalDeparture.routeAndHeadsign)
    }
}
