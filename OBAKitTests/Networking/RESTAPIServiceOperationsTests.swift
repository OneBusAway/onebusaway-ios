//
//  RESTAPIServiceOperationsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import MapKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class RESTAPIServiceOperationsTests: OBATestCase {

    private var dataLoader: MockDataLoader!

    override init() async throws {
        try await super.init()
        dataLoader = try #require(restService.dataLoader as? MockDataLoader)
    }

    // MARK: - getTrip ArrivalDeparture

    @Test func `getTripArrivalDepartureAtStop requests correct URL and decodes entry`() async throws {
        let stopID = "1_75414"
        let tripID = "1_18196913"
        let serviceDate = Date(timeIntervalSince1970: 1_588_834_800)
        let vehicleID = "1_4351"
        let stopSequence = 5

        let fixtureData = Fixtures.loadData(file: "arrivals-and-departures-for-stop-1_75414.json")

        dataLoader.mock(data: fixtureData) { request in
            guard let url = request.url else { return false }
            return url.path.contains("/api/where/arrival-and-departure-for-stop/\(stopID).json") &&
                url.containsQueryParams([
                    "tripId": tripID,
                    "serviceDate": "1588834800000",
                    "vehicleId": vehicleID,
                    "stopSequence": "5"
                ])
        }

        let response = try await restService.getTripArrivalDepartureAtStop(
            stopID: stopID,
            tripID: tripID,
            serviceDate: serviceDate,
            vehicleID: vehicleID,
            stopSequence: stopSequence
        )

        #expect(response.code == 200)
        #expect(response.entry.stopID == stopID)
    }

    // MARK: - getVehicleTrip

    @Test func `getVehicleTrip requests trip-for-vehicle and decodes trip details`() async throws {
        let vehicleID = "1_2799"
        let fixtureData = Fixtures.loadData(file: "trip-for-vehicle-1_2799.json")

        dataLoader.mock(data: fixtureData) { request in
            guard let url = request.url else { return false }
            return url.path.contains("/api/where/trip-for-vehicle/\(vehicleID).json")
        }

        let response = try await restService.getVehicleTrip(vehicleID: vehicleID)

        #expect(response.code == 200)
        #expect(response.entry.status?.activeTripID == "1_40956737")
        #expect(response.entry.status?.blockTripSequence == 3)
    }

    // MARK: - OnDemand Absence Recording

    @Test func `getOnDemandServices records absence in OnDemandSupport on 404`() async throws {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321),
            latitudinalMeters: 1000,
            longitudinalMeters: 1000
        )

        let targetURL = restService.urlBuilder.getOnDemandServices(region: region, geometryDetail: .simplified)
        let response404 = HTTPURLResponse(url: targetURL, statusCode: 404, httpVersion: "2.0", headerFields: nil)!
        dataLoader.mock(mockResponse: MockDataResponse(data: Data(), urlResponse: response404, error: nil) { $0.url?.path == targetURL.path })

        #expect(!restService.onDemandSupport.isKnownUnsupported(baseURL: restService.baseURL))

        await #expect(throws: APIError.self) {
            _ = try await self.restService.getOnDemandServices(region: region, geometryDetail: .simplified)
        }

        // OnDemandSupport should now have recorded absence for this base URL
        #expect(restService.onDemandSupport.isKnownUnsupported(baseURL: restService.baseURL))
    }

    @Test func `getOnDemandServices near coordinate records absence on HTML response`() async throws {
        let coordinate = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
        let targetURL = restService.urlBuilder.getOnDemandServices(near: coordinate, radiusMeters: 500, geometryDetail: .none)

        let htmlResponse = HTTPURLResponse(
            url: targetURL,
            statusCode: 200,
            httpVersion: "2.0",
            headerFields: ["Content-Type": "text/html; charset=utf-8"]
        )!
        dataLoader.mock(mockResponse: MockDataResponse(data: Data("<html></html>".utf8), urlResponse: htmlResponse, error: nil) { $0.url?.path == targetURL.path })

        await #expect(throws: APIError.self) {
            _ = try await self.restService.getOnDemandServices(near: coordinate, radiusMeters: 500, geometryDetail: .none)
        }

        #expect(restService.onDemandSupport.isKnownUnsupported(baseURL: restService.baseURL))
    }
}
