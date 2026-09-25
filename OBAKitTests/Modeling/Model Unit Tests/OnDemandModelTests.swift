//
//  OnDemandModelTests.swift
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

// swiftlint:disable force_cast

@Suite(.serialized)
final class OnDemandModelTests: OBATestCase {

    private func decodeService(_ json: String) throws -> OnDemandService {
        try JSONDecoder.RESTDecoder().decode(OnDemandService.self, from: Data(json.utf8))
    }

    // MARK: - GTFSTimeOfDay

    @Test func `Time of day parses plain and post-midnight values`() {
        #expect(GTFSTimeOfDay("05:00:00")?.seconds == 18_000)
        #expect(GTFSTimeOfDay("24:50:00")?.seconds == 89_400)
        #expect(GTFSTimeOfDay("25:00:00")?.seconds == 90_000)
        #expect(GTFSTimeOfDay("7:05:09")?.seconds == 25_509)
        #expect(GTFSTimeOfDay("05:00") == nil)
        #expect(GTFSTimeOfDay("05:60:00") == nil)
        #expect(GTFSTimeOfDay("abc") == nil)
        #expect(GTFSTimeOfDay(seconds: 89_400).description == "24:50:00")
        #expect(GTFSTimeOfDay.midnight < GTFSTimeOfDay.endOfServiceDay)
    }

    // MARK: - ServiceDate / Weekday

    @Test func `Service date parses and compares`() {
        let date = ServiceDate("2026-03-11")
        #expect(date == ServiceDate(year: 2026, month: 3, day: 11))
        #expect(date?.description == "2026-03-11")
        #expect(ServiceDate("2026-3-11") == nil)
        #expect(ServiceDate("20260311") == nil)
        #expect(ServiceDate(year: 2026, month: 3, day: 11) < ServiceDate(year: 2026, month: 12, day: 1))
        #expect(Weekday(calendarWeekday: 1) == .sun)
        #expect(Weekday(calendarWeekday: 7) == .sat)
        #expect(Weekday.mon.calendarWeekday == 2)
    }

    // MARK: - Enums

    @Test func `Unknown service kind and match reason fall back to unknown`() throws {
        let service = try decodeService("""
        {"id":"x_1","agencyId":"x","routeId":null,"name":"X","serviceKind":"curbToCurb",
         "description":null,"url":null,"rules":[],"matchReason":"somethingNew"}
        """)
        #expect(service.serviceKind == .unknown)
        #expect(service.matchReason == .unknown)
        #expect(service.routeID == nil)
        #expect(service.rules.isEmpty)
    }

    // MARK: - Equality

    @Test func `Services compare and hash by id`() throws {
        let json = """
        {"id":"x_1","agencyId":"x","routeId":null,"name":"X","serviceKind":"zone",
         "description":null,"url":null,"rules":[],"matchReason":null}
        """
        let first = try decodeService(json)
        let second = try decodeService(json)
        let other = try decodeService(json.replacingOccurrences(of: "x_1", with: "x_2"))

        #expect(first !== second)
        #expect(first == second)
        #expect(first.hash == second.hash)
        #expect(first != other)
        #expect(Set([first, second, other]).count == 2)
    }

    // MARK: - Entry decoding (wiki §3.4 worked example)

    @Test func `Alexandria service decodes`() throws {
        let data = Fixtures.loadData(file: "ondemand_service_alexandria.json")
        let response = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<OnDemandService>.self, from: data)
        let service = response.entry

        #expect(service.id == "5088_77652")
        #expect(service.agencyID == "5088")
        #expect(service.routeID == "5088_77652")
        #expect(service.name == "DOT Paratransit")
        #expect(service.serviceKind == .zone)
        #expect(service.serviceDescription == nil)
        #expect(service.url == nil)
        #expect(service.matchReason == nil)
        #expect(service.rules.count == 2)

