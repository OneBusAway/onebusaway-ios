//
//  OnDemandModelOperationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import MapKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast

@Suite(.serialized)
final class OnDemandModelOperationTests: OBATestCase {
    var dataLoader: MockDataLoader!

    override init() async throws {
        try await super.init()
        dataLoader = (restService.dataLoader as! MockDataLoader)
    }

    @Test func `Loading a service by id`() async throws {
        dataLoader.mock(
            URLString: "https://www.example.com/api/ondemand/service/5088_77652.json",
            with: Fixtures.loadData(file: "ondemand_service_alexandria.json")
        )

        let response = try await restService.getOnDemandService(id: "5088_77652")
        let service = response.entry
        #expect(service.id == "5088_77652")
        #expect(service.serviceKind == .zone)
        #expect(service.rules.count == 2)
        #expect(service.areas.map(\.id) == ["5088_area_1449"])
        #expect(service.bookingRules.first?.phoneNumber == "703-746-5222")
        #expect(service.calendars.count == 2)
        #expect(service.route?.longName == "DOT Paratransit")
        #expect(service.agency?.timeZone == "America/Los_Angeles")
        #expect(service.regionIdentifier == pugetSoundRegionIdentifier)

        let requested = dataLoader.recordedRequestURLs.last!
        #expect(URLComponents(url: requested, resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "geometryDetail", value: "full")) == true)
    }

    @Test func `Loading services for a region`() async throws {
        dataLoader.mock(
            URLString: "https://www.example.com/api/ondemand/services-for-location.json",
            with: Fixtures.loadData(file: "ondemand_services_for_location_viewport.json")
        )
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 38.83, longitude: -77.05),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )

        let response = try await restService.getOnDemandServices(region: region)
        #expect(response.list.map(\.id) == ["5088_77652"])
        #expect(response.list[0].matchReason == .areaIntersectsViewport)
        #expect(response.outOfRange == false)

        let requested = dataLoader.recordedRequestURLs.last!
        #expect(URLComponents(url: requested, resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "geometryDetail", value: "simplified")) == true)
    }

    @Test func `Loading services for an agency`() async throws {
        dataLoader.mock(
            URLString: "https://www.example.com/api/ondemand/services-for-agency/CC.json",
            with: Fixtures.loadData(file: "ondemand_services_for_agency_charlevoix.json")
        )

        let response = try await restService.getOnDemandServices(agencyID: "CC")
        #expect(response.list.map(\.id) == ["CC_CC1", "CC_CC2_med", "CC_CC3", "CC_CC4"])
        #expect(response.list[2].serviceKind == .stopGroup)
        #expect(response.list[2].locationGroups.first?.stopIDs.count == 2)

        let requested = dataLoader.recordedRequestURLs.last!
        #expect(URLComponents(url: requested, resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "geometryDetail", value: "simplified")) == true)
    }

    @Test func `Loading services near a point`() async throws {
        dataLoader.mock(
            URLString: "https://www.example.com/api/ondemand/services-for-location.json",
            with: Fixtures.loadData(file: "ondemand_services_for_location_point_near.json")
        )

        let response = try await restService.getOnDemandServices(
            near: CLLocationCoordinate2D(latitude: 45.3, longitude: -85.2),
            radiusMeters: 5000
        )
        #expect(response.list.map(\.id) == ["CC_CC1"])
        #expect(response.list[0].matchReason == .areaNearby)
        #expect(response.list[0].areas.first?.distanceToArea == 850)
        #expect(response.list[0].areas.first?.nearestPointOnBoundary?.latitude == 45.30765)
        #expect(response.list[0].areas.first?.nearestPointOnBoundary?.longitude == -85.2)

        let requested = dataLoader.recordedRequestURLs.last!
        let items = URLComponents(url: requested, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "radius", value: "5000.0")))
        #expect(items.contains(URLQueryItem(name: "geometryDetail", value: "none")))
    }

    @Test func `A 404 near a point records the server as unsupported`() async throws {
        let support = OnDemandSupport()
        let service = buildRESTService(dataLoader: dataLoader, onDemandSupport: support)
        dataLoader.mock(data: Data(), statusCode: 404) { request in
            request.url?.path.contains("/api/ondemand/services-for-location") ?? false
        }

        await #expect(throws: APIError.self) {
            _ = try await service.getOnDemandServices(near: CLLocationCoordinate2D(latitude: 45.3, longitude: -85.2), radiusMeters: 5000)
        }
        #expect(support.isKnownUnsupported(baseURL: baseURL))
    }

    @Test func `Eligibility decodes when present and is nil when absent`() throws {
        let data = Fixtures.loadData(file: "ondemand_service_alexandria.json")
        let absent = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<OnDemandService>.self, from: data).entry
        #expect(absent.eligibility == nil)

        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var body = json["data"] as! [String: Any]
        var entry = body["entry"] as! [String: Any]
        entry["eligibility"] = ["requirement": "certificationRequired", "infoUrl": "https://example.com/apply"]
        body["entry"] = entry
        json["data"] = body
        let present = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<OnDemandService>.self, from: JSONSerialization.data(withJSONObject: json)).entry
        #expect(present.eligibility?.requirement == .certificationRequired)
        #expect(present.eligibility?.infoURL == URL(string: "https://example.com/apply"))

        entry["eligibility"] = ["requirement": "somethingNewer", "infoUrl": nil]
        body["entry"] = entry
        json["data"] = body
        let newer = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<OnDemandService>.self, from: JSONSerialization.data(withJSONObject: json)).entry
        #expect(newer.eligibility?.requirement == .unknown)
        #expect(newer.eligibility?.infoURL == nil)
    }
}
