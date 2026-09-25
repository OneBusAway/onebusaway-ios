//
//  OnDemandServiceViewTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class OnDemandServiceViewTests: OBATestCase {

    private func alexandria() throws -> OnDemandService {
        try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<OnDemandService>.self, from: Fixtures.loadData(file: "ondemand_service_alexandria.json")).entry
    }

    private func charlevoixFerry() throws -> OnDemandService {
        let list = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<[OnDemandService]>.self, from: Fixtures.loadData(file: "ondemand_services_for_agency_charlevoix.json")).list
        return list.first { $0.id == "CC_CC3" }!
    }

    private var now: Date { ISO8601DateFormatter().date(from: "2026-03-10T23:00:00Z")! }

    @Test func `MKPolygon carries interior rings`() throws {
        let json = """
        {"id":"x","name":null,"description":null,"bbox":[0,0,10,10],
         "geometry":{"type":"Polygon","coordinates":[[[0,0],[10,0],[10,10],[0,10],[0,0]],[[4,4],[6,4],[6,6],[4,6],[4,4]]]}}
        """
        let area = try JSONDecoder().decode(ServiceArea.self, from: Data(json.utf8))
        let polygons = area.mkPolygons
        #expect(polygons.count == 1)
        #expect(polygons[0].pointCount == 5)
        #expect(polygons[0].interiorPolygons?.count == 1)
        #expect(polygons[0].interiorPolygons?.first?.pointCount == 5)
    }

    @Test func `Area without geometry yields no polygons`() throws {
        let area = try JSONDecoder().decode(ServiceArea.self, from: Data("{\"id\":\"x\",\"bbox\":[0,0,1,1]}".utf8))
        #expect(area.mkPolygons.isEmpty)
    }

    @Test func `Service with polygons shows the map section`() throws {
        let service = try alexandria()
        let summary = OnDemandServiceSummary(service: service, timeZone: service.timeZone!, now: now, locale: Locale(identifier: "en_US"))
        let view = OnDemandServiceView(service: service, summary: summary, onOpenURL: { _ in })
        #expect(view.showsMap)
        #expect(view.bookingLineText?.contains("Mar 11") == true)
    }

    @Test func `Service with no polygons renders no map section`() throws {
        let service = try charlevoixFerry()
        let view = OnDemandServiceView(service: service, summary: nil, onOpenURL: { _ in })
        #expect(!view.showsMap)
        #expect(view.bookingLineText == nil, "no summary → no deadline line")
    }

    @Test func `Booking line templates cover every case`() {
        #expect(OnDemandServiceView.bookingLineText(for: .bookBy(deadline: "D", travelDate: "T")) == String(format: Strings.onDemandBookByFormat, "D", "T"))
        #expect(OnDemandServiceView.bookingLineText(for: .opensAt("O")) == String(format: Strings.onDemandBookingOpensFormat, "O"))
        #expect(OnDemandServiceView.bookingLineText(for: .noNoticeRequired) == Strings.onDemandNoNoticeRequired)
        #expect(OnDemandServiceView.bookingLineText(for: .closed) == Strings.onDemandBookingClosed)
        #expect(OnDemandServiceView.bookingLineText(for: .unknown) == nil)
    }

    @Test func `Kind titles are distinct and non-empty`() {
        let kinds: [ServiceKind] = [.zone, .zoneToZone, .stopGroup, .deviatedRoute, .unknown]
        let titles = kinds.map(Strings.onDemandKindTitle)
        #expect(titles.allSatisfy { !$0.isEmpty })
        #expect(Set(titles).count == kinds.count)
    }

    @Test func `Hosting controller titles itself with the service name`() throws {
        let dataLoader = MockDataLoader(testName: name)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        let application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
        let controller = OnDemandServiceViewController(application: application, service: try alexandria())
        #expect(controller.title == "DOT Paratransit")
    }
}
