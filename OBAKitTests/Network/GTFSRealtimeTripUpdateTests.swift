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
        let cases: [(TransitRealtime_TripDescriptor.ScheduleRelationship, GTFSRTTripScheduleRelationship, Bool)] = [
            (.scheduled, .scheduled, false),
            (.added, .added, false),
            (.unscheduled, .unscheduled, false),
            (.canceled, .canceled, true),
            (.replacement, .replacement, false),
            (.duplicated, .duplicated, false),
            (.deleted, .deleted, true),
            (.new, .newTrip, false),
        ]

        for (protoRel, expectedDomainRel, isCanceled) in cases {
            var proto = TransitRealtime_TripUpdate()
            proto.trip.scheduleRelationship = protoRel
            let parsed = GTFSRTTripUpdate(protobuf: proto)

            #expect(parsed.scheduleRelationship == expectedDomainRel)
            #expect(parsed.scheduleRelationship.isCanceledOrDeleted == isCanceled)
        }
    }

    // MARK: - Delay Reconciler Tests

    @Test func `Reconciler matches stop by stopSequence and applies arrival and departure delays`() {
        let arrDep = makeArrivalDeparture(
            tripID: "trip_express",
            stopID: "stop_10",
            stopSequence: 4,
            scheduledArrival: Date(timeIntervalSince1970: 1_700_000_500),
            scheduledDeparture: Date(timeIntervalSince1970: 1_700_000_600)
        )

        let stopUpdate = GTFSRTStopTimeUpdate(
            stopSequence: 4,
            stopID: "stop_10",
            arrival: GTFSRTStopTimeEvent(delay: 90),
            departure: GTFSRTStopTimeEvent(delay: 150),
            scheduleRelationship: .scheduled
        )
        let tripUpdate = GTFSRTTripUpdate(
            tripID: "trip_express",
            scheduleRelationship: .scheduled,
            stopTimeUpdates: [stopUpdate]
        )

        let reconciler = GTFSRealtimeDelayReconciler.standard
        let result = reconciler.reconcile(arrivalDeparture: arrDep, with: tripUpdate)

        #expect(result.isCanceled == false)
        #expect(result.isSkipped == false)
        #expect(result.isNoData == false)
        #expect(result.arrivalDelay == 90)
        #expect(result.departureDelay == 150)
        #expect(result.reconciledArrival == Date(timeIntervalSince1970: 1_700_000_590))
        #expect(result.reconciledDeparture == Date(timeIntervalSince1970: 1_700_000_750))
        #expect(result.isLive == true)
    }

    @Test func `Reconciler matches stop by stopID when sequence is unspecified`() {
        let arrDep = makeArrivalDeparture(
            tripID: "trip_local",
            stopID: "stop_pike",
            stopSequence: 12,
            scheduledArrival: Date(timeIntervalSince1970: 1_700_000_000),
            scheduledDeparture: Date(timeIntervalSince1970: 1_700_000_050)
        )

        let stopUpdate = GTFSRTStopTimeUpdate(
            stopSequence: nil,
            stopID: "stop_pike",
            arrival: GTFSRTStopTimeEvent(delay: -45),
            departure: GTFSRTStopTimeEvent(delay: -45),
            scheduleRelationship: .scheduled
        )
        let tripUpdate = GTFSRTTripUpdate(
            tripID: "trip_local",
            scheduleRelationship: .scheduled,
            stopTimeUpdates: [stopUpdate]
        )

        let reconciler = GTFSRealtimeDelayReconciler.standard
        let result = reconciler.reconcile(arrivalDeparture: arrDep, with: tripUpdate)

        #expect(result.arrivalDelay == -45)
        #expect(result.departureDelay == -45)
        #expect(result.reconciledArrival == Date(timeIntervalSince1970: 1_700_000_000 - 45))
        #expect(result.reconciledDeparture == Date(timeIntervalSince1970: 1_700_000_050 - 45))
    }

    @Test func `Reconciler falls back to tripDelay when stop has no specific stop time update`() {
        let arrDep = makeArrivalDeparture(
            tripID: "trip_unmatched_stop",
            stopID: "stop_unknown",
            stopSequence: 7,
            scheduledArrival: Date(timeIntervalSince1970: 1_700_001_000),
            scheduledDeparture: Date(timeIntervalSince1970: 1_700_001_060)
        )

        let tripUpdate = GTFSRTTripUpdate(
            tripID: "trip_unmatched_stop",
            scheduleRelationship: .scheduled,
            tripDelay: 240, // 4 minutes late at trip level
            stopTimeUpdates: []
        )

        let reconciler = GTFSRealtimeDelayReconciler.standard
        let result = reconciler.reconcile(arrivalDeparture: arrDep, with: tripUpdate)

        #expect(result.arrivalDelay == 240)
        #expect(result.departureDelay == 240)
        #expect(result.reconciledArrival == Date(timeIntervalSince1970: 1_700_001_240))
        #expect(result.reconciledDeparture == Date(timeIntervalSince1970: 1_700_001_300))
    }

    @Test func `Reconciler handles canceled and deleted trips`() {
        let arrDep = makeArrivalDeparture(tripID: "trip_canceled")

        let canceledUpdate = GTFSRTTripUpdate(
            tripID: "trip_canceled",
            scheduleRelationship: .canceled
        )

        let reconciler = GTFSRealtimeDelayReconciler.standard
        let canceledResult = reconciler.reconcile(arrivalDeparture: arrDep, with: canceledUpdate)

        #expect(canceledResult.isCanceled == true)
        #expect(canceledResult.reconciledArrival == nil)
        #expect(canceledResult.reconciledDeparture == nil)

        let deletedUpdate = GTFSRTTripUpdate(
            tripID: "trip_canceled",
            scheduleRelationship: .deleted
        )
        let deletedResult = reconciler.reconcile(arrivalDeparture: arrDep, with: deletedUpdate)

        #expect(deletedResult.isCanceled == true)
    }

    @Test func `Reconciler handles skipped stop relationship`() {
        let arrDep = makeArrivalDeparture(
            tripID: "trip_detour",
            stopID: "stop_skipped",
            stopSequence: 2
        )

        let stopUpdate = GTFSRTStopTimeUpdate(
            stopSequence: 2,
            stopID: "stop_skipped",
            scheduleRelationship: .skipped
        )
        let tripUpdate = GTFSRTTripUpdate(
            tripID: "trip_detour",
            scheduleRelationship: .scheduled,
            stopTimeUpdates: [stopUpdate]
        )

        let reconciler = GTFSRealtimeDelayReconciler.standard
        let result = reconciler.reconcile(arrivalDeparture: arrDep, with: tripUpdate)

        #expect(result.isCanceled == false)
        #expect(result.isSkipped == true)
        #expect(result.reconciledArrival == nil)
        #expect(result.reconciledDeparture == nil)
    }

    @Test func `Reconciler handles NO_DATA stop relationship`() {
        let arrDep = makeArrivalDeparture(
            tripID: "trip_partially_tracked",
            stopID: "stop_no_data",
            stopSequence: 15
        )

        let stopUpdate = GTFSRTStopTimeUpdate(
            stopSequence: 15,
            stopID: "stop_no_data",
            scheduleRelationship: .noData
        )
        let tripUpdate = GTFSRTTripUpdate(
            tripID: "trip_partially_tracked",
            scheduleRelationship: .scheduled,
            tripDelay: 120, // should not be applied because NO_DATA explicitly disables prediction
            stopTimeUpdates: [stopUpdate]
        )

        let reconciler = GTFSRealtimeDelayReconciler.standard
        let result = reconciler.reconcile(arrivalDeparture: arrDep, with: tripUpdate)

        #expect(result.isNoData == true)
        #expect(result.arrivalDelay == nil)
        #expect(result.departureDelay == nil)
        #expect(result.isLive == false)
    }

    @Test func `Reconciler evaluates scheduleStatus from delay`() {
        let arrDepArriving = makeArrivalDeparture(
            tripID: "trip_eval",
            stopSequence: 1 // arriving
        )

        // Delayed > 90 seconds
        let delayedResult = GTFSRealtimeDelayReconciler.standard.reconcile(
            arrivalDeparture: arrDepArriving,
            with: GTFSRTTripUpdate(tripID: "trip_eval", tripDelay: 120)
        )
        #expect(delayedResult.scheduleStatus == .delayed)

        // On time: -90s to +90s
        let onTimeResult = GTFSRealtimeDelayReconciler.standard.reconcile(
            arrivalDeparture: arrDepArriving,
            with: GTFSRTTripUpdate(tripID: "trip_eval", tripDelay: 30)
        )
        #expect(onTimeResult.scheduleStatus == .onTime)

        // Early < -90 seconds
        let earlyResult = GTFSRealtimeDelayReconciler.standard.reconcile(
            arrivalDeparture: arrDepArriving,
            with: GTFSRTTripUpdate(tripID: "trip_eval", tripDelay: -100)
        )
        #expect(earlyResult.scheduleStatus == .early)
    }

    @Test func `Reconcile batch array matches corresponding trips and preserves unmatched items`() {
        let arrDep1 = makeArrivalDeparture(tripID: "trip_1", stopSequence: 1)
        let arrDep2 = makeArrivalDeparture(tripID: "trip_2", stopSequence: 2)
        let arrDep3 = makeArrivalDeparture(tripID: "trip_3", stopSequence: 3)

        let update1 = GTFSRTTripUpdate(tripID: "trip_1", tripDelay: 60)
        let update3 = GTFSRTTripUpdate(tripID: "trip_3", scheduleRelationship: .canceled)

        let reconciler = GTFSRealtimeDelayReconciler.standard
        let results = reconciler.reconcile(
            arrivalDepartures: [arrDep1, arrDep2, arrDep3],
            with: [update1, update3]
        )

        #expect(results.count == 3)
        #expect(results[0].arrivalDelay == 60)
        #expect(results[1].isLive == false)
        #expect(results[1].tripUpdate == nil)
        #expect(results[2].isCanceled == true)
    }

    @Test func `ArrivalDeparture applying reconciliation generates updated instance`() {
        let arrDep = makeArrivalDeparture(tripID: "trip_apply", stopSequence: 5)
        let stopUpdate = GTFSRTStopTimeUpdate(
            stopSequence: 5,
            stopID: "stop_200",
            arrival: GTFSRTStopTimeEvent(delay: 180),
            departure: GTFSRTStopTimeEvent(delay: 200),
            departureOccupancyStatus: .manySeatsAvailable
        )
        let tripUpdate = GTFSRTTripUpdate(
            tripID: "trip_apply",
            vehicleID: "veh_999",
            stopTimeUpdates: [stopUpdate]
        )

        let reconciliation = GTFSRealtimeDelayReconciler.standard.reconcile(arrivalDeparture: arrDep, with: tripUpdate)
        let updatedArrDep = arrDep.applying(reconciliation: reconciliation)

        #expect(updatedArrDep.predicted == true)
        #expect(updatedArrDep.vehicleID == "veh_999")
        #expect(updatedArrDep.predictedArrival == arrDep.scheduledArrival.addingTimeInterval(180))
        #expect(updatedArrDep.predictedDeparture == arrDep.scheduledDeparture.addingTimeInterval(200))
        #expect(updatedArrDep.occupancyStatus == .manySeatsAvailable)
    }

    @Test func `Reconciles custom GTFSRTScheduleItem protocol conformance`() {
        let item = GTFSRTScheduleItem(
            tripID: "trip_custom",
            stopID: "stop_custom",
            stopSequence: 8,
            scheduledArrival: Date(timeIntervalSince1970: 1_700_000_100),
            scheduledDeparture: Date(timeIntervalSince1970: 1_700_000_200)
        )

        let tripUpdate = GTFSRTTripUpdate(
            tripID: "trip_custom",
            tripDelay: -60
        )

        let result = GTFSRealtimeDelayReconciler.standard.reconcile(schedule: item, with: tripUpdate)
        #expect(result.arrivalDelay == -60)
        #expect(result.reconciledArrival == Date(timeIntervalSince1970: 1_700_000_040))
        #expect(result.reconciledDeparture == Date(timeIntervalSince1970: 1_700_000_140))
    }

    @Test func `OccupancyStatus mapping from protobuf maps all cases correctly`() {
        let mappings: [(TransitRealtime_VehiclePosition.OccupancyStatus, ArrivalDeparture.OccupancyStatus)] = [
            (.empty, .empty),
            (.manySeatsAvailable, .manySeatsAvailable),
            (.fewSeatsAvailable, .fewSeatsAvailable),
            (.standingRoomOnly, .standingRoomOnly),
            (.crushedStandingRoomOnly, .crushedStandingRoomOnly),
            (.full, .full),
            (.notAcceptingPassengers, .notAcceptingPassengers),
            (.noDataAvailable, .noDataAvailable),
            (.notBoardable, .notBoardable),
        ]

        for (protoStatus, domainStatus) in mappings {
            #expect(ArrivalDeparture.OccupancyStatus(protobuf: protoStatus) == domainStatus)
        }
    }

    // MARK: - CodeRabbit Review Resolution Tests

    @Test func `DUPLICATED trip retains target trip identity and startDate from tripProperties`() {
        var proto = TransitRealtime_TripUpdate()
        proto.trip.tripID = "source_trip_123"
        proto.trip.scheduleRelationship = .duplicated
        proto.tripProperties.tripID = "target_trip_456"
        proto.tripProperties.startDate = "20261122"
        proto.tripProperties.startTime = "08:30:00"

        let update = GTFSRTTripUpdate(protobuf: proto)
        #expect(update.tripID == "target_trip_456")
        #expect(update.sourceTripID == "source_trip_123")
        #expect(update.startDate == "20261122")
        #expect(update.startTime == "08:30:00")
        #expect(update.scheduleRelationship == .duplicated)
    }

    @Test func `Scheduled fallback without prediction does not treat times as live`() {
        let arrDep = makeArrivalDeparture(
            tripID: "trip_partially_predicted",
            stopID: "stop_1",
            stopSequence: 1,
            predicted: false
        )

        // Stop update only for sequence 10; trip has no tripDelay
        let stopUpdate = GTFSRTStopTimeUpdate(
            stopSequence: 10,
            stopID: "stop_10",
            arrival: GTFSRTStopTimeEvent(delay: 120),
            scheduleRelationship: .scheduled
        )
        let tripUpdate = GTFSRTTripUpdate(
            tripID: "trip_partially_predicted",
            scheduleRelationship: .scheduled,
            tripDelay: nil,
            stopTimeUpdates: [stopUpdate]
        )

        let reconciler = GTFSRealtimeDelayReconciler.standard
        let result = reconciler.reconcile(arrivalDeparture: arrDep, with: tripUpdate)

        #expect(result.isLive == false)
        #expect(result.reconciledArrival == nil)
        #expect(result.reconciledDeparture == nil)
        #expect(result.arrivalDelay == nil)

        let applied = arrDep.applying(reconciliation: result)
        #expect(applied.predicted == false)
        #expect(applied.predictedArrival == nil)
    }

    @Test func `Downstream delay propagates to subsequent stops`() {
        let scheduleItem = GTFSRTScheduleItem(
            tripID: "trip_propagate",
            stopID: "stop_seq_4",
            stopSequence: 4,
            scheduledArrival: Date(timeIntervalSince1970: 1_700_001_000),
            scheduledDeparture: Date(timeIntervalSince1970: 1_700_001_100)
        )

        let seq3Update = GTFSRTStopTimeUpdate(
            stopSequence: 3,
            stopID: "stop_seq_3",
            departure: GTFSRTStopTimeEvent(delay: 300)
        )
        let tripUpdate = GTFSRTTripUpdate(
            tripID: "trip_propagate",
            tripDelay: 30, // trip delay should be overridden by upstream sequence 3 delay
            stopTimeUpdates: [seq3Update]
        )

        let result = GTFSRealtimeDelayReconciler.standard.reconcile(schedule: scheduleItem, with: tripUpdate)
        #expect(result.isLive == true)
        #expect(result.arrivalDelay == 300)
        #expect(result.departureDelay == 300)
        #expect(result.reconciledArrival == Date(timeIntervalSince1970: 1_700_001_300))
    }

    @Test func `Downstream NO_DATA suppresses fallback delays`() {
        let scheduleItem = GTFSRTScheduleItem(
            tripID: "trip_no_data_prop",
            stopID: "stop_seq_4",
            stopSequence: 4,
            scheduledArrival: Date(timeIntervalSince1970: 1_700_001_000)
        )

        let seq3Update = GTFSRTStopTimeUpdate(
            stopSequence: 3,
            stopID: "stop_seq_3",
            scheduleRelationship: .noData
        )
        let tripUpdate = GTFSRTTripUpdate(
            tripID: "trip_no_data_prop",
            tripDelay: 60,
            stopTimeUpdates: [seq3Update]
        )

        let result = GTFSRealtimeDelayReconciler.standard.reconcile(schedule: scheduleItem, with: tripUpdate)
        #expect(result.isNoData == true)
        #expect(result.isLive == false)
        #expect(result.arrivalDelay == nil)
        #expect(result.reconciledArrival == nil)
    }

    @Test func `Conflicting stopSequence rejects stopID fallback`() {
        let scheduleItem = GTFSRTScheduleItem(
            tripID: "trip_loop",
            stopID: "stop_common",
            stopSequence: 8
        )

        // Update for stop_common at sequence 2 (e.g. earlier visit on a loop)
        let updateSeq2 = GTFSRTStopTimeUpdate(
            stopSequence: 2,
            stopID: "stop_common",
            scheduleRelationship: .skipped
        )
        let tripUpdate = GTFSRTTripUpdate(
            tripID: "trip_loop",
            stopTimeUpdates: [updateSeq2]
        )

        let result = GTFSRealtimeDelayReconciler.standard.reconcile(schedule: scheduleItem, with: tripUpdate)
        // Sequence 8 must not match sequence 2's skipped state
        #expect(result.isSkipped == false)
        #expect(result.matchedStopTimeUpdate == nil)
    }

    @Test func `Batch reconciliation matches agency-prefixed REST trip IDs with raw feed IDs`() {
        let arrDep = makeArrivalDeparture(tripID: "1_15551341", stopID: "1_200", stopSequence: 5)
        let feedUpdate = GTFSRTTripUpdate(tripID: "15551341", tripDelay: 120)

        let results = GTFSRealtimeDelayReconciler.standard.reconcile(
            arrivalDepartures: [arrDep],
            with: [feedUpdate]
        )

        #expect(results.count == 1)
        #expect(results[0].arrivalDelay == 120)
        #expect(results[0].isLive == true)
    }

    @Test func `Service date disambiguates multiple candidate trip updates`() {
        // 2026-11-22 00:00:00 UTC = 1795305600
        let serviceDate22 = Date(timeIntervalSince1970: 1_795_305_600)
        let arrDep = ArrivalDeparture(
            arrivalEnabled: true,
            routeID: "route_1",
            scheduledArrival: serviceDate22.addingTimeInterval(3600),
            scheduledDeparture: serviceDate22.addingTimeInterval(3700),
            serviceDate: serviceDate22,
            stopID: "stop_1",
            tripID: "trip_daily"
        )

        let updateYesterday = GTFSRTTripUpdate(
            tripID: "trip_daily",
            startDate: "20261121",
            tripDelay: 60
        )
        let updateToday = GTFSRTTripUpdate(
            tripID: "trip_daily",
            startDate: "20261122",
            tripDelay: 300
        )

        let results = GTFSRealtimeDelayReconciler.standard.reconcile(
            arrivalDepartures: [arrDep],
            with: [updateYesterday, updateToday]
        )

        #expect(results.count == 1)
        #expect(results[0].arrivalDelay == 300)
    }

    @Test func `NO_DATA update clears prior predictions and reconciledDate returns scheduled`() {
        let schedArrival = Date(timeIntervalSince1970: 1_700_001_000)
        let arrDep = makeArrivalDeparture(
            tripID: "trip_tracked",
            stopID: "stop_10",
            stopSequence: 1,
            scheduledArrival: schedArrival,
            predictedArrival: schedArrival.addingTimeInterval(180),
            predicted: true
        )

        let stopUpdate = GTFSRTStopTimeUpdate(
            stopID: "stop_10",
            scheduleRelationship: .noData
        )
        let tripUpdate = GTFSRTTripUpdate(
            tripID: "trip_tracked",
            stopTimeUpdates: [stopUpdate]
        )

        let result = GTFSRealtimeDelayReconciler.standard.reconcile(arrivalDeparture: arrDep, with: tripUpdate)
        #expect(result.isNoData == true)
        #expect(result.reconciledDate == schedArrival)

        let applied = arrDep.applying(reconciliation: result)
        #expect(applied.predicted == false)
        #expect(applied.predictedArrival == nil)
    }

    @Test func `Unmatched update preserves existing REST predictions`() {
        let schedArrival = Date(timeIntervalSince1970: 1_700_001_000)
        let predArrival = schedArrival.addingTimeInterval(300)
        let arrDep = makeArrivalDeparture(
            tripID: "trip_rest_live",
            stopID: "stop_20",
            scheduledArrival: schedArrival,
            predictedArrival: predArrival,
            predicted: true
        )

        let result = GTFSRealtimeDelayReconciler.standard.reconcile(arrivalDeparture: arrDep, with: nil)
        #expect(result.isLive == false)

        let applied = arrDep.applying(reconciliation: result)
        #expect(applied.predicted == true)
        #expect(applied.predictedArrival == predArrival)
    }

    @Test func `Applying reconciliation with nil route and trip does not trap`() {
        let arrDep = ArrivalDeparture(
            arrivalEnabled: true,
            routeID: "route_1",
            scheduledArrival: Date(timeIntervalSince1970: 1_700_000_000),
            scheduledDeparture: Date(timeIntervalSince1970: 1_700_000_100),
            serviceDate: Date(timeIntervalSince1970: 1_700_000_000),
            stopID: "stop_isolated",
            tripID: "trip_isolated"
        )

        let tripUpdate = GTFSRTTripUpdate(
            tripID: "trip_isolated",
            tripDelay: 90
        )

        let result = GTFSRealtimeDelayReconciler.standard.reconcile(arrivalDeparture: arrDep, with: tripUpdate)
        let applied = arrDep.applying(reconciliation: result)

        #expect(applied.predicted == true)
        #expect(applied.predictedArrival == Date(timeIntervalSince1970: 1_700_000_090))
    }

    @Test func `Skipped stop disables boarding and subsequent active update recovers status`() {
        let arrDep = makeArrivalDeparture(tripID: "trip_status", stopID: "stop_status", stopSequence: 1)

        let skippedUpdate = GTFSRTTripUpdate(
            tripID: "trip_status",
            stopTimeUpdates: [GTFSRTStopTimeUpdate(stopID: "stop_status", scheduleRelationship: .skipped)]
        )
        let skippedResult = GTFSRealtimeDelayReconciler.standard.reconcile(arrivalDeparture: arrDep, with: skippedUpdate)
        let skippedArrDep = arrDep.applying(reconciliation: skippedResult)

        #expect(skippedArrDep.status == "skipped")
        #expect(skippedArrDep.arrivalEnabled == false)
        #expect(skippedArrDep.departureEnabled == false)

        // Now a subsequent update arrives with active predictions
        let activeUpdate = GTFSRTTripUpdate(
            tripID: "trip_status",
            stopTimeUpdates: [GTFSRTStopTimeUpdate(stopID: "stop_status", arrival: GTFSRTStopTimeEvent(delay: 60))]
        )
        let activeResult = GTFSRealtimeDelayReconciler.standard.reconcile(arrivalDeparture: skippedArrDep, with: activeUpdate)
        let recoveredArrDep = skippedArrDep.applying(reconciliation: activeResult)

        #expect(recoveredArrDep.status == "default")
        #expect(recoveredArrDep.arrivalEnabled == true)
        #expect(recoveredArrDep.departureEnabled == true)
        #expect(recoveredArrDep.predicted == true)
    }

    @Test func `ScheduleStatus evaluates exact timestamps and 90-second boundary`() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let arrDep = makeArrivalDeparture(
            tripID: "trip_boundary",
            stopID: "stop_b",
            stopSequence: 1, // arriving
            scheduledArrival: base
        )

        // Exact timestamp 89 seconds late (< 90s) -> onTime
        let update89 = GTFSRTTripUpdate(
            tripID: "trip_boundary",
            stopTimeUpdates: [
                GTFSRTStopTimeUpdate(
                    stopID: "stop_b",
                    arrival: GTFSRTStopTimeEvent(time: base.addingTimeInterval(89))
                )
            ]
        )
        let result89 = GTFSRealtimeDelayReconciler.standard.reconcile(arrivalDeparture: arrDep, with: update89)
        #expect(result89.scheduleStatus == .onTime)

        // Exact timestamp 90 seconds late (>= 90s) -> delayed
        let update90 = GTFSRTTripUpdate(
            tripID: "trip_boundary",
            stopTimeUpdates: [
                GTFSRTStopTimeUpdate(
                    stopID: "stop_b",
                    arrival: GTFSRTStopTimeEvent(time: base.addingTimeInterval(90))
                )
            ]
        )
        let result90 = GTFSRealtimeDelayReconciler.standard.reconcile(arrivalDeparture: arrDep, with: update90)
        #expect(result90.scheduleStatus == .delayed)

        // Exact timestamp 91 seconds early (< -90s) -> early
        let updateEarly = GTFSRTTripUpdate(
            tripID: "trip_boundary",
            stopTimeUpdates: [
                GTFSRTStopTimeUpdate(
                    stopID: "stop_b",
                    arrival: GTFSRTStopTimeEvent(time: base.addingTimeInterval(-91))
                )
            ]
        )
        let resultEarly = GTFSRealtimeDelayReconciler.standard.reconcile(arrivalDeparture: arrDep, with: updateEarly)
        #expect(resultEarly.scheduleStatus == .early)
    }
}
