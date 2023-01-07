//
//  VehicleStatussModelOperationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
import CoreLocation
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable function_body_length force_cast

class VehicleStatusModelOperationTests: OBATestCase {
    let vehicleID = "1_4351"
    lazy var apiPath = "https://www.example.com/api/where/vehicle/\(vehicleID).json"

    var dataLoader: MockDataLoader!

    override func setUp() {
        super.setUp()

        dataLoader = (restService.dataLoader as! MockDataLoader)
    }

    func stubVehicle14351Success() {
        dataLoader.mock(URLString: apiPath, with: Fixtures.loadData(file: "api_where_vehicle_1_4351.json"))
    }

    func stubVehicle14351CaptivePortal() {
        let url = URL(string: apiPath)!
        let httpResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "2", headerFields: ["Content-Type": "text/html"])
        let error = NSError(domain: NSCocoaErrorDomain, code: 3840, userInfo: nil)
        let mockResponse = MockDataResponse(data: Fixtures.loadData(file: "captive_portal.html"), urlResponse: httpResponse, error: error) { (request) -> Bool in
            return request.url!.absoluteString.starts(with: url.absoluteString)
        }
        dataLoader.mock(response: mockResponse)
    }

    // MARK: - Vehicle Status

    func testLoading_vehicleStatus_failure_garbageData() {
        stubVehicle14351CaptivePortal()

        let op = restService.getVehicle(vehicleID)

        waitUntil { done in
            op.complete { result in
                switch result {
                case .failure(let error):
                    if case APIError.captivePortal = error {
                        done()
                    }
                    else {
                        fatalError()
                    }
                case .success:
                    fatalError()
                }
            }
        }
    }

    func testLoading_vehicleStatus_success() {
        stubVehicle14351Success()

        let op = restService.getVehicle(vehicleID)

        waitUntil { done in
            op.complete { result in
                switch result {
                case .failure:
                    fatalError()
                case .success(let response):
                    let vehicle = response.entry
                    expect(vehicle.lastLocationUpdateTime) == Date.fromComponents(year: 2020, month: 05, day: 07, hour: 21, minute: 59, second: 04)
                    expect(vehicle.lastUpdateTime) == Date.fromComponents(year: 2020, month: 05, day: 07, hour: 21, minute: 59, second: 04)
                    expect(vehicle.location!.coordinate.latitude).to(beCloseTo(47.6195))
                    expect(vehicle.location!.coordinate.longitude).to(beCloseTo(-122.3244))
                    expect(vehicle.phase) == "in_progress"
                    expect(vehicle.status) == "SCHEDULED"

                    done()
                }
            }
        }
    }

    // MARK: - Trip Status

    func testLoading_tripStatus_success() {
        stubVehicle14351Success()

        let op = restService.getVehicle(vehicleID)

        waitUntil { done in

            op.complete { result in
                switch result {
                case .failure:
                    fatalError()
                case .success(let response):
                    let vehicle = response.entry

                    expect(vehicle.vehicleID) == "1_4351"
                    expect(vehicle.lastUpdateTime) == Date.fromComponents(year: 2020, month: 05, day: 07, hour: 21, minute: 59, second: 04)
                    expect(vehicle.lastLocationUpdateTime) == Date.fromComponents(year: 2020, month: 05, day: 07, hour: 21, minute: 59, second: 04)
                    expect(vehicle.location?.coordinate.latitude).to(beCloseTo(47.6195))
                    expect(vehicle.location?.coordinate.longitude).to(beCloseTo(-122.3244))

                    expect(vehicle.trip!.id) == "1_47649081"
                    expect(vehicle.trip!.routeShortName).to(beNil())
                    expect(vehicle.trip!.shortName) == "LOCAL"

                    expect(vehicle.phase) == "in_progress"
                    expect(vehicle.status) == "SCHEDULED"

                    let tripStatus = vehicle.tripStatus

                    // Trip Status
                    expect(tripStatus).toNot(beNil())

                    expect(tripStatus.activeTrip.id) == "1_47649081"
                    expect(tripStatus.activeTrip.headsign) == "Downtown Seattle"

                    expect(tripStatus.blockTripSequence) == 19

                    expect(tripStatus.closestStop.id) == "1_29266"
                    expect(tripStatus.closestStop.name) == "E Olive Way & Summit Ave E"

                    expect(tripStatus.closestStopTimeOffset) == 23
                    expect(tripStatus.distanceAlongTrip).to(beCloseTo(2277.5779, within: 0.1))
                    expect(tripStatus.lastKnownDistanceAlongTrip) == 0

                    let lastKnown = tripStatus.lastKnownLocation!.coordinate
                    expect(lastKnown.latitude).to(beCloseTo(47.61949539))
                    expect(lastKnown.longitude).to(beCloseTo(-122.32442474))
                    expect(tripStatus.lastKnownOrientation) == 0
                    expect(tripStatus.lastLocationUpdateTime) == 1588888744000
                    expect(tripStatus.lastUpdate) == Date.fromComponents(year: 2020, month: 05, day: 07, hour: 21, minute: 59, second: 04)

                    expect(tripStatus.nextStop!.id) == "1_29266"
                    expect(tripStatus.nextStop!.name) == "E Olive Way & Summit Ave E"

                    expect(tripStatus.nextStopTimeOffset) == 23
                    expect(tripStatus.orientation).to(beCloseTo(204.6164, within: 0.1))
                    expect(tripStatus.phase) == "in_progress"
                    expect(tripStatus.position!.coordinate.latitude).to(beCloseTo(47.6195, within: 0.01))
                    expect(tripStatus.position!.coordinate.longitude).to(beCloseTo(-122.33187637, within: 0.01))
                    expect(tripStatus.isRealTime).to(beTrue())
                    expect(tripStatus.scheduleDeviation) == -116
                    expect(tripStatus.scheduledDistanceAlongTrip).to(beCloseTo(2277.5779, within: 0.1))
                    expect(tripStatus.serviceDate) == Date.fromComponents(year: 2020, month: 05, day: 07, hour: 07, minute: 00, second: 00)
                    expect(tripStatus.serviceAlerts.count) == 1
                    expect(tripStatus.statusModifier) == .scheduled
                    expect(tripStatus.totalDistanceAlongTrip).to(beCloseTo(3302.4674, within: 0.01))
                    expect(tripStatus.vehicleID) == "1_4351"

                    done()
                }
            }
        }
    }

    // MARK: - References

    func testLoading_references_success() {
        stubVehicle14351Success()

        let op = restService.getVehicle(vehicleID)

        waitUntil { done in
            op.complete { result in
                switch result {
                case .failure:
                    fatalError()
                case .success(let response):
                    let references = response.references!
                    expect(references.agencies.count) == 1
                    expect(references.routes.count) == 3
                    expect(references.serviceAlerts.count) == 1
                    expect(references.stops.count) == 1
                    expect(references.trips.count) == 1
                    done()
                }
            }
        }
    }

    // MARK: - Frequency

    func testLoading_frequency_success() {
        let data = Fixtures.loadData(file: "frequency-vehicle.json")
        dataLoader.mock(URLString: "https://www.example.com/api/where/vehicle/\(vehicleID).json", with: data)

        let op = restService.getVehicle(vehicleID)

        waitUntil { done in
            op.complete { result in
                switch result {
                case .failure:
                    fatalError()
                case .success(let response):
                    let frequency = response.entry.tripStatus.frequency!

                    expect(frequency).toNot(beNil())
                    expect(frequency.startTime) == Date.fromComponents(year: 2010, month: 11, day: 12, hour: 16, minute: 30, second: 00)

                    expect(frequency.endTime) == Date.fromComponents(year: 2010, month: 11, day: 12, hour: 22, minute: 59, second: 59)
                    expect(frequency.headway) == 600

                    done()
                }
            }
        }
    }
}
