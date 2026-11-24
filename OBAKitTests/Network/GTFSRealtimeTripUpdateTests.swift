//
//  GTFSRealtimeTripUpdateTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import SwiftProtobuf
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class GTFSRealtimeTripUpdateTests {

    // MARK: - Helpers

    private func makeFeedData(
        timestamp: UInt64? = nil,
        incrementality: TransitRealtime_FeedHeader.Incrementality? = nil,
        entities: [TransitRealtime_FeedEntity] = []
    ) throws -> Data {
        var message = TransitRealtime_FeedMessage()
        message.header.gtfsRealtimeVersion = "2.0"
        if let timestamp {
            message.header.timestamp = timestamp
        }
        if let incrementality {
            message.header.incrementality = incrementality
        }
        message.entity = entities
        return try message.serializedData()
    }

    private func makeArrivalDeparture(
        tripID: String = "trip_100",
        stopID: String = "stop_200",
        stopSequence: Int = 5,
        scheduledArrival: Date = Date(timeIntervalSince1970: 1_700_001_000),
        scheduledDeparture: Date = Date(timeIntervalSince1970: 1_700_001_100),
        predictedArrival: Date? = nil,
        predictedDeparture: Date? = nil,
        predicted: Bool = false,
        status: String = "default"
    ) -> ArrivalDeparture {
        ArrivalDeparture(
            arrivalEnabled: true,
            blockTripSequence: 1,
            departureEnabled: true,
            distanceFromStop: 250.0,
            frequency: nil,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
            numberOfStopsAway: 2,
            predicted: predicted,
            predictedArrival: predictedArrival,
            predictedDeparture: predictedDeparture,
            routeID: "route_1",
            routeLongName: "RapidRide E Line",
            routeShortName: "E",
            scheduledArrival: scheduledArrival,
            scheduledDeparture: scheduledDeparture,
            serviceDate: Date(timeIntervalSince1970: 1_700_000_000),
            situationIDs: [],
            serviceAlerts: [],
            status: status,
            stopID: stopID,
            stopSequence: stopSequence,
            totalStopsInTrip: 20,
            tripHeadsign: "Downtown Seattle",
            tripID: tripID,
            vehicleID: "veh_10"
        )
    }

    // MARK: - Feed Parsing & Header Validation Tests

    @Test func `Empty data throws emptyData error`() {
        let parser = GTFSRealtimeTripUpdateParser.standard
        #expect(throws: GTFSRealtimeError.emptyData) {
            try parser.parse(data: Data())
        }
    }

    @Test func `Malformed bytes throw malformedData error`() {
        let parser = GTFSRealtimeTripUpdateParser.standard
        let garbage = Data([0xFF, 0xFE, 0xFD, 0x00, 0x01, 0x02, 0xAA, 0xBB])

        #expect(throws: GTFSRealtimeError.self) {
            try parser.parse(data: garbage)
        }
    }

    @Test func `Unsupported differential incrementality is rejected`() throws {
        let parser = GTFSRealtimeTripUpdateParser.standard
        let data = try makeFeedData(incrementality: .differential)

        #expect(throws: GTFSRealtimeError.unsupportedIncrementality(.differential)) {
            try parser.parse(data: data)
        }
    }

    @Test func `Extracts trip updates from valid feed message`() throws {
        var entity1 = TransitRealtime_FeedEntity()
        entity1.id = "E1"
        entity1.tripUpdate.trip.tripID = "trip_A"
        entity1.tripUpdate.trip.routeID = "route_10"
        entity1.tripUpdate.delay = 180

        var entity2 = TransitRealtime_FeedEntity()
        entity2.id = "E2"
        entity2.tripUpdate.trip.tripID = "trip_B"
        entity2.tripUpdate.vehicle.id = "bus_400"
        entity2.tripUpdate.vehicle.label = "Bus 400"

        // Entity 3 is a vehicle position, not a trip update
        var entity3 = TransitRealtime_FeedEntity()
        entity3.id = "E3"
        entity3.vehicle = TransitRealtime_VehiclePosition()

        let data = try makeFeedData(
            timestamp: 1_700_000_000,
            incrementality: .fullDataset,
            entities: [entity1, entity2, entity3]
        )

        let updates = try GTFSRealtimeTripUpdateParser.standard.parse(data: data)
        #expect(updates.count == 2)

        #expect(updates[0].entityID == "E1")
        #expect(updates[0].tripID == "trip_A")
        #expect(updates[0].routeID == "route_10")
        #expect(updates[0].tripDelay == 180)

        #expect(updates[1].entityID == "E2")
        #expect(updates[1].tripID == "trip_B")
        #expect(updates[1].vehicleID == "bus_400")
        #expect(updates[1].vehicleLabel == "Bus 400")
    }

    // MARK: - StopTimeUpdate Delay & Details Extraction Tests

    @Test func `Extracts stop time update arrival and departure delays`() {
        var protoUpdate = TransitRealtime_TripUpdate()
        protoUpdate.trip.tripID = "trip_1"

        var stopUpdate = TransitRealtime_TripUpdate.StopTimeUpdate()
        stopUpdate.stopSequence = 3
        stopUpdate.stopID = "stop_99"
        stopUpdate.arrival.delay = 120 // 2 minutes late
        stopUpdate.departure.delay = -30 // 30 seconds early
        stopUpdate.scheduleRelationship = .scheduled
        protoUpdate.stopTimeUpdate = [stopUpdate]

        let parsed = GTFSRealtimeTripUpdateParser.standard.parse(tripUpdate: protoUpdate)
        #expect(parsed.tripID == "trip_1")
        #expect(parsed.stopTimeUpdates.count == 1)

        let stop = parsed.stopTimeUpdates[0]
        #expect(stop.stopSequence == 3)
        #expect(stop.stopID == "stop_99")
        #expect(stop.arrivalDelay == 120)
        #expect(stop.departureDelay == -30)
        #expect(stop.scheduleRelationship == .scheduled)
    }

    @Test func `Extracts explicit arrival departure timestamps and uncertainty`() {
        var protoUpdate = TransitRealtime_TripUpdate()
        protoUpdate.trip.tripID = "trip_2"

        var stopUpdate = TransitRealtime_TripUpdate.StopTimeUpdate()
        stopUpdate.stopID = "stop_50"
        stopUpdate.arrival.time = 1_700_002_000
        stopUpdate.arrival.uncertainty = 15
        stopUpdate.departure.time = 1_700_002_100
        stopUpdate.departure.uncertainty = 20
        stopUpdate.departureOccupancyStatus = .standingRoomOnly
        protoUpdate.stopTimeUpdate = [stopUpdate]

        let parsed = GTFSRealtimeTripUpdateParser.standard.parse(tripUpdate: protoUpdate)
        let stop = parsed.stopTimeUpdates[0]

        #expect(stop.arrivalTime == Date(timeIntervalSince1970: 1_700_002_000))
        #expect(stop.arrival?.uncertainty == 15)
        #expect(stop.departureTime == Date(timeIntervalSince1970: 1_700_002_100))
        #expect(stop.departure?.uncertainty == 20)
        #expect(stop.departureOccupancyStatus == .standingRoomOnly)
    }

    // MARK: - Schedule Relationship Tests

    @Test func `Handles all StopTimeUpdate schedule relationships`() {
        let cases: [(TransitRealtime_TripUpdate.StopTimeUpdate.ScheduleRelationship, GTFSRTStopTimeScheduleRelationship)] = [
            (.scheduled, .scheduled),
            (.skipped, .skipped),
            (.noData, .noData),
            (.unscheduled, .unscheduled),
        ]

        for (protoRel, expectedDomainRel) in cases {
            var stopUpdate = TransitRealtime_TripUpdate.StopTimeUpdate()
            stopUpdate.scheduleRelationship = protoRel
            let domainUpdate = GTFSRTStopTimeUpdate(protobuf: stopUpdate)

            #expect(domainUpdate.scheduleRelationship == expectedDomainRel)
            if expectedDomainRel == .skipped {
                #expect(domainUpdate.scheduleRelationship.isSkipped == true)
            } else {
                #expect(domainUpdate.scheduleRelationship.isSkipped == false)
            }
            if expectedDomainRel == .noData {
                #expect(domainUpdate.scheduleRelationship.isNoData == true)
            } else {
                #expect(domainUpdate.scheduleRelationship.isNoData == false)
            }
        }
    }

    @Test func `Handles all TripDescriptor schedule relationships`() {
        struct TestCase {
            let protoRel: TransitRealtime_TripDescriptor.ScheduleRelationship
            let expectedDomainRel: GTFSRTTripScheduleRelationship
            let isCanceled: Bool
        }

        let cases: [TestCase] = [
            TestCase(protoRel: .scheduled, expectedDomainRel: .scheduled, isCanceled: false),
            TestCase(protoRel: .added, expectedDomainRel: .added, isCanceled: false),
            TestCase(protoRel: .unscheduled, expectedDomainRel: .unscheduled, isCanceled: false),
            TestCase(protoRel: .canceled, expectedDomainRel: .canceled, isCanceled: true),
            TestCase(protoRel: .replacement, expectedDomainRel: .replacement, isCanceled: false),
            TestCase(protoRel: .duplicated, expectedDomainRel: .duplicated, isCanceled: false),
            TestCase(protoRel: .deleted, expectedDomainRel: .deleted, isCanceled: true),
            TestCase(protoRel: .new, expectedDomainRel: .newTrip, isCanceled: false),
        ]

        for tc in cases {
            var proto = TransitRealtime_TripUpdate()
            proto.trip.scheduleRelationship = tc.protoRel
            let parsed = GTFSRTTripUpdate(protobuf: proto)

            #expect(parsed.scheduleRelationship == tc.expectedDomainRel)
            #expect(parsed.scheduleRelationship.isCanceledOrDeleted == tc.isCanceled)
        }
    }
}
