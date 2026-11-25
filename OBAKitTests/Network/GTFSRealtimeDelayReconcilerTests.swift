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

    struct TestSchedule: GTFSRTReconcilableSchedule {
        var reconcilableTripID: String
        var reconcilableStopID: String?
        var reconcilableStopSequence: Int?
        var scheduledArrivalDate: Date?
        var scheduledDepartureDate: Date?
    }

    private func makeArrivalDeparture(
        tripID: String = "trip_100",
        stopID: String = "stop_200",
        stopSequence: Int = 5,
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

    @Test func `ArrivalDeparture does not carry forward upstream stop update when tripDelay is nil`() {
        let arrDep = makeArrivalDeparture(
            tripID: "trip_no_carry_forward",
            stopID: "stop_downstream",
            stopSequence: 5,
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
        let visit2Schedule = TestSchedule(
            reconcilableTripID: "trip_loop_route",
            reconcilableStopID: "stop_shared",
            reconcilableStopSequence: 10,
            scheduledArrivalDate: Date(timeIntervalSince1970: 1_700_005_000),
            scheduledDepartureDate: nil
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

        let result = GTFSRealtimeDelayReconciler.standard.reconcile(schedule: visit2Schedule, with: tripUpdate)
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

    @Test func `Reconciler with real decoded arrivals fixture performs stop-level match and trip-level delay fallback`() throws {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: "arrivals_and_departures_for_stop_1_75403.json")
        let arrival = try #require(stopArrivals.arrivalsAndDepartures.first)

        // 1. Verify reconcilableStopSequence is nil for ArrivalDeparture
        #expect(arrival.reconcilableStopSequence == nil)
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
        // Because arrival.reconcilableStopSequence is nil, stop-sequence carry-forward does not match the other stop;
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

    // MARK: - Delay Reconciliation Fallbacks, Exact Matches, & Mutating Semantics

    @Test func `Reconciler selects exact sequence and stop match over duplicate sequence candidate`() {
        let reconciler = GTFSRealtimeDelayReconciler.standard

        // Feed has two updates for sequence 5: one for stop_X and one for stop_Y
        let updateX = GTFSRTStopTimeUpdate(
            stopSequence: 5,
            stopID: "stop_X",
            arrival: GTFSRTStopTimeEvent(delay: 111),
            departure: GTFSRTStopTimeEvent(delay: 222)
        )
        let updateY = GTFSRTStopTimeUpdate(
            stopSequence: 5,
            stopID: "stop_Y",
            arrival: GTFSRTStopTimeEvent(delay: 333),
            departure: GTFSRTStopTimeEvent(delay: 444)
        )

        let tripUpdate = GTFSRTTripUpdate(
            tripID: "trip_multi_seq",
            stopTimeUpdates: [updateX, updateY]
        )

        let targetSchedule = GTFSRTScheduleItem(
            tripID: "trip_multi_seq",
            stopID: "stop_Y",
            stopSequence: 5,
            scheduledArrival: Date(timeIntervalSince1970: 1_700_000_000),
            scheduledDeparture: Date(timeIntervalSince1970: 1_700_000_060)
        )

        let matched = reconciler.findMatchingStopTimeUpdate(for: targetSchedule, in: tripUpdate)
        #expect(matched?.stopID == "stop_Y")
        #expect(matched?.arrivalDelay == 333)
        #expect(matched?.departureDelay == 444)
    }

    @Test func `Reconciler matches stop ID when sequence is absent in target schedule`() {
        let reconciler = GTFSRealtimeDelayReconciler.standard

        let update = GTFSRTStopTimeUpdate(
            stopSequence: 8,
            stopID: "stop_standalone",
            arrival: GTFSRTStopTimeEvent(delay: 150),
            departure: GTFSRTStopTimeEvent(delay: 200)
        )

        let tripUpdate = GTFSRTTripUpdate(
            tripID: "trip_standalone",
            stopTimeUpdates: [update]
        )

        // Schedule has nil stop sequence
        let scheduleWithoutSeq = GTFSRTScheduleItem(
            tripID: "trip_standalone",
            stopID: "stop_standalone",
            stopSequence: nil
        )

        let matched = reconciler.findMatchingStopTimeUpdate(for: scheduleWithoutSeq, in: tripUpdate)
        #expect(matched?.stopID == "stop_standalone")
        #expect(matched?.arrivalDelay == 150)
        #expect(matched?.departureDelay == 200)
    }

    @Test func `Applying reconciliation updates vehicleID and occupancyStatus on ArrivalDeparture`() {
        let arrDep = makeArrivalDeparture(tripID: "trip_veh", stopID: "stop_veh")

        let stopUpdate = GTFSRTStopTimeUpdate(
            stopID: "stop_veh",
            arrival: GTFSRTStopTimeEvent(delay: 90),
            departure: GTFSRTStopTimeEvent(delay: 120),
            departureOccupancyStatus: .fewSeatsAvailable
        )

        let tripUpdate = GTFSRTTripUpdate(
            tripID: "trip_veh",
            vehicleID: "new_vehicle_888",
            stopTimeUpdates: [stopUpdate]
        )

        let result = GTFSRealtimeDelayReconciler.standard.reconcile(arrivalDeparture: arrDep, with: tripUpdate)
        let applied = arrDep.applying(reconciliation: result)

        #expect(applied.vehicleID == "new_vehicle_888")
        #expect(applied.occupancyStatus == .fewSeatsAvailable)
        #expect(applied.predicted == true)
        #expect(applied.predictedArrival == arrDep.scheduledArrival.addingTimeInterval(90))
        #expect(applied.predictedDeparture == arrDep.scheduledDeparture.addingTimeInterval(120))
    }

    @Test func `Applying reconciliation preserves existing vehicleID when update vehicleID is absent`() {
        let arrDep = makeArrivalDeparture(tripID: "trip_preserve", stopID: "stop_preserve")
        #expect(arrDep.vehicleID == "veh_10")

        let stopUpdate = GTFSRTStopTimeUpdate(
            stopID: "stop_preserve",
            arrival: GTFSRTStopTimeEvent(delay: 60),
            departure: GTFSRTStopTimeEvent(delay: 60)
        )

        let tripUpdateWithoutVehicle = GTFSRTTripUpdate(
            tripID: "trip_preserve",
            vehicleID: nil,
            stopTimeUpdates: [stopUpdate]
        )

        let result = GTFSRealtimeDelayReconciler.standard.reconcile(arrivalDeparture: arrDep, with: tripUpdateWithoutVehicle)
        let applied = arrDep.applying(reconciliation: result)

        #expect(applied.vehicleID == "veh_10")
    }

    @Test func `Batch reconciliation filters candidate updates matching routeID when routeID is present`() {
        let arrDepRoute1 = makeArrivalDeparture(tripID: "trip_shared", stopID: "stop_shared")
        #expect(arrDepRoute1.routeID == "route_1")

        // Feed has trip update for trip_shared with route_2 (mismatch) and route_1 (match)
        let updateWrongRoute = GTFSRTTripUpdate(
            tripID: "trip_shared",
            routeID: "route_2",
            tripDelay: 500
        )
        let updateCorrectRoute = GTFSRTTripUpdate(
            tripID: "trip_shared",
            routeID: "route_1",
            tripDelay: 150
        )

        let results = GTFSRealtimeDelayReconciler.standard.reconcile(
            arrivalDepartures: [arrDepRoute1],
            with: [updateWrongRoute, updateCorrectRoute]
        )

        #expect(results.count == 1)
        #expect(results[0].arrivalDelay == 150)
        #expect(results[0].tripUpdate?.routeID == "route_1")
    }

    @Test func `ScheduleForStop StopScheduleStopTime conforms to GTFSRTReconcilableSchedule`() throws {
        let stopTimeJSON: [String: Any] = [
            "tripId": "trip_schedule_entry",
            "serviceId": "svc_1",
            "arrivalTime": Int64(1_700_000_500_000),
            "departureTime": Int64(1_700_000_600_000),
            "arrivalEnabled": true,
            "departureEnabled": true,
            "stopHeadsign": "Downtown"
        ]

        let data = try JSONSerialization.data(withJSONObject: stopTimeJSON)
        let stopTime = try JSONDecoder().decode(ScheduleForStop.StopScheduleStopTime.self, from: data)
        stopTime.stopID = "stop_timetable_123"

        #expect(stopTime.reconcilableTripID == "trip_schedule_entry")
        #expect(stopTime.reconcilableStopID == "stop_timetable_123")
        #expect(stopTime.reconcilableStopSequence == nil)
        #expect(stopTime.scheduledArrivalDate == Date(timeIntervalSince1970: 1_700_000_500))
        #expect(stopTime.scheduledDepartureDate == Date(timeIntervalSince1970: 1_700_000_600))

        let tripUpdate = GTFSRTTripUpdate(
            tripID: "trip_schedule_entry",
            stopTimeUpdates: [
                GTFSRTStopTimeUpdate(
                    stopID: "stop_timetable_123",
                    arrival: GTFSRTStopTimeEvent(delay: 120),
                    departure: GTFSRTStopTimeEvent(delay: 180)
                )
            ]
        )

        let reconciled = GTFSRealtimeDelayReconciler.standard.reconcile(schedule: stopTime, with: tripUpdate)
        #expect(reconciled.isLive == true)
        #expect(reconciled.arrivalDelay == 120)
        #expect(reconciled.departureDelay == 180)
        #expect(reconciled.reconciledArrival == Date(timeIntervalSince1970: 1_700_000_620))
        #expect(reconciled.reconciledDeparture == Date(timeIntervalSince1970: 1_700_000_780))
    }
}
