//
//  ObacoAPIServiceOperationsTests.swift
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

@Suite(.serialized)
final class ObacoAPIServiceOperationsTests: OBATestCase {

    private var dataLoader: MockDataLoader!
    private var obacoService: ObacoAPIService!

    override init() async throws {
        try await super.init()

        dataLoader = try #require(restService.dataLoader as? MockDataLoader)
        let config = APIServiceConfiguration(
            baseURL: URL(string: "https://alerts.onebusaway.org")!,
            apiKey: "TEST",
            uuid: "TEST-UUID",
            appVersion: "1.0",
            regionIdentifier: 1
        )
        obacoService = ObacoAPIService(regionID: 1, delegate: nil, configuration: config, dataLoader: dataLoader)
    }

    // MARK: - Weather

    @Test func `getWeather requests regional weather endpoint and decodes payload`() async throws {
        let fixtureData = Fixtures.loadData(file: "pugetsound-weather.json")

        dataLoader.mock(data: fixtureData) { request in
            guard let url = request.url else { return false }
            return url.path == "/api/v1/regions/1/weather.json"
        }

        let weather = try await obacoService.getWeather()

        #expect(weather.regionIdentifier == 1)
        #expect(weather.regionName == "Puget Sound")
        #expect(weather.units == "us")
        #expect(!weather.todaySummary.isEmpty)
        #expect(weather.hourlyForecasts.count > 0)
    }

    // MARK: - Ghost Bus Report

    @Test func `postGhostBusReport builds POST form body and decodes response`() async throws {
        var draft = GhostBusReportDraft(
            tripID: "1_18196913",
            serviceDate: Date(timeIntervalSince1970: 1_588_834_800),
            waitDurationMinutes: 15
        )
        draft.routeID = "1_10"
        draft.stopID = "1_75414"
        draft.vehicleID = "1_4351"
        draft.stopSequence = 4
        draft.predicted = true
        draft.scheduledArrivalAt = Date(timeIntervalSince1970: 1_588_834_800)
        draft.predictedArrivalAt = Date(timeIntervalSince1970: 1_588_834_900)
        draft.scheduleDeviationMinutes = 2
        draft.predictionLastUpdatedAt = Date(timeIntervalSince1970: 1_588_834_750)
        draft.comment = "Bus never appeared at stop"
        draft.userLatitude = 47.6062
        draft.userLongitude = -122.3321

        let mockResponseJSON = """
        {
            "id": "gbr_999"
        }
        """
        let mockResponseData = Data(mockResponseJSON.utf8)

        dataLoader.mock(data: mockResponseData) { request in
            guard let url = request.url else { return false }
            guard url.path == "/api/v2/regions/1/ghost_bus_reports" else { return false }
            guard request.httpMethod == "POST" else { return false }

            if let body = request.httpBody, let bodyString = String(data: body, encoding: .utf8) {
                return bodyString.contains("trip_identifier=1_18196913") &&
                    bodyString.contains("wait_duration_minutes=15") &&
                    bodyString.contains("route_identifier=1_10")
            }
            return false
        }

        let report = try await obacoService.postGhostBusReport(draft, userID: "rider_uuid")

        #expect(report.id == "gbr_999")
    }

    // MARK: - Push Registrations

    @Test func `postPushRegistration sends testDevice and description correctly`() async throws {
        dataLoader.mock(data: Data()) { request in
            guard let url = request.url else { return false }
            guard url.path == "/api/v2/regions/1/push_registrations" else { return false }
            guard request.httpMethod == "POST" else { return false }

            if let body = request.httpBody, let bodyString = String(data: body, encoding: .utf8) {
                return bodyString.contains("token=aabbccdd") &&
                    bodyString.contains("locale=en_US") &&
                    bodyString.contains("test_device=true") &&
                    bodyString.contains("description=Test%20iPhone")
            }
            return false
        }

        try await obacoService.postPushRegistration(
            token: "aabbccdd",
            locale: "en_US",
            testDevice: true,
            description: "Test iPhone"
        )
    }

    @Test func `deletePushRegistration includes token query item with DELETE method`() async throws {
        dataLoader.mock(data: Data()) { request in
            guard let url = request.url else { return false }
            guard url.path == "/api/v2/regions/1/push_registrations" else { return false }
            guard request.httpMethod == "DELETE" else { return false }
            return url.query?.contains("token=feedbeef") == true
        }

        let (_, response) = try await obacoService.deletePushRegistration(token: "feedbeef")
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
    }

    // MARK: - Vehicles query

    @Test func `getVehicles queries vehicles endpoint with query parameter`() async throws {
        let fixtureData = Fixtures.loadData(file: "vehicles-query-1_1.json")

        dataLoader.mock(data: fixtureData) { request in
            guard let url = request.url else { return false }
            return url.path == "/api/v1/regions/1/vehicles" && url.query?.contains("query=10") == true
        }

        let vehicles = try await obacoService.getVehicles(matching: "10")
        #expect(!vehicles.isEmpty)
    }
}
