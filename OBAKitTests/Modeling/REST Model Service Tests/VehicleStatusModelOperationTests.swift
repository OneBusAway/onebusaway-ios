//
//  VehicleStatussModelOperationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable function_body_length force_cast

@Suite(.serialized)
final class VehicleStatusModelOperationTests: OBATestCase {
    let vehicleID = "1_4351"
    lazy var apiPath = "https://www.example.com/api/where/vehicle/\(vehicleID).json"

    var dataLoader: MockDataLoader!

    override init() async throws {
        try await super.init()

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

    @Test func `Loading vehicle status failure garbage data`() async throws {
        stubVehicle14351CaptivePortal()

        // The do/catch this replaces carried a TODO asking for an
        // XCTAssertThrowsAPIError helper, because XCTAssertThrowsError could not
        // take an async expression. #expect(throws:) can, so the helper is moot.
        // APIError isn't Equatable, so match the case rather than the value.
        let thrown = await #expect(throws: APIError.self) {
            _ = try await restService.getVehicle(vehicleID: vehicleID)
        }

        guard case .captivePortal? = thrown else {
            Issue.record("Expected APIError.captivePortal, got \(String(describing: thrown))")
            return
        }
    }

    @Test func `Loading vehicle status success`() async throws {
        stubVehicle14351Success()

        let vehicle = try await restService.getVehicle(vehicleID: vehicleID).entry
        #expect(vehicle.lastLocationUpdateTime == Date.fromComponents(year: 2020, month: 05, day: 07, hour: 21, minute: 59, second: 04))
        #expect(vehicle.lastUpdateTime == Date.fromComponents(year: 2020, month: 05, day: 07, hour: 21, minute: 59, second: 04))
        expectClose(vehicle.location!.coordinate.latitude, 47.6195)
        expectClose(vehicle.location!.coordinate.longitude, -122.3244)
        #expect(vehicle.phase == "in_progress")
        #expect(vehicle.status == "SCHEDULED")
    }

    // MARK: - Trip Status

    @Test func `Loading trip status success`() async throws {
        stubVehicle14351Success()

        let vehicle = try await restService.getVehicle(vehicleID: vehicleID).entry
        #expect(vehicle.vehicleID == "1_4351")
        #expect(vehicle.lastUpdateTime == Date.fromComponents(year: 2020, month: 05, day: 07, hour: 21, minute: 59, second: 04))
        #expect(vehicle.lastLocationUpdateTime == Date.fromComponents(year: 2020, month: 05, day: 07, hour: 21, minute: 59, second: 04))
        expectClose(vehicle.location?.coordinate.latitude, 47.6195)
        expectClose(vehicle.location?.coordinate.longitude, -122.3244)

        #expect(vehicle.trip!.id == "1_47649081")
        #expect(vehicle.trip!.routeShortName == nil)
        #expect(vehicle.trip!.shortName == "LOCAL")

        #expect(vehicle.phase == "in_progress")
        #expect(vehicle.status == "SCHEDULED")

        let tripStatus = vehicle.tripStatus
        #expect(tripStatus.activeTrip.id == "1_47649081")
        #expect(tripStatus.activeTrip.headsign == "Downtown Seattle")

        #expect(tripStatus.blockTripSequence == 19)

        #expect(tripStatus.closestStop.id == "1_29266")
        #expect(tripStatus.closestStop.name == "E Olive Way & Summit Ave E")

        #expect(tripStatus.closestStopTimeOffset == 23)
        expectClose(tripStatus.distanceAlongTrip, 2277.5779, within: 0.1)
        #expect(tripStatus.lastKnownDistanceAlongTrip == 0)

        let lastKnown = tripStatus.lastKnownLocation!.coordinate
        expectClose(lastKnown.latitude, 47.61949539)
        expectClose(lastKnown.longitude, -122.32442474)
        #expect(tripStatus.lastKnownOrientation == 0)
        #expect(tripStatus.lastLocationUpdateTime == 1588888744000)
        #expect(tripStatus.lastUpdate == Date.fromComponents(year: 2020, month: 05, day: 07, hour: 21, minute: 59, second: 04))

        #expect(tripStatus.nextStop!.id == "1_29266")
        #expect(tripStatus.nextStop!.name == "E Olive Way & Summit Ave E")

        #expect(tripStatus.nextStopTimeOffset == 23)
        expectClose(tripStatus.orientation, 204.6164, within: 0.1)
        #expect(tripStatus.phase == "in_progress")
        expectClose(tripStatus.position!.coordinate.latitude, 47.6195, within: 0.01)
        expectClose(tripStatus.position!.coordinate.longitude, -122.33187637, within: 0.01)
        #expect(tripStatus.isRealTime)
        #expect(tripStatus.scheduleDeviation == -116)
        expectClose(tripStatus.scheduledDistanceAlongTrip, 2277.5779, within: 0.1)
        #expect(tripStatus.serviceDate == Date.fromComponents(year: 2020, month: 05, day: 07, hour: 07, minute: 00, second: 00))
        #expect(tripStatus.serviceAlerts.count == 1)
        #expect(tripStatus.statusModifier == .scheduled)
        expectClose(tripStatus.totalDistanceAlongTrip, 3302.4674, within: 0.01)
        #expect(tripStatus.vehicleID == "1_4351")
    }

    // MARK: - References

    @Test func `Loading references success`() async throws {
        stubVehicle14351Success()

        let response = try await restService.getVehicle(vehicleID: vehicleID)
        let references = try #require(response.references)
        #expect(references.agencies.count == 1)
        #expect(references.routes.count == 3)
        #expect(references.serviceAlerts.count == 1)
        #expect(references.stops.count == 1)
        #expect(references.trips.count == 1)
    }

    // MARK: - Frequency

    @Test func `Loading frequency success`() async throws {
        let data = Fixtures.loadData(file: "frequency-vehicle.json")
        dataLoader.mock(URLString: "https://www.example.com/api/where/vehicle/\(vehicleID).json", with: data)

        let response = try await restService.getVehicle(vehicleID: vehicleID)
        let frequency = try #require(response.entry.tripStatus.frequency)

        #expect(frequency.startTime == Date.fromComponents(year: 2010, month: 11, day: 12, hour: 16, minute: 30, second: 00))

        #expect(frequency.endTime == Date.fromComponents(year: 2010, month: 11, day: 12, hour: 22, minute: 59, second: 59))
        #expect(frequency.headway == 600)
    }
}
