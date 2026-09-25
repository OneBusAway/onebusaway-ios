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
    }
}
