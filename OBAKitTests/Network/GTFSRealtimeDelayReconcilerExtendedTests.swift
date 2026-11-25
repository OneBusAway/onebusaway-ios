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

    @Test func `Service date disambiguates multiple candidate trip updates`() throws {
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
            timeZone: try #require(TimeZone(identifier: "UTC"))
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

    @Test func `Service date matching in UTC+13 agency timezone picks today over yesterday`() throws {
        let aucklandTZ = try #require(TimeZone(identifier: "Pacific/Auckland"))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = aucklandTZ

        let components = DateComponents(year: 2026, month: 11, day: 22, hour: 0, minute: 0, second: 0)
        let aucklandMidnight = try #require(cal.date(from: components))

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

    @Test func `selectBestTripUpdate matches startDate on spring-forward DST transition day in agency timezone`() throws {
        // In the US, spring-forward Sunday skips from 2:00 to 3:00 AM (e.g. March 10, 2024 in America/New_York).
        let easternTZ = try #require(TimeZone(identifier: "America/New_York"))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = easternTZ

        // Java OBA ServiceDate builds serviceDate using the "noon minus 12 hours" rule:
        // ServiceDate.moveCalendarToServiceDate sets calendar to 12:00:00 and subtracts 12 hours.
        // On spring-forward Sunday, that lands at 23:00 the previous evening (March 9, 2024 at 23:00:00 EST).
        let noonComponents = DateComponents(year: 2024, month: 3, day: 10, hour: 12, minute: 0, second: 0)
        let noon = try #require(cal.date(from: noonComponents))
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

    @Test func `selectBestTripUpdate matches startDate when device timezone is west of agency timezone`() throws {
        // Agency operates in America/New_York (UTC-4 / EDT), service date is March 15, 2024.
        let easternTZ = try #require(TimeZone(identifier: "America/New_York"))
        let pacificTZ = try #require(TimeZone(identifier: "America/Los_Angeles"))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = easternTZ

        // Standard midnight in agency timezone
        let midnightComponents = DateComponents(year: 2024, month: 3, day: 15, hour: 0, minute: 0, second: 0)
        let agencyMidnight = try #require(cal.date(from: midnightComponents))

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

    /// A route whose agency runs in `timeZone`, as the REST references load it.
    private func makeRoute(agencyTimeZone timeZone: String) throws -> Route {
        let json = """
        {"agencyId": "1", "id": "1_10", "shortName": "10", "type": 3,
         "agency": {"id": "1", "lang": "en", "name": "Metro", "phone": "", "privateService": false,
                    "timezone": "\(timeZone)", "url": "https://example.com"}}
        """
        return try JSONDecoder().decode(Route.self, from: Data(json.utf8))
    }

    /// An arrival on `serviceDay` (yyyyMMdd) at an agency in `timeZone`, with
    /// its service date at that day's start there.
    private func makeArrivalDeparture(serviceDay: DateComponents, agencyTimeZone timeZone: String, tripID: String) throws -> ArrivalDeparture {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try #require(TimeZone(identifier: timeZone))
        let serviceDate = try #require(cal.date(from: serviceDay))
        return ArrivalDeparture(
            arrivalEnabled: true,
            routeID: "1_10",
            route: try makeRoute(agencyTimeZone: timeZone),
            scheduledArrival: serviceDate.addingTimeInterval(13 * 3600),
            scheduledDeparture: serviceDate.addingTimeInterval(13 * 3600 + 60),
            serviceDate: serviceDate,
            stopID: "1_stop",
            tripID: tripID
        )
    }

    /// Samoa (UTC-11) and Kiritimati (UTC+14) are 25 hours apart, so no single
    /// device zone formats both service dates as the right day. Each arrival's
    /// update only matches when its own agency's zone is used.
    @Test func `start_date is checked in each arrival's agency zone, not the device's`() throws {
        let day = DateComponents(year: 2026, month: 11, day: 22)
        let samoa = try makeArrivalDeparture(serviceDay: day, agencyTimeZone: "Pacific/Pago_Pago", tripID: "1_trip_samoa")
        let kiritimati = try makeArrivalDeparture(serviceDay: day, agencyTimeZone: "Pacific/Kiritimati", tripID: "1_trip_kiritimati")

        let results = GTFSRealtimeDelayReconciler.standard.reconcile(
            arrivalDepartures: [samoa, kiritimati],
            with: [
                GTFSRTTripUpdate(tripID: "trip_samoa", startDate: "20261122", tripDelay: 120),
                GTFSRTTripUpdate(tripID: "trip_kiritimati", startDate: "20261122", tripDelay: 240)
            ]
        )

        #expect(results.map(\.arrivalDelay) == [120, 240])
    }

    /// Without the agency's zone a start_date can't be checked, so an update
    /// carrying one isn't trusted; one without a start_date still applies.
    @Test func `With no known zone, only updates without a start_date apply`() {
        let serviceDate = Date(timeIntervalSince1970: 1_795_305_600)
        let arrDep = ArrivalDeparture(
            arrivalEnabled: true,
            routeID: "route_1",
            scheduledArrival: serviceDate.addingTimeInterval(3600),
            scheduledDeparture: serviceDate.addingTimeInterval(3700),
            serviceDate: serviceDate,
            stopID: "stop_1",
            tripID: "trip_no_zone"
        )

        let dated = GTFSRealtimeDelayReconciler.standard.reconcile(
            arrivalDepartures: [arrDep],
            with: [GTFSRTTripUpdate(tripID: "trip_no_zone", startDate: "20261122", tripDelay: 60)]
        )
        #expect(dated[0].tripUpdate == nil)

        let undated = GTFSRealtimeDelayReconciler.standard.reconcile(
            arrivalDepartures: [arrDep],
            with: [GTFSRTTripUpdate(tripID: "trip_no_zone", timestamp: serviceDate.addingTimeInterval(3000), tripDelay: 60)]
        )
        #expect(undated[0].arrivalDelay == 60)
    }

    /// The vehicle is still finishing the block's previous trip, so the
    /// arrival's `tripStatus` is that trip's. This trip's update, delayed or
    /// canceled, must leave it alone.
    @Test func `An update leaves a trip status that belongs to another active trip unchanged`() {
        let previousTripStatus = TripStatus(
            activeTripID: "trip_previous",
            closestStopID: "stop_1",
            scheduleDeviation: 30,
            statusModifier: .canceled
        )
        let arrDep = makeArrivalDeparture(tripID: "trip_next", stopID: "stop_1", tripStatus: previousTripStatus)

        for update in [
            GTFSRTTripUpdate(tripID: "trip_next", tripDelay: 600),
            GTFSRTTripUpdate(tripID: "trip_next", scheduleRelationship: .canceled)
        ] {
            let result = GTFSRealtimeDelayReconciler.standard.reconcile(arrivalDeparture: arrDep, with: update)
            let applied = arrDep.applying(reconciliation: result)

            #expect(applied.tripStatus === previousTripStatus)
            #expect(applied.tripStatus?.scheduleDeviation == 30)
            #expect(applied.tripStatus?.statusModifier == .canceled)
        }
    }

    /// With no known zone there is no start_date to match exactly, so undated
    /// updates still go through the 36-hour timestamp check.
    @Test func `With no known zone, a stale undated update is rejected`() {
        let serviceDate = Date(timeIntervalSince1970: 1_795_305_600)
        let arrDep = makeArrivalDeparture(tripID: "trip_no_zone", serviceDate: serviceDate)

        let results = GTFSRealtimeDelayReconciler.standard.reconcile(
            arrivalDepartures: [arrDep],
            with: [GTFSRTTripUpdate(tripID: "trip_no_zone", timestamp: serviceDate.addingTimeInterval(37 * 3600), tripDelay: 60)]
        )

        #expect(results[0].tripUpdate == nil)
    }

    @Test func `With no known zone, the nearest undated update wins`() {
        let serviceDate = Date(timeIntervalSince1970: 1_795_305_600)
        let arrDep = makeArrivalDeparture(tripID: "trip_no_zone", serviceDate: serviceDate)

        let results = GTFSRealtimeDelayReconciler.standard.reconcile(
            arrivalDepartures: [arrDep],
            with: [
                GTFSRTTripUpdate(tripID: "trip_no_zone", timestamp: serviceDate.addingTimeInterval(30 * 3600), tripDelay: 60),
                GTFSRTTripUpdate(tripID: "trip_no_zone", timestamp: serviceDate.addingTimeInterval(3600), tripDelay: 120)
            ]
        )

        #expect(results[0].arrivalDelay == 120)
    }

    /// An empty or unknown agency zone falls through to the trip's zone.
    @Test func `An unusable agency zone falls back to the trip's zone`() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try #require(TimeZone(identifier: "Pacific/Kiritimati"))
        let serviceDate = try #require(cal.date(from: DateComponents(year: 2026, month: 11, day: 22)))
        let tripJSON = """
        {"blockId": "1_block", "id": "1_trip_kiritimati", "routeId": "1_10", "routeShortName": "10",
         "serviceId": "1_weekday", "tripShortName": "", "timeZone": "Pacific/Kiritimati"}
        """
        let trip = try JSONDecoder().decode(Trip.self, from: Data(tripJSON.utf8))

        for agencyZone in ["", "Not/AZone"] {
            let arrDep = ArrivalDeparture(
                arrivalEnabled: true,
                routeID: "1_10",
                route: try makeRoute(agencyTimeZone: agencyZone),
                scheduledArrival: serviceDate.addingTimeInterval(13 * 3600),
                scheduledDeparture: serviceDate.addingTimeInterval(13 * 3600 + 60),
                serviceDate: serviceDate,
                stopID: "1_stop",
                tripID: "1_trip_kiritimati",
                trip: trip
            )

            let results = GTFSRealtimeDelayReconciler.standard.reconcile(
                arrivalDepartures: [arrDep],
                with: [GTFSRTTripUpdate(tripID: "trip_kiritimati", startDate: "20261122", tripDelay: 240)]
            )

            #expect(results[0].arrivalDelay == 240, "agency zone \"\(agencyZone)\"")
        }
    }

    // MARK: - Reconciled Schedule Parity & Auxiliary Boundaries

    @Test func `ReconciledArrivalDeparture reconciledDate returns scheduled date matching arrivalDepartureStatus when isNoData`() {
        let schedArr = Date(timeIntervalSince1970: 1_700_000_000)
        let schedDep = Date(timeIntervalSince1970: 1_700_000_100)

        // Case 1: Arriving (stopSequence > 0) returns scheduledArrival
        let arrivingArrDep = makeArrivalDeparture(
            stopSequence: 5,
            scheduledArrival: schedArr,
            scheduledDeparture: schedDep
        )
        let arrivingNoDataUpdate = GTFSRTTripUpdate(
            tripID: arrivingArrDep.tripID,
            stopTimeUpdates: [
                GTFSRTStopTimeUpdate(
                    stopID: arrivingArrDep.stopID,
                    scheduleRelationship: .noData
                )
            ]
        )
        let arrivingResult = GTFSRealtimeDelayReconciler.standard.reconcile(arrivalDeparture: arrivingArrDep, with: arrivingNoDataUpdate)
        #expect(arrivingResult.isNoData == true)
        #expect(arrivingResult.reconciledDate == schedArr)

        // Case 2: Departing (stopSequence == 0) returns scheduledDeparture
        let departingArrDep = makeArrivalDeparture(
            stopSequence: 0,
            scheduledArrival: schedArr,
            scheduledDeparture: schedDep
        )
        let departingNoDataUpdate = GTFSRTTripUpdate(
            tripID: departingArrDep.tripID,
            stopTimeUpdates: [
                GTFSRTStopTimeUpdate(
                    stopID: departingArrDep.stopID,
                    scheduleRelationship: .noData
                )
            ]
        )
        let departingResult = GTFSRealtimeDelayReconciler.standard.reconcile(arrivalDeparture: departingArrDep, with: departingNoDataUpdate)
        #expect(departingResult.isNoData == true)
        #expect(departingResult.reconciledDate == schedDep)
    }

    @Test func `PropagateUpstream with custom stopOrder propagates delay to stop without direct update`() {
        let reconciler = GTFSRealtimeDelayReconciler.standard

        // Feed has updates for stop_A (delay: 100) and stop_B (delay: 250).
        // Neither update specifies a stop sequence.
        let updateStopA = GTFSRTStopTimeUpdate(
            stopID: "stop_A",
            departure: GTFSRTStopTimeEvent(delay: 100)
        )
        let updateStopB = GTFSRTStopTimeUpdate(
            stopID: "stop_B",
            departure: GTFSRTStopTimeEvent(delay: 250)
        )

        let tripUpdate = GTFSRTTripUpdate(
            tripID: "trip_ordered",
            stopTimeUpdates: [updateStopB, updateStopA] // feed order has B before A
        )

        // Target stop is stop_C, which has no direct update in the feed.
        let itemC = GTFSRTScheduleItem(
            tripID: "trip_ordered",
            stopID: "stop_C",
            stopSequence: nil,
            scheduledArrival: Date(timeIntervalSince1970: 1_700_003_000),
            scheduledDeparture: Date(timeIntervalSince1970: 1_700_003_060)
        )

        // Custom order 1: [stop_A, stop_B, stop_C] -> latest upstream is stop_B (delay: 250)
        let result1 = reconciler.reconcile(
            schedule: itemC,
            with: tripUpdate,
            stopOrder: ["stop_A", "stop_B", "stop_C"]
        )
        #expect(result1.departureDelay == 250)
        #expect(result1.matchedStopTimeUpdate == nil)

        // Custom order 2: [stop_B, stop_A, stop_C] -> latest upstream is stop_A (delay: 100)
        let result2 = reconciler.reconcile(
            schedule: itemC,
            with: tripUpdate,
            stopOrder: ["stop_B", "stop_A", "stop_C"]
        )
        #expect(result2.departureDelay == 100)
        #expect(result2.matchedStopTimeUpdate == nil)
    }

    @Test func `Agency prefix extraction and stripping handles nested and edge string formats`() {
        #expect(GTFSRealtimeDelayReconciler.agencyPrefix(from: "1_100") == "1")
        #expect(GTFSRealtimeDelayReconciler.agencyPrefix(from: "agency-kcm_route99") == "agency-kcm")
        #expect(GTFSRealtimeDelayReconciler.agencyPrefix(from: "_leading") == nil)
        #expect(GTFSRealtimeDelayReconciler.agencyPrefix(from: "noUnderscore") == nil)
        #expect(GTFSRealtimeDelayReconciler.agencyPrefix(from: nil) == nil)

        #expect(GTFSRealtimeDelayReconciler.stripAgencyPrefix(from: "1_100") == "100")
        #expect(GTFSRealtimeDelayReconciler.stripAgencyPrefix(from: "agency_sub_component") == "sub_component")
        #expect(GTFSRealtimeDelayReconciler.stripAgencyPrefix(from: "_leading") == "_leading")
        #expect(GTFSRealtimeDelayReconciler.stripAgencyPrefix(from: "plainText") == "plainText")
    }

    @Test func `StopIDsMatch validates optional agency ID prefix and rejects empty identifiers`() {
        #expect(GTFSRealtimeDelayReconciler.stopIDsMatch(feedStopID: "50", restStopID: "1_50", agencyID: "1"))
        #expect(!GTFSRealtimeDelayReconciler.stopIDsMatch(feedStopID: "50", restStopID: "40_50", agencyID: "1"))
        #expect(!GTFSRealtimeDelayReconciler.stopIDsMatch(feedStopID: "", restStopID: "1_50"))
        #expect(!GTFSRealtimeDelayReconciler.stopIDsMatch(feedStopID: "50", restStopID: ""))
        #expect(!GTFSRealtimeDelayReconciler.stopIDsMatch(feedStopID: nil, restStopID: "1_50"))
        #expect(!GTFSRealtimeDelayReconciler.stopIDsMatch(feedStopID: "50", restStopID: nil))
        #expect(GTFSRealtimeDelayReconciler.stopIDsMatch(feedStopID: "same_stop", restStopID: "same_stop"))
    }
}
