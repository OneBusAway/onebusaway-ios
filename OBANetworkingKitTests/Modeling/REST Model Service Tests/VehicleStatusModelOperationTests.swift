//
//  VehicleStatussModelOperationTests.swift
//  OBANetworkingKitTests
//
//  Created by Aaron Brethorst on 10/19/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
import CoreLocation
@testable import OBANetworkingKit

class VehicleStatusModelOperationTests: OBATestCase {
    let vehicleID = "40_11"
    lazy var apiPath = RequestVehicleOperation.buildAPIPath(vehicleID: vehicleID)

    func stubVehicle4011() {
        stubJSON(fileName: "vehicle_for_id_4011.json")
    }

    func stubJSON(fileName: String) {
        stub(condition: isHost(self.host) && isPath(apiPath)) { _ in
            return self.JSONFile(named: fileName)
        }
    }
}

// MARK: - Vehicle Status
extension VehicleStatusModelOperationTests {
    func testLoading_vehicleStatus_failure_garbageData() {
        stub(condition: isHost(self.host) && isPath(apiPath)) { _ in
            return self.file(named: "captive_portal.html", contentType: "text/html")
        }

        waitUntil { done in
            let op = self.restModelService.getVehicle(self.vehicleID)
            op.completionBlock = {
                expect(op.vehicles.count) == 0

                done()
            }
        }
    }

    func testLoading_vehicleStatus_success() {
        stubVehicle4011()

        waitUntil { done in
            let op = self.restModelService.getVehicle(self.vehicleID)
            op.completionBlock = {
                expect(op.vehicles.count) == 1

                let vehicle = op.vehicles.first!

                // Vehicle Status
                expect(vehicle.lastLocationUpdateTime).to(beNil())
                expect(vehicle.lastUpdateTime) == Date.fromComponents(year: 2018, month: 10, day: 03, hour: 16, minute: 31, second: 09)
                expect(vehicle.location!.coordinate.latitude) == 47.608246
                expect(vehicle.location!.coordinate.longitude) == -122.336166
                expect(vehicle.phase) == "in_progress"
                expect(vehicle.status) == "SCHEDULED"

                done()
            }
        }
    }
}

// MARK: - Trip Status
extension VehicleStatusModelOperationTests {
    func testLoading_tripStatus_success() {
        stubVehicle4011()

        waitUntil { done in
            let op = self.restModelService.getVehicle(self.vehicleID)
            op.completionBlock = {
                let tripStatus = op.vehicles.first!.tripStatus

                // Trip Status
                expect(tripStatus).toNot(beNil())
                expect(tripStatus.activeTripID) == "40_40804394"
                expect(tripStatus.blockTripSequence) == 3
                expect(tripStatus.closestStop) == "1_532"
                expect(tripStatus.closestStopTimeOffset) == -7
                expect(tripStatus.distanceAlongTrip).to(beCloseTo(25959.0657, within: 0.1))
                expect(tripStatus.lastKnownDistanceAlongTrip) == 0
                expect(tripStatus.lastKnownLocation).to(beNil())
                expect(tripStatus.lastKnownOrientation) == 0
                expect(tripStatus.lastLocationUpdateTime) == 0
                expect(tripStatus.lastUpdateTime) == 1538584269000
                expect(tripStatus.nextStop) == "1_565"
                expect(tripStatus.nextStopTimeOffset) == 144
                expect(tripStatus.orientation).to(beCloseTo(132.0288, within: 0.1))
                expect(tripStatus.phase) == "in_progress"
                expect(tripStatus.position!.coordinate.latitude).to(beCloseTo(47.60339847, within: 0.01))
                expect(tripStatus.position!.coordinate.longitude).to(beCloseTo(-122.33187637, within: 0.01))
                expect(tripStatus.predicted).to(beTrue())
                expect(tripStatus.scheduleDeviation) == 219
                expect(tripStatus.scheduledDistanceAlongTrip).to(beCloseTo(25959.0657, within: 0.1))
                expect(tripStatus.serviceDate) == Date.fromComponents(year: 2018, month: 10, day: 03, hour: 07, minute: 00, second: 00)
                expect(tripStatus.situationIDs) == []
                expect(tripStatus.status) == "SCHEDULED"
                expect(tripStatus.totalDistanceAlongTrip).to(beCloseTo(32491.73, within: 0.01))
                expect(tripStatus.vehicleID) == "40_11"

                done()
            }
        }
    }
}

// MARK: - References
extension VehicleStatussModelOperationTests {
    func testLoading_references_success() {
        stubVehicle4011()

        waitUntil { done in
            let op = self.restModelService.getVehicle(self.vehicleID)
            op.completionBlock = {
                let references = op.references!

                expect(references).toNot(beNil())

                expect(references.agencies.count) == 2
                expect(references.routes.count) == 8
                expect(references.situations.count) == 0
                expect(references.stops.count) == 2
                expect(references.trips.count) == 1

                done()
            }
        }
    }
}

// MARK: - Frequency
extension VehicleStatusModelOperationTests {
    func testLoading_frequency_success() {
        stubJSON(fileName: "frequency-vehicle.json")

        waitUntil { done in
            let op = self.restModelService.getVehicle(self.vehicleID)
            op.completionBlock = {
                let frequency = op.vehicles.first!.tripStatus.frequency!

                expect(frequency).toNot(beNil())
                expect(frequency.startTime) == Date.fromComponents(year: 2010, month: 11, day: 12, hour: 16, minute: 30, second: 00)
                
                expect(frequency.endTime) == Date.fromComponents(year: 2010, month: 11, day: 12, hour: 22, minute: 59, second: 59)
                expect(frequency.headway) == 600

                done()
            }
        }
    }
}
