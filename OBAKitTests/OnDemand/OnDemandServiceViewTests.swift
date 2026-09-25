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
import UIKit
@testable import OBAKit
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class OnDemandServiceViewTests: OBATestCase {

    private func alexandria() throws -> OnDemandService {
        try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<OnDemandService>.self, from: Fixtures.loadData(file: "ondemand_service_alexandria.json")).entry
    }

    /// The Alexandria service with each `references[referenceKey]` element
    /// rewritten by `transform`.
    private func alexandria(rewriting referenceKey: String, _ transform: @escaping (inout [String: Any]) -> Void) throws -> OnDemandService {
        let data = Fixtures.loadData(file: "ondemand_service_alexandria.json")
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var body = try #require(json["data"] as? [String: Any])
        var references = try #require(body["references"] as? [String: Any])
        let elements = try #require(references[referenceKey] as? [[String: Any]])
        references[referenceKey] = elements.map { element in
            var rewritten = element
            transform(&rewritten)
            return rewritten
        }
        body["references"] = references
        json["data"] = body
        return try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<OnDemandService>.self, from: JSONSerialization.data(withJSONObject: json)).entry
    }

    /// Alexandria with an agency zone identifier Foundation can't resolve.
    private func alexandriaWithUnknownTimeZone() throws -> OnDemandService {
        let service = try alexandria(rewriting: "agencies") { $0["timezone"] = "Nowhere/Unknown" }
        #expect(service.timeZone == nil)
        return service
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
        let summary = OnDemandServiceSummary(service: service, timeZone: service.timeZone, now: now, locale: Locale(identifier: "en_US"))
        let view = OnDemandServiceView(service: service, summary: summary, onOpenURL: { _ in })
        #expect(view.showsMap)
        #expect(view.bookingLineText?.contains("Mar 11") == true)
    }

    @Test func `Service with no polygons renders no map section`() throws {
        let service = try charlevoixFerry()
        let summary = OnDemandServiceSummary(service: service, timeZone: nil, now: now, locale: Locale(identifier: "en_US"))
        let view = OnDemandServiceView(service: service, summary: summary, onOpenURL: { _ in })
        #expect(!view.showsMap)
        #expect(view.bookingLineText == nil, "no zone → unknown line → no deadline line")
        #expect(view.hasContactDetails)
        #expect(view.summary.phoneNumber == "(231) 547-7244")
        #expect(view.infoURL == URL(string: "https://ccttransit.routematch.com/customer/"))
    }

    @Test func `Area whose only ring is degenerate renders no map section`() throws {
        let service = try alexandria(rewriting: "serviceAreas") {
            $0["geometry"] = ["type": "Polygon", "coordinates": [[[-77.05, 38.8], [-77.04, 38.81]]]]
        }
        #expect(service.areas.first?.hasGeometry == true, "the ring decodes; only MapKit can't draw it")
        let summary = OnDemandServiceSummary(service: service, timeZone: service.timeZone, now: now, locale: Locale(identifier: "en_US"))
        let view = OnDemandServiceView(service: service, summary: summary, onOpenURL: { _ in })
        #expect(!view.showsMap)
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

    @Test func `Hosting controller keeps contact details when the agency time zone is unknown`() throws {
        let dataLoader = MockDataLoader(testName: name)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        let application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
        let controller = OnDemandServiceViewController(application: application, service: try alexandriaWithUnknownTimeZone())
        let summary = controller.rootView.summary
        #expect(summary.bookingLine == .unknown)
        #expect(summary.phoneNumber == "703-746-5222")
        #expect(summary.bookingURL?.host() == "spare-rider-alexandriadot-production.vercel.app")
        #expect(controller.rootView.hasContactDetails)
    }

    // MARK: - Refreshing the booking line

    /// Alexandria's calendars cut to end on Wed 2026-03-11, so once Tuesday's
    /// 17:00 cutoff passes no service day is left to book.
    private func alexandriaEndingWednesday() throws -> OnDemandService {
        try alexandria(rewriting: "calendars") { $0["endDate"] = "2026-03-11" }
    }

    private func makeController(service: OnDemandService, clock: SendableBox<Date>) -> OnDemandServiceViewController {
        let dataLoader = MockDataLoader(testName: name)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        let application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
        return OnDemandServiceViewController(application: application, service: service, now: { clock.value })
    }

    /// A rider who calls and comes back after the cutoff must not still see
    /// "Book by today at 5:00 PM".
    @Test func `Refreshing past the cutoff replaces the book-by line`() async throws {
        let clock = SendableBox(now)
        let controller = makeController(service: try alexandriaEndingWednesday(), clock: clock)
        #expect(controller.rootView.bookingLineText?.contains("5:00") == true)

        // 2026-03-10 17:30 in Los Angeles.
        clock.value = ISO8601DateFormatter().date(from: "2026-03-11T00:30:00Z")!
        controller.refreshSummary()
        await controller.summaryBuildTask?.value

        #expect(controller.rootView.bookingLineText == Strings.onDemandBookingClosed)
    }

    @Test func `Returning to the foreground refreshes the booking line`() async throws {
        let clock = SendableBox(now)
        let controller = makeController(service: try alexandriaEndingWednesday(), clock: clock)
        let window = UIWindow()
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }

        clock.value = ISO8601DateFormatter().date(from: "2026-03-11T00:30:00Z")!
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        await controller.summaryBuildTask?.value

        #expect(controller.rootView.bookingLineText == Strings.onDemandBookingClosed)
    }

    /// A page that isn't on screen catches up in `viewWillAppear` instead.
    @Test func `Returning to the foreground leaves an off-screen page alone`() throws {
        let clock = SendableBox(now)
        let controller = makeController(service: try alexandriaEndingWednesday(), clock: clock)
        let bookByLine = controller.rootView.bookingLineText

        clock.value = ISO8601DateFormatter().date(from: "2026-03-11T00:30:00Z")!
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)

        #expect(controller.summaryBuildTask == nil)
        #expect(controller.rootView.bookingLineText == bookByLine)
    }

    /// Only the newest rebuild lands, whichever finishes first.
    @Test func `A superseded rebuild never replaces a newer one`() async throws {
        let clock = SendableBox(ISO8601DateFormatter().date(from: "2026-03-11T00:30:00Z")!)
        let controller = makeController(service: try alexandriaEndingWednesday(), clock: clock)
        controller.refreshSummary()
        let staleBuild = try #require(controller.summaryBuildTask)

        clock.value = now
        controller.refreshSummary()
        await staleBuild.value
        await controller.summaryBuildTask?.value

        #expect(staleBuild.isCancelled)
        #expect(controller.rootView.bookingLineText?.contains("5:00") == true)
    }

    /// The one-shot timer fires at the earliest instant the line can change.
    @Test func `The next change instant is the shown cutoff`() throws {
        let clock = SendableBox(now)
        let controller = makeController(service: try alexandriaEndingWednesday(), clock: clock)

        // Tuesday 17:00 in Los Angeles (PDT).
        #expect(controller.rootView.summary.nextChangeInstant == ISO8601DateFormatter().date(from: "2026-03-11T00:00:00Z"))
    }

    /// A page left open overnight must not keep saying "tomorrow" once
    /// tomorrow has become today.
    @Test func `Refreshing past agency midnight updates the relative day`() async throws {
        // Mon 2026-03-09 23:30 in Los Angeles; Wednesday's ride is booked by Tue 17:00.
        let clock = SendableBox(ISO8601DateFormatter().date(from: "2026-03-10T06:30:00Z")!)
        let controller = makeController(service: try alexandria(), clock: clock)
        let beforeMidnight = try #require(controller.rootView.bookingLineText)
        // Tue 00:00 PDT comes before the 17:00 cutoff, so midnight is the boundary.
        let midnight = try #require(ISO8601DateFormatter().date(from: "2026-03-10T07:00:00Z"))
        #expect(controller.rootView.summary.nextChangeInstant == midnight)

        clock.value = midnight.addingTimeInterval(30 * 60)
        controller.refreshSummary()
        await controller.summaryBuildTask?.value

        let afterMidnight = try #require(controller.rootView.bookingLineText)
        #expect(afterMidnight != beforeMidnight, "the deadline moved from tomorrow to today")
        #expect(afterMidnight.contains("5:00"), "\(afterMidnight)")
    }
}
