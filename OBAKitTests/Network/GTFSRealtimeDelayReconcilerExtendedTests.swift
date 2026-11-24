import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
struct GTFSRealtimeDelayReconcilerExtendedTests {

    private func makeArrivalDeparture(
        tripID: String = "trip_100",
        stopID: String = "stop_200",
        stopSequence: Int = 5,
        scheduledArrival: Date = Date(timeIntervalSince1970: 1_700_001_000),
        scheduledDeparture: Date = Date(timeIntervalSince1970: 1_700_001_100),
        serviceDate: Date = Date(timeIntervalSince1970: 1_700_000_000),
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
            predicted: false,
            predictedArrival: nil,
            predictedDeparture: nil,
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
            with: [updateYesterday, updateToday]
        )

        #expect(results.count == 1)
        #expect(results[0].arrivalDelay == 300)
        #expect(results[0].tripUpdate?.startDate == "20261122")
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

    @Test func `selectBestTripUpdate matches startDate on spring-forward DST transition day in agency timezone`() {
        // In the US, spring-forward Sunday skips from 2:00 to 3:00 AM (e.g. March 10, 2024 in America/New_York).
        guard let easternTZ = TimeZone(identifier: "America/New_York") else { return }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = easternTZ

        // Java OBA ServiceDate builds serviceDate using the "noon minus 12 hours" rule:
        // ServiceDate.moveCalendarToServiceDate sets calendar to 12:00:00 and subtracts 12 hours.
        // On spring-forward Sunday, that lands at 23:00 the previous evening (March 9, 2024 at 23:00:00 EST).
        let noonComponents = DateComponents(year: 2024, month: 3, day: 10, hour: 12, minute: 0, second: 0)
        guard let noon = cal.date(from: noonComponents) else { return }
        let springForwardServiceDate = noon.addingTimeInterval(-12 * 3600)

        // Verify that springForwardServiceDate is indeed 23:00 the previous evening in Eastern time
        let hour = cal.component(.hour, from: springForwardServiceDate)
        let day = cal.component(.day, from: springForwardServiceDate)
        #expect(hour == 23)
        #expect(day == 9)

        let arrDep = makeArrivalDeparture(
            tripID: "trip_spring_forward",
            stopID: "stop_1",
            scheduledArrival: noon.addingTimeInterval(600),
            scheduledDeparture: noon.addingTimeInterval(660),
            serviceDate: springForwardServiceDate
        )

        // Feed has start_date matching the service day (20240310)
        let matchingUpdate = GTFSRTTripUpdate(
            tripID: "trip_spring_forward",
            startDate: "20240310",
            tripDelay: 120
        )

        let reconciler = GTFSRealtimeDelayReconciler.standard
        let results = reconciler.reconcile(
            arrivalDepartures: [arrDep],
            with: [matchingUpdate],
            timeZone: easternTZ
        )

        #expect(results.count == 1)
        #expect(results[0].isLive == true)
        #expect(results[0].arrivalDelay == 120)
        #expect(results[0].tripUpdate?.tripID == "trip_spring_forward")
    }

    @Test func `selectBestTripUpdate matches startDate when device timezone is west of agency timezone`() {
        // Agency operates in America/New_York (UTC-4 / EDT), service date is March 15, 2024.
        guard let easternTZ = TimeZone(identifier: "America/New_York"),
              let pacificTZ = TimeZone(identifier: "America/Los_Angeles") else { return }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = easternTZ

        // Standard midnight in agency timezone
        let midnightComponents = DateComponents(year: 2024, month: 3, day: 15, hour: 0, minute: 0, second: 0)
        guard let agencyMidnight = cal.date(from: midnightComponents) else { return }

        // In Pacific timezone (3 hours behind Eastern), agency midnight (00:00 EDT) is 21:00 PDT on March 14.
        // Anchoring at noon (adding 12 hours) ensures formatting in Pacific gives 20240315.
        let arrDep = makeArrivalDeparture(
            tripID: "trip_west_tz",
            stopID: "stop_1",
            scheduledArrival: agencyMidnight.addingTimeInterval(3600),
            scheduledDeparture: agencyMidnight.addingTimeInterval(3700),
            serviceDate: agencyMidnight
        )

        let update = GTFSRTTripUpdate(
            tripID: "trip_west_tz",
            startDate: "20240315",
            tripDelay: 180
        )

        let reconciler = GTFSRealtimeDelayReconciler.standard
        let results = reconciler.reconcile(
            arrivalDepartures: [arrDep],
            with: [update],
            timeZone: pacificTZ
        )

        #expect(results.count == 1)
        #expect(results[0].isLive == true)
        #expect(results[0].arrivalDelay == 180)
        #expect(results[0].tripUpdate?.tripID == "trip_west_tz")
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

    @Test func `applying reconciliation with non-canceled feed update resets canceled status and statusModifier to default`() {
        let sched = Date(timeIntervalSince1970: 1_700_001_000)
        let canceledTripStatus = TripStatus(
            activeTripID: "trip_uncancel",
            closestStopID: "stop_1",
            statusModifier: .canceled
        )
        let arrDepCanceled = ArrivalDeparture(
            arrivalEnabled: false,
            routeID: "route_1",
            scheduledArrival: sched,
            scheduledDeparture: sched.addingTimeInterval(60),
            serviceDate: Date(timeIntervalSince1970: 1_700_000_000),
            status: "canceled",
            stopID: "stop_1",
            tripID: "trip_uncancel",
            tripStatus: canceledTripStatus
        )

        let liveUpdate = GTFSRTTripUpdate(
            tripID: "trip_uncancel",
            tripDelay: 90
        )

        let result = GTFSRealtimeDelayReconciler.standard.reconcile(arrivalDeparture: arrDepCanceled, with: liveUpdate)
        let applied = arrDepCanceled.applying(reconciliation: result)

        #expect(applied.status == "default")
        #expect(applied.arrivalEnabled == true)
        #expect(applied.departureEnabled == true)
        #expect(applied.tripStatus?.statusModifier == .default)
        #expect(applied.tripStatus?.isRealTime == true)
        #expect(applied.tripStatus?.scheduleDeviation == 90)
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
