//
//  GTFSRealtimeDelayReconcilerTests.swift
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
final class GTFSRealtimeDelayReconcilerTests {

    private func makeArrivalDeparture(
        tripID: String = "trip_100",
        stopID: String = "stop_200",
        stopSequence: Int = 5,
        gtfsStopSequence: Int? = nil,
        scheduledArrival: Date = Date(timeIntervalSince1970: 1_700_001_000),
        scheduledDeparture: Date = Date(timeIntervalSince1970: 1_700_001_100),
        serviceDate: Date = Date(timeIntervalSince1970: 1_700_000_000),
        predictedArrival: Date? = nil,
        predictedDeparture: Date? = nil,
        predicted: Bool = false,
        status: String = "default",
        tripStatus: TripStatus? = nil
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
            serviceDate: serviceDate,
            situationIDs: [],
            serviceAlerts: [],
            status: status,
            stopID: stopID,
            stopSequence: stopSequence,
            gtfsStopSequence: gtfsStopSequence,
            totalStopsInTrip: 20,
            tripHeadsign: "Downtown Seattle",
            tripID: tripID,
            tripStatus: tripStatus,
            vehicleID: "veh_10"
        )
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
            tripDelay: 240,
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
            tripDelay: 120,
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
            stopSequence: 1
        )

        let delayedResult = GTFSRealtimeDelayReconciler.standard.reconcile(
            arrivalDeparture: arrDepArriving,
            with: GTFSRTTripUpdate(tripID: "trip_eval", tripDelay: 120)
        )
        #expect(delayedResult.scheduleStatus == .delayed)

        let onTimeResult = GTFSRealtimeDelayReconciler.standard.reconcile(
            arrivalDeparture: arrDepArriving,
            with: GTFSRTTripUpdate(tripID: "trip_eval", tripDelay: 30)
        )
        #expect(onTimeResult.scheduleStatus == .onTime)

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

    @Test func `Scheduled fallback without prediction does not treat times as live`() {
        let arrDep = makeArrivalDeparture(
            tripID: "trip_partially_predicted",
            stopID: "stop_1",
            stopSequence: 1,
            predicted: false
        )

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
            tripDelay: 30,
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
            with: [updateYesterday, updateToday],
            timeZone: TimeZone(identifier: "UTC")
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
        #expect(skippedArrDep.predicted == false)
        #expect(skippedArrDep.predictedArrival == nil)
        #expect(skippedArrDep.predictedDeparture == nil)

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
            stopSequence: 1,
            scheduledArrival: base
        )

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

    @Test func `ArrivalDeparture without gtfsStopSequence does not carry forward upstream stop update when tripDelay is nil`() {
        let arrDep = makeArrivalDeparture(
            tripID: "trip_no_carry_forward",
            stopID: "stop_downstream",
            stopSequence: 5,
            gtfsStopSequence: nil,
            scheduledArrival: Date(timeIntervalSince1970: 1_700_001_000),
            scheduledDeparture: Date(timeIntervalSince1970: 1_700_001_100)
        )

        let upstreamUpdate = GTFSRTStopTimeUpdate(
            stopSequence: 2,
            stopID: "stop_upstream",
            departure: GTFSRTStopTimeEvent(delay: 150)
        )
        let tripUpdate = GTFSRTTripUpdate(
            tripID: "trip_no_carry_forward",
            tripDelay: nil,
            stopTimeUpdates: [upstreamUpdate]
        )

        let result = GTFSRealtimeDelayReconciler.standard.reconcile(arrivalDeparture: arrDep, with: tripUpdate)
        #expect(result.isLive == false)
        #expect(result.arrivalDelay == nil)
        #expect(result.departureDelay == nil)

        let applied = arrDep.applying(reconciliation: result)
        #expect(applied.predicted == false)
        #expect(applied.predictedArrival == nil)
    }

    @Test func `Canceled trip clears ArrivalDeparture predictions and attaches canceled tripStatus`() {
        let sched = Date(timeIntervalSince1970: 1_700_001_000)
        let existingTripStatus = TripStatus(
            activeTripID: "trip_cancel_test",
            closestStopID: "stop_10",
            isRealTime: true,
            statusModifier: .default
        )
        let arrDep = makeArrivalDeparture(
            tripID: "trip_cancel_test",
            stopID: "stop_10",
            stopSequence: 3,
            scheduledArrival: sched,
            scheduledDeparture: sched.addingTimeInterval(60),
            predictedArrival: sched.addingTimeInterval(120),
            predictedDeparture: sched.addingTimeInterval(180),
            predicted: true
        )
        let arrDepWithStatus = ArrivalDeparture(
            arrivalEnabled: true,
            routeID: "route_1",
            scheduledArrival: sched,
            scheduledDeparture: sched.addingTimeInterval(60),
            serviceDate: Date(timeIntervalSince1970: 1_700_000_000),
            stopID: "stop_10",
            stopSequence: 3,
            tripID: "trip_cancel_test",
            tripStatus: existingTripStatus
        )

        let canceledUpdate = GTFSRTTripUpdate(
            tripID: "trip_cancel_test",
            scheduleRelationship: .canceled
        )

        let result = GTFSRealtimeDelayReconciler.standard.reconcile(arrivalDeparture: arrDep, with: canceledUpdate)
        #expect(result.isCanceled == true)
        #expect(result.isLive == false)

        let applied = arrDep.applying(reconciliation: result)
        #expect(applied.predicted == false)
        #expect(applied.predictedArrival == nil)
        #expect(applied.predictedDeparture == nil)
        #expect(applied.status == "canceled")
        #expect(applied.arrivalEnabled == false)
        #expect(applied.departureEnabled == false)
        #expect(applied.tripStatus?.statusModifier == TripStatus.StatusModifier.canceled)
        #expect(applied.tripStatus?.isRealTime == false)

        let appliedWithExisting = arrDepWithStatus.applying(reconciliation: result)
        #expect(appliedWithExisting.predicted == false)
        #expect(appliedWithExisting.predictedArrival == nil)
        #expect(appliedWithExisting.tripStatus?.statusModifier == TripStatus.StatusModifier.canceled)
    }

    @Test func `Loop route matches correct visit when stopSequence is provided`() {
        let visit2ArrDep = makeArrivalDeparture(
            tripID: "trip_loop_route",
            stopID: "stop_shared",
            stopSequence: 1,
            gtfsStopSequence: 10,
            scheduledArrival: Date(timeIntervalSince1970: 1_700_005_000)
        )

        let visit1Update = GTFSRTStopTimeUpdate(
            stopSequence: 2,
            stopID: "stop_shared",
            arrival: GTFSRTStopTimeEvent(delay: 30)
        )
        let visit2Update = GTFSRTStopTimeUpdate(
            stopSequence: 10,
            stopID: "stop_shared",
            arrival: GTFSRTStopTimeEvent(delay: 240)
        )
        let tripUpdate = GTFSRTTripUpdate(
            tripID: "trip_loop_route",
            stopTimeUpdates: [visit1Update, visit2Update]
        )

        let result = GTFSRealtimeDelayReconciler.standard.reconcile(arrivalDeparture: visit2ArrDep, with: tripUpdate)
        #expect(result.matchedStopTimeUpdate?.stopSequence == 10)
        #expect(result.arrivalDelay == 240)
    }

    @Test func `Loop route disambiguates multiple visits without stopSequence using time proximity`() {
        let visit2Time = Date(timeIntervalSince1970: 1_700_007_200)
        let visit2ArrDep = makeArrivalDeparture(
            tripID: "trip_loop_not_seq",
            stopID: "stop_repeat",
            stopSequence: 8,
            scheduledArrival: visit2Time
        )

        let visit1Update = GTFSRTStopTimeUpdate(
            stopSequence: nil,
            stopID: "stop_repeat",
            arrival: GTFSRTStopTimeEvent(time: Date(timeIntervalSince1970: 1_700_000_100))
        )
        let visit2Update = GTFSRTStopTimeUpdate(
            stopSequence: nil,
            stopID: "stop_repeat",
            arrival: GTFSRTStopTimeEvent(time: visit2Time.addingTimeInterval(90))
        )
        let tripUpdate = GTFSRTTripUpdate(
            tripID: "trip_loop_not_seq",
            stopTimeUpdates: [visit1Update, visit2Update]
        )

        let result = GTFSRealtimeDelayReconciler.standard.reconcile(arrivalDeparture: visit2ArrDep, with: tripUpdate)
        #expect(result.matchedStopTimeUpdate?.arrivalTime == visit2Time.addingTimeInterval(90))
    }

    @Test func `Service date matching handles east-of-UTC agency timezone without picking yesterday`() {
        let warsawMidnight = Date(timeIntervalSince1970: 1_795_302_000)

        let arrDep = ArrivalDeparture(
            arrivalEnabled: true,
            routeID: "1_10",
            scheduledArrival: warsawMidnight.addingTimeInterval(3600),
            scheduledDeparture: warsawMidnight.addingTimeInterval(3700),
            serviceDate: warsawMidnight,
            stopID: "1_stop",
            tripID: "1_trip_warsaw"
        )

        let updateYesterday = GTFSRTTripUpdate(
            tripID: "trip_warsaw",
            startDate: "20261121",
            tripDelay: 45
        )
        let updateToday = GTFSRTTripUpdate(
            tripID: "trip_warsaw",
            startDate: "20261122",
            tripDelay: 180
        )

        let results = GTFSRealtimeDelayReconciler.standard.reconcile(
            arrivalDepartures: [arrDep],
            with: [updateYesterday, updateToday],
            timeZone: TimeZone(identifier: "Europe/Warsaw")
        )

        #expect(results.count == 1)
        #expect(results[0].arrivalDelay == 180)
        #expect(results[0].tripUpdate?.startDate == "20261122")
    }

    @Test func `Multi-agency trip ID matching does not collide 100 with 40_100`() {
        let kcmArrDep = makeArrivalDeparture(tripID: "1_100", stopID: "1_50")
        let soundTransitArrDep = makeArrivalDeparture(tripID: "40_100", stopID: "40_50")

        let feed40Update = GTFSRTTripUpdate(tripID: "40_100", tripDelay: 200)

        #expect(GTFSRealtimeDelayReconciler.tripIDsMatch(feedTripID: "100", restTripID: "1_100", agencyID: "1") == true)
        #expect(GTFSRealtimeDelayReconciler.tripIDsMatch(feedTripID: "100", restTripID: "40_100", agencyID: "1") == false)
        #expect(GTFSRealtimeDelayReconciler.tripIDsMatch(feedTripID: "1_100", restTripID: "40_100") == false)

        let kcmResults = GTFSRealtimeDelayReconciler.standard.reconcile(
            arrivalDepartures: [kcmArrDep],
            with: [feed40Update]
        )
        #expect(kcmResults[0].isLive == false)

        let stResults = GTFSRealtimeDelayReconciler.standard.reconcile(
            arrivalDepartures: [soundTransitArrDep],
            with: [feed40Update]
        )
        #expect(stResults[0].isLive == true)
        #expect(stResults[0].arrivalDelay == 200)
    }

    @Test func `ArrivalDeparture with zero-based stopSequence matches feed stop by stopID when feed uses 1-based GTFS stop_sequence`() {
        let arrDep = makeArrivalDeparture(
            tripID: "trip_express",
            stopID: "stop_pike",
            stopSequence: 0,
            scheduledArrival: Date(timeIntervalSince1970: 1_700_000_500),
            scheduledDeparture: Date(timeIntervalSince1970: 1_700_000_600)
        )

        let stopUpdate = GTFSRTStopTimeUpdate(
            stopSequence: 10,
            stopID: "stop_pike",
            arrival: GTFSRTStopTimeEvent(delay: 90),
            departure: GTFSRTStopTimeEvent(delay: 150),
            scheduleRelationship: .scheduled
        )
        let tripUpdate = GTFSRTTripUpdate(
            tripID: "trip_express",
            scheduleRelationship: .scheduled,
            stopTimeUpdates: [stopUpdate]
        )

        let result = GTFSRealtimeDelayReconciler.standard.reconcile(arrivalDeparture: arrDep, with: tripUpdate)
        #expect(result.matchedStopTimeUpdate?.stopSequence == 10)
        #expect(result.arrivalDelay == 90)
        #expect(result.departureDelay == 150)
    }

    @Test func `Negative stop sequence does not trap and returns nil sequence match`() {
        let item = GTFSRTScheduleItem(tripID: "trip_1", stopID: "stop_1", stopSequence: -1)
        let update = GTFSRTStopTimeUpdate(stopSequence: 1, stopID: "stop_1")
        let tripUpdate = GTFSRTTripUpdate(tripID: "trip_1", stopTimeUpdates: [update])

        let result = GTFSRealtimeDelayReconciler.standard.reconcile(schedule: item, with: tripUpdate)
        #expect(result.matchedStopTimeUpdate?.stopSequence == 1)
    }

    @Test func `Batch reconciliation isolates raw feed trip ID by feed agency`() {
        let kcmArrDep = makeArrivalDeparture(tripID: "1_100", stopID: "1_50")
        let soundTransitArrDep = makeArrivalDeparture(tripID: "40_100", stopID: "40_50")

        let rawFeedUpdate = GTFSRTTripUpdate(tripID: "100", tripDelay: 200)

        let results = GTFSRealtimeDelayReconciler.standard.reconcile(
            arrivalDepartures: [kcmArrDep, soundTransitArrDep],
            with: [rawFeedUpdate],
            agencyID: "1"
        )

        #expect(results.count == 2)
        #expect(results[0].isLive == true)
        #expect(results[0].arrivalDelay == 200)
        #expect(results[1].isLive == false)
    }

    @Test func `Service date matching in UTC+13 agency timezone picks today over yesterday`() {
        guard let aucklandTZ = TimeZone(identifier: "Pacific/Auckland") else { return }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = aucklandTZ

        let components = DateComponents(year: 2026, month: 11, day: 22, hour: 0, minute: 0, second: 0)
        guard let aucklandMidnight = cal.date(from: components) else { return }

        let arrDep = ArrivalDeparture(
            arrivalEnabled: true,
            routeID: "1_10",
            scheduledArrival: aucklandMidnight.addingTimeInterval(3600),
            scheduledDeparture: aucklandMidnight.addingTimeInterval(3700),
            serviceDate: aucklandMidnight,
            stopID: "1_stop",
            tripID: "1_trip_nz"
        )

        let updateYesterday = GTFSRTTripUpdate(
            tripID: "trip_nz",
            startDate: "20261121",
            tripDelay: 45
        )
        let updateToday = GTFSRTTripUpdate(
            tripID: "trip_nz",
            startDate: "20261122",
            tripDelay: 180
        )

        let results = GTFSRealtimeDelayReconciler.standard.reconcile(
            arrivalDepartures: [arrDep],
            with: [updateYesterday, updateToday],
            timeZone: aucklandTZ
        )

        #expect(results.count == 1)
        #expect(results[0].arrivalDelay == 180)
        #expect(results[0].tripUpdate?.startDate == "20261122")
    }

    @Test func `Reconciler with real decoded arrivals fixture performs stop-level match and trip-level delay fallback`() throws {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: "arrivals_and_departures_for_stop_1_75403.json")
        let arrival = try #require(stopArrivals.arrivalsAndDepartures.first)

        // 1. Verify REST API does not return gtfsStopSequence
        #expect(arrival.gtfsStopSequence == nil)
        #expect(arrival.stopID == "1_75403")
        #expect(arrival.tripID == "1_18198879")

        let reconciler = GTFSRealtimeDelayReconciler.standard

        // 2. Stop-level match: update matching arrival.stopID
        let stopMatchUpdate = GTFSRTTripUpdate(
            tripID: arrival.tripID,
            stopTimeUpdates: [
                GTFSRTStopTimeUpdate(
                    stopID: arrival.stopID,
                    arrival: GTFSRTStopTimeEvent(delay: 180),
                    departure: GTFSRTStopTimeEvent(delay: 240)
                )
            ]
        )
        let stopMatchResult = reconciler.reconcile(arrivalDeparture: arrival, with: stopMatchUpdate)
        #expect(stopMatchResult.arrivalDelay == 180)
        #expect(stopMatchResult.departureDelay == 240)
        #expect(stopMatchResult.reconciledArrival == arrival.scheduledArrival.addingTimeInterval(180))

        // 3. Trip-level delay fallback: update with tripDelay and stop updates for DIFFERENT stops.
        // Because arrival.gtfsStopSequence is nil, stop-sequence carry-forward does not match the other stop;
        // it cleanly falls back to trip-level delay.
        let tripFallbackUpdate = GTFSRTTripUpdate(
            tripID: arrival.tripID,
            tripDelay: 420,
            stopTimeUpdates: [
                GTFSRTStopTimeUpdate(
                    stopSequence: 10,
                    stopID: "1_99999",
                    arrival: GTFSRTStopTimeEvent(delay: 900)
                )
            ]
        )
        let tripFallbackResult = reconciler.reconcile(arrivalDeparture: arrival, with: tripFallbackUpdate)
        #expect(tripFallbackResult.arrivalDelay == 420)
        #expect(tripFallbackResult.departureDelay == 420)
        #expect(tripFallbackResult.reconciledArrival == arrival.scheduledArrival.addingTimeInterval(420))
    }

    @Test func `selectBestTripUpdate rejects update when startDate does not match arrival service date`() {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 22
        components.hour = 0
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")
        let todayMidnight = calendar.date(from: components)!

        let arrDepToday = makeArrivalDeparture(
            tripID: "trip_reject_yesterday",
            stopID: "stop_1",
            scheduledArrival: todayMidnight.addingTimeInterval(3600),
            scheduledDeparture: todayMidnight.addingTimeInterval(3700),
            serviceDate: todayMidnight
        )

        // Only yesterday's update is present in feed
        let updateYesterday = GTFSRTTripUpdate(
            tripID: "trip_reject_yesterday",
            startDate: "20261121",
            tripDelay: 300
        )

        let reconciler = GTFSRealtimeDelayReconciler.standard
        let results = reconciler.reconcile(
            arrivalDepartures: [arrDepToday],
            with: [updateYesterday],
            timeZone: TimeZone(identifier: "UTC")
        )

        #expect(results.count == 1)
        #expect(results[0].tripUpdate == nil)
        #expect(results[0].arrivalDelay == nil)
        #expect(results[0].isLive == false)

        let applied = arrDepToday.applying(reconciliation: results[0])
        #expect(applied.predicted == false)
        #expect(applied.predictedArrival == nil)
    }

    @Test func `buildUpdatedTripStatus preserves statusModifier on empty reconciliation or no-match`() {
        let sched = Date(timeIntervalSince1970: 1_700_001_000)

        // Canceled statusModifier
        let canceledTripStatus = TripStatus(
            activeTripID: "trip_preserve_status",
            closestStopID: "stop_1",
            statusModifier: .canceled
        )
        let arrDepCanceled = ArrivalDeparture(
            arrivalEnabled: false,
            routeID: "route_1",
            scheduledArrival: sched,
            scheduledDeparture: sched.addingTimeInterval(60),
            serviceDate: Date(timeIntervalSince1970: 1_700_000_000),
            stopID: "stop_1",
            tripID: "trip_preserve_status",
            tripStatus: canceledTripStatus
        )

        // Scheduled statusModifier
        let scheduledTripStatus = TripStatus(
            activeTripID: "trip_preserve_status_2",
            closestStopID: "stop_1",
            statusModifier: .scheduled
        )
        let arrDepScheduled = ArrivalDeparture(
            arrivalEnabled: true,
            routeID: "route_1",
            scheduledArrival: sched,
            scheduledDeparture: sched.addingTimeInterval(60),
            serviceDate: Date(timeIntervalSince1970: 1_700_000_000),
            stopID: "stop_1",
            tripID: "trip_preserve_status_2",
            tripStatus: scheduledTripStatus
        )

        let reconciler = GTFSRealtimeDelayReconciler.standard

        // Reconcile with nil (empty reconciliation)
        let emptyResultCanceled = reconciler.reconcile(arrivalDeparture: arrDepCanceled, with: nil)
        let appliedCanceled = arrDepCanceled.applying(reconciliation: emptyResultCanceled)
        #expect(appliedCanceled.tripStatus?.statusModifier == .canceled)

        let emptyResultScheduled = reconciler.reconcile(arrivalDeparture: arrDepScheduled, with: nil)
        let appliedScheduled = arrDepScheduled.applying(reconciliation: emptyResultScheduled)
        #expect(appliedScheduled.tripStatus?.statusModifier == .scheduled)

        // Reconcile batch with no matching updates (no-match)
        let batchResults = reconciler.reconcile(
            arrivalDepartures: [arrDepCanceled, arrDepScheduled],
            with: [GTFSRTTripUpdate(tripID: "some_unrelated_trip", tripDelay: 60)]
        )
        let batchAppliedCanceled = arrDepCanceled.applying(reconciliation: batchResults[0])
        #expect(batchAppliedCanceled.tripStatus?.statusModifier == .canceled)

        let batchAppliedScheduled = arrDepScheduled.applying(reconciliation: batchResults[1])
        #expect(batchAppliedScheduled.tripStatus?.statusModifier == .scheduled)
    }

    @Test func `ArrivalDeparture isEqual and hash include gtfsStopSequence`() {
        let arrDep1 = makeArrivalDeparture(stopSequence: 3, gtfsStopSequence: 10)
        let arrDep2 = makeArrivalDeparture(stopSequence: 3, gtfsStopSequence: 10)
        let arrDepDifferentSeq = makeArrivalDeparture(stopSequence: 3, gtfsStopSequence: 20)
        let arrDepNilSeq = makeArrivalDeparture(stopSequence: 3, gtfsStopSequence: nil)

        #expect(arrDep1 == arrDep2)
        #expect(arrDep1.hashValue == arrDep2.hashValue)

        #expect(arrDep1 != arrDepDifferentSeq)
        #expect(arrDep1 != arrDepNilSeq)
    }

    @Test func `buildUpdatedTripStatus uses tripDelay for scheduleDeviation rather than single stop arrivalDelay`() {
        let initialTripStatus = TripStatus(
            activeTripID: "trip_dev_test",
            closestStopID: "stop_dev",
            scheduleDeviation: 100,
            statusModifier: .default
        )
        let arrDep = makeArrivalDeparture(
            tripID: "trip_dev_test",
            stopID: "stop_dev",
            tripStatus: initialTripStatus
        )

        let tripUpdate = GTFSRTTripUpdate(
            tripID: "trip_dev_test",
            tripDelay: 500,
            stopTimeUpdates: [
                GTFSRTStopTimeUpdate(
                    stopID: "stop_dev",
                    arrival: GTFSRTStopTimeEvent(delay: 60)
                )
            ]
        )

        let result = GTFSRealtimeDelayReconciler.standard.reconcile(arrivalDeparture: arrDep, with: tripUpdate)
        #expect(result.arrivalDelay == 60)

        let applied = arrDep.applying(reconciliation: result)
        // Stop arrival is adjusted by stop's arrivalDelay (60)
        #expect(applied.predictedArrival == arrDep.scheduledArrival.addingTimeInterval(60))
        // But trip-level scheduleDeviation reflects trip-level tripDelay (500)
        #expect(applied.tripStatus?.scheduleDeviation == 500)
    }
}
