//
//  OnDemandSupportTests.swift
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
final class OnDemandSupportTests: OBATestCase {
    private var support: OnDemandSupport!
    private var dataLoader: MockDataLoader!
    private var service: RESTAPIService!

    private let region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 38.83, longitude: -77.05),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )

    override init() async throws {
        try await super.init()
        support = OnDemandSupport()
        dataLoader = MockDataLoader(testName: name)
        service = buildRESTService(dataLoader: dataLoader, onDemandSupport: support)
    }

    private func mock(path: String, statusCode: Int, data: Data = Data()) {
        dataLoader.mock(data: data, statusCode: statusCode) { request in
            request.url?.path.contains(path) ?? false
        }
    }

    @Test func `Fresh support knows nothing`() {
        #expect(!support.isKnownUnsupported(baseURL: baseURL))
    }

    @Test func `Trailing slash does not change the key`() {
        support.recordAbsent(baseURL: URL(string: "https://www.example.com/")!)
        #expect(support.isKnownUnsupported(baseURL: URL(string: "https://www.example.com")!))
    }

    @Test func `404 on the location probe marks the server unsupported`() async {
        mock(path: "/api/ondemand/services-for-location", statusCode: 404)
        await #expect(throws: APIError.self) {
            _ = try await service.getOnDemandServices(region: region)
        }
        #expect(support.isKnownUnsupported(baseURL: baseURL))
    }

    @Test func `Blank 200 on the location probe marks the server unsupported`() async {
        // Legacy servers answer unknown paths with an empty 200; APIService maps
        // that to requestNotFound for GETs.
        mock(path: "/api/ondemand/services-for-location", statusCode: 200)
        await #expect(throws: APIError.self) {
            _ = try await service.getOnDemandServices(region: region)
        }
        #expect(support.isKnownUnsupported(baseURL: baseURL))
    }

    @Test func `404 on service by id is not-found, not unsupported`() async {
        mock(path: "/api/ondemand/service/", statusCode: 404)
        await #expect(throws: APIError.self) {
            _ = try await service.getOnDemandService(id: "nope")
        }
        #expect(!support.isKnownUnsupported(baseURL: baseURL))
    }

    @Test func `404 on services for agency is not-found, not unsupported`() async {
        mock(path: "/api/ondemand/services-for-agency/", statusCode: 404)
        await #expect(throws: APIError.self) {
            _ = try await service.getOnDemandServices(agencyID: "nope")
        }
        #expect(!support.isKnownUnsupported(baseURL: baseURL))
    }

    @Test func `Server error on the probe is transient`() async {
        mock(path: "/api/ondemand/services-for-location", statusCode: 500)
        await #expect(throws: APIError.self) {
            _ = try await service.getOnDemandServices(region: region)
        }
        #expect(!support.isKnownUnsupported(baseURL: baseURL))
    }

    @Test func `Decode failure on the probe is transient`() async {
        mock(path: "/api/ondemand/services-for-location", statusCode: 200, data: Data("{\"code\":200,\"version\":2,\"data\":{\"list\":\"not-an-array\"}}".utf8))
        await #expect(throws: (any Error).self) {
            _ = try await service.getOnDemandServices(region: region)
        }
        #expect(!support.isKnownUnsupported(baseURL: baseURL))
    }

    @Test func `Success leaves support untouched`() async throws {
        dataLoader.mock(
            URLString: "https://www.example.com/api/ondemand/services-for-location.json",
            with: Fixtures.loadData(file: "ondemand_services_for_location_viewport.json")
        )
        _ = try await service.getOnDemandServices(region: region)
        #expect(!support.isKnownUnsupported(baseURL: baseURL))
    }

    @Test func `Absence is recorded per base URL`() async {
        mock(path: "/api/ondemand/services-for-location", statusCode: 404)
        await #expect(throws: APIError.self) {
            _ = try await service.getOnDemandServices(region: region)
        }
        #expect(support.isKnownUnsupported(baseURL: baseURL))
        #expect(!support.isKnownUnsupported(baseURL: URL(string: "https://other.example.com")!))

        let otherConfig = APIServiceConfiguration(baseURL: URL(string: "https://other.example.com")!, apiKey: apiKey, uuid: uuid, appVersion: appVersion, regionIdentifier: 2)
        let otherService = RESTAPIService(otherConfig, dataLoader: dataLoader, onDemandSupport: support)
        #expect(otherService.baseURL == URL(string: "https://other.example.com")!)
        #expect(!support.isKnownUnsupported(baseURL: otherService.baseURL))
    }
}
