//
//  StopArrivalsModelOperationTests.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 11/4/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
import CoreLocation
import MapKit
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable function_body_length

class StopArrivalsModelOperationTests: OBATestCase {
    let campusParkwayStopID = "1_10914"
    lazy var campusParkwayAPIPath: String = StopArrivalsAndDeparturesOperation.buildAPIPath(stopID: campusParkwayStopID)

    let galerStopID = "1_11370"
    lazy var galerAPIPath: String = StopArrivalsAndDeparturesOperation.buildAPIPath(stopID: galerStopID)

    let rvtdStopID = "1739_d1e8e68e-83f8-487f-baf5-f465fe70fc84.json"
    lazy var rvtdAPIPath = StopArrivalsAndDeparturesOperation.buildAPIPath(stopID: rvtdStopID)

    override func setUp() {
        super.setUp()
        stub(condition: isHost(self.host) && isPath(self.campusParkwayAPIPath)) { _ in
            return OHHTTPStubsResponse.JSONFile(named: "arrivals-and-departures-for-stop-1_10914.json")
        }
        stub(condition: isHost(self.host) && isPath(self.galerAPIPath)) { _ in
            return OHHTTPStubsResponse.JSONFile(named: "arrivals_and_departures_for_stop_15th-galer.json")
        }
        stub(condition: isHost(self.host) && isPath(self.rvtdAPIPath)) { _ in
            return OHHTTPStubsResponse.JSONFile(named: "arrivals-and-departures-for-stop-1739-rvtd.json")
        }
    }

    func test_arrivalAndDepartureStatus() {
        waitUntil { (done) in
            let op = self.restModelService.getArrivalsAndDeparturesForStop(id: self.galerStopID, minutesBefore: 5, minutesAfter: 30)
            op.completionBlock = {
                let arrivals = op.stopArrivals!

                expect(arrivals.arrivalsAndDepartures.count) == 5

                expect(arrivals.arrivalsAndDepartures[0].arrivalDepartureStatus) == .arriving
                expect(arrivals.arrivalsAndDepartures[1].arrivalDepartureStatus) == .departing

                expect(arrivals.arrivalsAndDepartures[0].vehicleID) == "1_4361"
                expect(arrivals.arrivalsAndDepartures[1].vehicleID) == "1_4361"

                expect(arrivals.arrivalsAndDepartures[2].arrivalDepartureStatus) == .arriving
                expect(arrivals.arrivalsAndDepartures[3].arrivalDepartureStatus) == .departing
                expect(arrivals.arrivalsAndDepartures[4].arrivalDepartureStatus) == .arriving

                done()
            }
        }
    }

    func testLoading_success() {
        waitUntil { (done) in
            let op = self.restModelService.getArrivalsAndDeparturesForStop(id: self.campusParkwayStopID, minutesBefore: 5, minutesAfter: 30)
            op.completionBlock = {
                let arrivals = op.stopArrivals!

                expect(arrivals.nearbyStops.count) == 4
                expect(arrivals.nearbyStops.count) == 4
                expect(arrivals.nearbyStops.first!.name) == "15th Ave NE & NE Campus Pkwy"

                expect(arrivals.situations.count) == 0

                expect(arrivals.stop.id) == "1_10914"
                expect(arrivals.stop.name) == "15th Ave NE & NE Campus Pkwy"

                expect(arrivals.arrivalsAndDepartures.count) == 1

                let arrDep = arrivals.arrivalsAndDepartures.first!
                expect(arrDep.arrivalEnabled).to(beTrue())
                expect(arrDep.blockTripSequence) == 9
                expect(arrDep.departureEnabled).to(beTrue())
                expect(arrDep.distanceFromStop).to(beCloseTo(1232.648659247323))
                expect(arrDep.frequency).to(beNil())

                expect(arrDep.lastUpdated) == Date.fromComponents(year: 2018, month: 11, day: 02, hour: 06, minute: 55, second: 49)

                expect(arrDep.numberOfStopsAway) == 4
                expect(arrDep.predicted).to(beTrue())

                expect(arrDep.arrivalDepartureDate) == Date.fromComponents(year: 2018, month: 11, day: 02, hour: 07, minute: 02, second: 36)

                expect(arrDep.route.id) == "1_100447"
                expect(arrDep.route.shortName) == "49"

                expect(arrDep.routeLongName).to(beNil())
                expect(arrDep.routeShortName) == "49"

                expect(arrDep.arrivalDepartureDate) == Date.fromComponents(year: 2018, month: 11, day: 02, hour: 07, minute: 02, second: 36)

                expect(arrDep.serviceDate) == Date.fromComponents(year: 2018, month: 11, day: 01, hour: 07, minute: 00, second: 00)

                expect(arrDep.situations.count) == 0

                expect(arrDep.status) == "default"

                expect(arrDep.stop.id) == "1_10914"
                expect(arrDep.stop.name) == "15th Ave NE & NE Campus Pkwy"

                expect(arrDep.stopSequence) == 3

                expect(arrDep.totalStopsInTrip) == 22

                expect(arrDep.tripHeadsign) == "Downtown Seattle Broadway"

                expect(arrDep.trip.id) == "1_40984902"
                expect(arrDep.trip.shortName) == "LOCAL"

                expect(arrDep.tripStatus).toNot(beNil())
                let tripStatus = arrDep.tripStatus!
                expect(tripStatus.activeTrip.id) == "1_40984840"

                expect(arrDep.vehicleID) == "1_4559"

                done()
            }
        }
    }

    func testLoading_rogueValley() {
        // There are some indications that the data shape from RVTD is different from some other regions.
        // This test is meant to ensure that these different data sources work equally well.

        waitUntil { (done) in
            let op = self.restModelService.getArrivalsAndDeparturesForStop(id: self.rvtdStopID, minutesBefore: 5, minutesAfter: 30)
            op.completionBlock = {
                let arrivals = op.stopArrivals!

                expect(arrivals.nearbyStops.count) == 3
                expect(arrivals.situations.count) == 0

                expect(arrivals.stop.id) == "1739_d1e8e68e-83f8-487f-baf5-f465fe70fc84"
                expect(arrivals.stop.name) == "E Main St - West of Myrtle St"

                expect(arrivals.arrivalsAndDepartures.count) == 1

                let arrDep = arrivals.arrivalsAndDepartures.first!
                expect(arrDep.arrivalEnabled).to(beTrue())
                expect(arrDep.blockTripSequence) == 2
                expect(arrDep.departureEnabled).to(beTrue())
                expect(arrDep.distanceFromStop).to(beCloseTo(63293.0860))
                expect(arrDep.frequency).to(beNil())

                done()
            }
        }
    }
}
