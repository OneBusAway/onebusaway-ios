//
//  OnDemandReferencesTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class OnDemandReferencesTests: OBATestCase {

    private func decodeEntry(_ file: String) throws -> RESTAPIResponse<OnDemandService> {
        try JSONDecoder.RESTDecoder(regionIdentifier: pugetSoundRegionIdentifier)
            .decode(RESTAPIResponse<OnDemandService>.self, from: Fixtures.loadData(file: file))
    }

    private func decodeList(_ file: String) throws -> RESTAPIResponse<[OnDemandService]> {
        try JSONDecoder.RESTDecoder(regionIdentifier: pugetSoundRegionIdentifier)
            .decode(RESTAPIResponse<[OnDemandService]>.self, from: Fixtures.loadData(file: file))
    }

    @Test func `References carry the four on-demand arrays`() throws {
        let references = try decodeEntry("ondemand_service_alexandria.json").references!
        #expect(references.serviceAreas.map(\.id) == ["5088_area_1449"])
        #expect(references.locationGroups.isEmpty)
        #expect(references.bookingRules.map(\.id) == ["5088_booking_route_77652"])
        #expect(references.calendars.map(\.id) == ["5088_c_71675_b_85952_d_63", "5088_c_71675_b_85952_d_64"])
        #expect(references.agencies.first?.timeZone == "America/Los_Angeles")
        #expect(references.routes.first?.longName == "DOT Paratransit")
    }

    @Test func `Finders resolve by id and return nil for unknown or nil ids`() throws {
        let references = try decodeEntry("ondemand_service_alexandria.json").references!
        #expect(references.serviceAreaWithID("5088_area_1449")?.id == "5088_area_1449")
        #expect(references.bookingRuleWithID("5088_booking_route_77652")?.phoneNumber == "703-746-5222")
        #expect(references.calendarWithID("5088_c_71675_b_85952_d_64")?.days == [.sun])
        #expect(references.locationGroupWithID("nope") == nil)
        #expect(references.serviceAreaWithID(nil) == nil)
        #expect(references.bookingRuleWithID(nil) == nil)
        #expect(references.calendarWithID(nil) == nil)
    }

    @Test func `Legacy references decode with empty on-demand arrays`() throws {
        let data = Fixtures.loadData(file: "references.json")
        let references = try JSONDecoder.RESTDecoder().decode(References.self, from: data)
        #expect(references.serviceAreas.isEmpty)
        #expect(references.locationGroups.isEmpty)
        #expect(references.bookingRules.isEmpty)
        #expect(references.calendars.isEmpty)
    }

    @Test func `Entry response resolves the service's references`() throws {
        let service = try decodeEntry("ondemand_service_alexandria.json").entry
        #expect(service.route?.id == "5088_77652")
        #expect(service.agency?.id == "5088")
        #expect(service.timeZone?.identifier == "America/Los_Angeles")
        #expect(service.areas.map(\.id) == ["5088_area_1449"])
        #expect(service.bookingRules.map(\.id) == ["5088_booking_route_77652"])
        #expect(service.calendars.map(\.id) == ["5088_c_71675_b_85952_d_63", "5088_c_71675_b_85952_d_64"])
        #expect(service.locationGroups.isEmpty)
        #expect(service.regionIdentifier == pugetSoundRegionIdentifier)
        #expect(service.bookingRule(id: "5088_booking_route_77652")?.bookingType == 2)
        #expect(service.bookingRule(id: "missing") == nil)
        #expect(service.bookingRule(id: nil) == nil)
    }

    @Test func `Location list response resolves every element and carries match reasons`() throws {
        let response = try decodeList("ondemand_services_for_location_viewport.json")
        #expect(response.list.map(\.id) == ["5088_77652"])
        #expect(response.list[0].matchReason == .areaIntersectsViewport)
        #expect(response.list[0].areas.count == 1)
        #expect(response.list[0].areas[0].hasGeometry, "list endpoints default to simplified geometry")
        #expect(response.list[0].areas[0].distanceToArea == nil, "viewport mode carries no distance")
        #expect(response.outOfRange == false)
        #expect(response.limitExceeded == false)

        let point = try decodeList("ondemand_services_for_location_point.json")
        #expect(point.list[0].matchReason == .areaContainsPoint)
        #expect(point.list[0].areas[0].distanceToArea == 0)
        #expect(point.list[0].areas[0].nearestPointOnBoundary == nil)
    }

    @Test func `Charlevoix agency list resolves a stop group and its stops`() throws {
        let response = try decodeList("ondemand_services_for_agency_charlevoix.json")
        #expect(response.list.map(\.id) == ["CC_CC1", "CC_CC2_med", "CC_CC3", "CC_CC4"])
        #expect(response.list.map(\.serviceKind) == [.zone, .zoneToZone, .stopGroup, .zone])

        let ferry = response.list[2]
        #expect(ferry.locationGroups.count == 1)
        #expect(ferry.locationGroups[0].stopIDs.count == 2)
        #expect(ferry.areas.isEmpty)
        let members = response.references!.stopsWithIDs(ferry.locationGroups[0].stopIDs)
        #expect(members.count == 2)
        #expect(ferry.agency?.timeZone == "America/Detroit")
        #expect(ferry.calendars.count >= 1)
        #expect(response.list[0].calendars.map(\.id).sorted() == ["CC_mon-tues-wed-thurs-fri", "CC_sat"])
    }
}
