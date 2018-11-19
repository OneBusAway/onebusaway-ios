//
//  StopArrivalsModelOperationTests.swift
//  OBANetworkingKitTests
//
//  Created by Aaron Brethorst on 11/4/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
import CoreLocation
import MapKit
import OBATestHelpers
@testable import OBANetworkingKit

class StopArrivalsModelOperationTests: OBATestCase {
    let stopID = "1_10914"
    lazy var apiPath: String = StopArrivalsAndDeparturesOperation.buildAPIPath(stopID: stopID)

    func stubAPICall() {
        stub(condition: isHost(self.host) && isPath(self.apiPath)) { _ in
            return self.JSONFile(named: "arrivals-and-departures-for-stop-1_10914.json")
        }
    }

    func testLoading_success() {
        stubAPICall()

        waitUntil { (done) in
            let op = self.restModelService.getArrivalsAndDeparturesForStop(id: self.stopID, minutesBefore: 5, minutesAfter: 30)
            op.completionBlock = {
                let arrivals = op.stopArrivals!

                expect(arrivals.nearbyStopIDs.count) == 4
                expect(arrivals.nearbyStops.count) == 4
                expect(arrivals.nearbyStops.first!.name) == "15th Ave NE & NE Campus Pkwy"

                expect(arrivals.situationIDs.count) == 0
                expect(arrivals.situations.count) == 0

                expect(arrivals.stopID) == "1_10914"
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

                expect(arrDep.predictedArrival) == Date.fromComponents(year: 2018, month: 11, day: 02, hour: 07, minute: 02, second: 36)
                expect(arrDep.predictedDeparture) == Date.fromComponents(year: 2018, month: 11, day: 02, hour: 07, minute: 02, second: 36)

                expect(arrDep.routeID) == "1_100447"
                expect(arrDep.route.shortName) == "49"

                expect(arrDep.routeLongName).to(beNil())
                expect(arrDep.routeShortName) == "49"

                expect(arrDep.scheduledArrival) == Date.fromComponents(year: 2018, month: 11, day: 02, hour: 07, minute: 00, second: 00)
                expect(arrDep.scheduledDeparture) == Date.fromComponents(year: 2018, month: 11, day: 02, hour: 07, minute: 00, second: 00)

                expect(arrDep.serviceDate) == Date.fromComponents(year: 2018, month: 11, day: 01, hour: 07, minute: 00, second: 00)

                expect(arrDep.situationIDs.count) == 0
                expect(arrDep.situations.count) == 0

                expect(arrDep.status) == "default"

                expect(arrDep.stopID) == "1_10914"
                expect(arrDep.stop.name) == "15th Ave NE & NE Campus Pkwy"

                expect(arrDep.stopSequence) == 3

                expect(arrDep.totalStopsInTrip) == 22

                expect(arrDep.tripHeadsign) == "Downtown Seattle Broadway"

                expect(arrDep.tripID) == "1_40984902"
                expect(arrDep.trip.shortName) == "LOCAL"

                expect(arrDep.tripStatus).toNot(beNil())
                let tripStatus = arrDep.tripStatus!
                expect(tripStatus.activeTripID) == "1_40984840"

                expect(arrDep.vehicleID) == "1_4559"

                done()
            }
        }
    }
}