        let first = service.rules[0]
        #expect(first.fromIDs == ["5088_area_1449"])
        #expect(first.toIDs == ["5088_area_1449"])
        #expect(first.startPickupTime == GTFSTimeOfDay("05:00:00"))
        #expect(first.endPickupTime == GTFSTimeOfDay("24:50:00"))
        #expect(first.endDropOffTime == GTFSTimeOfDay("25:00:00"))
        #expect(first.calendarIDs == ["5088_c_71675_b_85952_d_63"])
        #expect(first.pickupType == 2)
        #expect(first.dropOffType == 2)
        #expect(first.pickupBookingRuleID == "5088_booking_route_77652")
        #expect(first.dropOffBookingRuleID == "5088_booking_route_77652")
        #expect(first.safeDurationFactor == 1.0)
        #expect(first.safeDurationOffset == 0.0)

        #expect(service.rules[1].startPickupTime == GTFSTimeOfDay("07:00:00"))
        #expect(service.rules[1].calendarIDs == ["5088_c_71675_b_85952_d_64"])
    }

    @Test func `Service area decodes bbox and polygon geometry`() throws {
        let data = Fixtures.loadData(file: "ondemand_service_alexandria.json")
        let container = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let areasJSON = try JSONSerialization.data(withJSONObject: ((container["data"] as! [String: Any])["references"] as! [String: Any])["serviceAreas"]!)
        let areas = try JSONDecoder().decode([ServiceArea].self, from: areasJSON)

        #expect(areas.count == 1)
        let area = areas[0]
        #expect(area.id == "5088_area_1449")
        #expect(area.name == nil)
        #expect(area.areaDescription == nil)
        expectClose(area.bbox.minLongitude, -77.5372039)
        expectClose(area.bbox.minLatitude, 38.617508)
        expectClose(area.bbox.maxLongitude, -76.9092198)
        expectClose(area.bbox.maxLatitude, 39.057831)
        #expect(area.hasGeometry)
        #expect(area.polygons.count == 1)
        #expect(area.polygons[0].count == 1, "Alexandria's zone has no holes")
        #expect(area.polygons[0][0].count == 4239)
        // GeoJSON positions are [lon, lat]; a swap would put latitude at -77.
        expectClose(area.polygons[0][0][0].latitude, 38.8762916)
        expectClose(area.polygons[0][0][0].longitude, -77.0464775)
        #expect(area.distanceToArea == nil)
        #expect(area.nearestPointOnBoundary == nil)
        expectClose(area.bbox.center.latitude, (38.617508 + 39.057831) / 2)
    }

    @Test func `Service area without geometry decodes with no polygons`() throws {
        let json = """
        {"id":"x_a","name":"Zone","description":"d","bbox":[-1.0,2.0,3.0,4.0]}
        """
        let area = try JSONDecoder().decode(ServiceArea.self, from: Data(json.utf8))
        #expect(!area.hasGeometry)
        #expect(area.polygons.isEmpty)
        #expect(area.name == "Zone")
        #expect(area.areaDescription == "d")
    }

    @Test func `MultiPolygon with a hole decodes exterior and interior rings`() throws {
        let json = """
        {"id":"x_m","name":null,"description":null,"bbox":[0.0,0.0,10.0,10.0],
         "geometry":{"type":"MultiPolygon","coordinates":[
           [[[0,0],[10,0],[10,10],[0,10],[0,0]],[[4,4],[6,4],[6,6],[4,6],[4,4]]],
           [[[20,20],[21,20],[21,21],[20,20]]]
         ]},
         "distanceToArea":1234.5,"nearestPointOnBoundary":[-77.1,38.8]}
        """
        let area = try JSONDecoder().decode(ServiceArea.self, from: Data(json.utf8))
        #expect(area.polygons.count == 2)
        #expect(area.polygons[0].count == 2)
        #expect(area.polygons[0][0].count == 5)
        #expect(area.polygons[0][1].count == 5)
        expectClose(area.polygons[0][1][0].latitude, 4)
        expectClose(area.polygons[0][1][0].longitude, 4)
        #expect(area.polygons[1].count == 1)
        expectClose(area.polygons[1][0][1].latitude, 20)
        expectClose(area.polygons[1][0][1].longitude, 21)
        #expect(area.distanceToArea == 1234.5)
        expectClose(area.nearestPointOnBoundary?.latitude, 38.8)
        expectClose(area.nearestPointOnBoundary?.longitude, -77.1)
    }

    @Test func `Unsupported geometry type decodes with no polygons`() throws {
        let json = """
        {"id":"x_p","name":null,"description":null,"bbox":[0,0,1,1],"geometry":{"type":"Point","coordinates":[0.5,0.5]}}
        """
        let area = try JSONDecoder().decode(ServiceArea.self, from: Data(json.utf8))
        #expect(area.polygons.isEmpty)
        #expect(!area.hasGeometry)
    }

    @Test func `Booking rule and calendar decode`() throws {
        let data = Fixtures.loadData(file: "ondemand_service_alexandria.json")
        let container = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let refs = (container["data"] as! [String: Any])["references"] as! [String: Any]

        let rules = try JSONDecoder().decode([OnDemandBookingRule].self, from: JSONSerialization.data(withJSONObject: refs["bookingRules"]!))
        #expect(rules.count == 1)
        let rule = rules[0]
        #expect(rule.id == "5088_booking_route_77652")
        #expect(rule.bookingType == 2)
        #expect(rule.priorNoticeDurationMin == nil)
        #expect(rule.priorNoticeDurationMax == nil)
        #expect(rule.priorNoticeLastDay == 1)
        #expect(rule.priorNoticeLastTime == GTFSTimeOfDay("17:00:00"))
        #expect(rule.priorNoticeStartDay == 14)
        #expect(rule.priorNoticeStartTime == GTFSTimeOfDay("00:00:00"))
        #expect(rule.priorNoticeCalendarID == nil)
        #expect(rule.message?.hasPrefix("DOT is the City of Alexandria") == true)
        #expect(rule.pickupMessage == nil)
        #expect(rule.phoneNumber == "703-746-5222")
        #expect(rule.infoURL == URL(string: "https://www.alexandriava.gov/Paratransit"))
        #expect(rule.bookingURL?.host() == "spare-rider-alexandriadot-production.vercel.app")

        let calendars = try JSONDecoder().decode([OnDemandCalendar].self, from: JSONSerialization.data(withJSONObject: refs["calendars"]!))
        #expect(calendars.map(\.id) == ["5088_c_71675_b_85952_d_63", "5088_c_71675_b_85952_d_64"])
        #expect(calendars[0].days == [.mon, .tue, .wed, .thu, .fri, .sat])
        #expect(calendars[1].days == [.sun])
        #expect(calendars[0].startDate == ServiceDate("2025-12-01"))
        #expect(calendars[0].endDate == ServiceDate("2026-12-01"))
        #expect(calendars[0].exceptedDates.isEmpty)
    }

    @Test func `Location group decodes`() throws {
        let json = """
        {"id":"CC_group","name":null,"stopIds":["CC_CC_Ironton_Ferry_West","CC_CC_Ironton_Ferry_East"]}
        """
        let group = try JSONDecoder().decode(OnDemandLocationGroup.self, from: Data(json.utf8))
        #expect(group.id == "CC_group")
        #expect(group.name == nil)
        #expect(group.stopIDs.count == 2)
    }

    @Test func `Calendar skips unknown day names`() throws {
        let json = """
        {"id":"c","days":["mon","funday","sun"],"startDate":"2026-01-01","endDate":"2026-12-31","exceptedDates":["2026-07-04"]}
        """
        let calendar = try JSONDecoder().decode(OnDemandCalendar.self, from: Data(json.utf8))
        #expect(calendar.days == [.mon, .sun])
        #expect(calendar.exceptedDates == [ServiceDate("2026-07-04")!])
    }
}

// swiftlint:enable force_cast
