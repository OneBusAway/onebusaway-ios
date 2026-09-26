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

// swiftlint:disable force_cast

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

    private func instant(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    private func charlevoix(_ id: String, rewriting transform: ((inout [String: Any]) -> Void)? = nil) throws -> OnDemandService {
        let data = Fixtures.loadData(file: "ondemand_services_for_agency_charlevoix.json")
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        transform?(&json)
        let list = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<[OnDemandService]>.self, from: JSONSerialization.data(withJSONObject: json)).list
        return try #require(list.first { $0.id == id })
    }

    private func makeView(_ service: OnDemandService, timeZone: TimeZone?? = nil, now: Date? = nil, locationCheck: OnDemandLocationCheck? = nil) -> OnDemandServiceView {
        let zone: TimeZone? = timeZone ?? service.timeZone
        let clock = now ?? self.now
        let summary = OnDemandServiceSummary(service: service, timeZone: zone, now: clock, locale: Locale(identifier: "en_US"))
        let availability = OnDemandAvailability.evaluate(service: service, timeZone: zone, now: clock)
        return OnDemandServiceView(service: service, summary: summary, availability: availability, locationCheck: locationCheck, now: clock, onOpenURL: { _ in })
    }

    private let charlevoixPoint = CLLocationCoordinate2D(latitude: 45.3, longitude: -85.2)

    /// `DateFormatter` inserts a narrow no-break space (U+202F) before AM/PM
    /// on this OS; normalise it as `OnDemandZoneCardTests` does.
    private func normalizeSpaces(_ string: String?) -> String? {
        string?.replacingOccurrences(of: "\u{202F}", with: " ")
    }

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
        let view = makeView(try alexandria())
        #expect(view.showsMap)
        #expect(view.bookingLineText?.contains("Mar 11") == true)
    }

    @Test func `Service with no polygons renders no map section`() throws {
        let view = makeView(try charlevoixFerry(), timeZone: .some(nil))
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
        let view = makeView(service)
        #expect(!view.showsMap)
    }

    @Test func `Booking line templates cover every case`() {
        #expect(OnDemandServiceView.bookingLineText(for: .bookBy(deadline: "D", travelDate: "T")) == String(format: Strings.onDemandBookByFormat, "D", "T"))
        #expect(OnDemandServiceView.bookingLineText(for: .opensAt("O")) == String(format: Strings.onDemandBookingOpensFormat, "O"))
        #expect(OnDemandServiceView.bookingLineText(for: .noNoticeRequired) == Strings.onDemandNoNoticeRequired)
        #expect(OnDemandServiceView.bookingLineText(for: .closed) == Strings.onDemandBookingClosed)
        #expect(OnDemandServiceView.bookingLineText(for: .unknown) == nil)
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

    // MARK: - Header card (spec 3.6 item 1)

    /// Tuesday 12:00 EDT: CC1 is open now → tier 1, status line, no promoted row.
    @Test func `Tier one shows the status line in the header and no promoted deadline`() throws {
        let view = makeView(try charlevoix("CC_CC1"), now: instant("2026-03-10T16:00:00Z"))
        #expect(view.tags == [.sameDayBooking])
        #expect(normalizeSpaces(view.statusLineText) == "Open now · until 4:40 PM")
        #expect(view.promotedDeadlineText == nil)
        guard case .call(let phone, _) = view.primaryContact else {
            Issue.record("expected a call pill, got \(String(describing: view.primaryContact))")
            return
        }
        #expect(phone == "(231) 582-6900")
    }

    @Test func `Tier two shows the opens line`() throws {
        let view = makeView(try charlevoix("CC_CC1"), now: instant("2026-03-10T07:00:00Z")) // 03:00 EDT
        #expect(view.statusLineText?.hasPrefix("Opens ") == true, "\(view.statusLineText ?? "nil")")
        #expect(view.promotedDeadlineText == nil)
    }

    @Test func `Tier three promotes the booking deadline instead of a status line`() throws {
        let view = makeView(try alexandria())
        #expect(view.tags == [.advanceBooking])
        #expect(view.statusLineText == nil)
        #expect(view.promotedDeadlineText == view.bookingLineText)
        #expect(view.promotedDeadlineText?.contains("Mar 11") == true)
    }

    @Test func `A closed service shows Closed and an unknown one shows nothing`() throws {
        let closed = makeView(try charlevoix("CC_CC1") { json in
            self.rewriteReferences(&json, "calendars") { $0["endDate"] = "2026-03-01" }
        }, now: instant("2026-03-10T16:00:00Z"))
        #expect(closed.statusLineText == Strings.onDemandStatusClosed)

        let unknown = makeView(try alexandriaWithUnknownTimeZone())
        #expect(unknown.statusLineText == nil)
        #expect(unknown.promotedDeadlineText == nil)
        #expect(unknown.tags.isEmpty)
    }

    // MARK: - Location row (item 3)

    @Test func `Location row copy follows the probe source and side`() throws {
        let service = try charlevoix("CC_CC1")
        func text(_ source: ProbeSource, inside: Bool, locality: String? = nil) -> (String?, String?) {
            let view = makeView(service, locationCheck: OnDemandLocationCheck(source: source, isInside: inside, locality: locality, coordinate: charlevoixPoint))
            return (view.locationRowText, view.locationRowSubtext)
        }
        #expect(text(.rider, inside: true, locality: "Boyne City") == (Strings.onDemandDetailLocationInside, "Pickups available in Boyne City"))
        #expect(text(.rider, inside: false, locality: "Boyne City") == (Strings.onDemandDetailLocationOutside, nil))
        #expect(text(.mapCenter, inside: true) == (Strings.onDemandDetailCenterInside, nil))
        #expect(text(.mapCenter, inside: false) == (Strings.onDemandDetailCenterOutside, nil))
        #expect(text(.point(label: nil), inside: true) == (Strings.onDemandDetailPointInside, nil))
        #expect(text(.point(label: nil), inside: false) == (Strings.onDemandDetailPointOutside, nil))
        #expect(makeView(service).locationRowText == nil, "no probe, no row")
    }

    // MARK: - Where (item 5)

    @Test func `Where appears only for zone-to-zone or multi-area services`() throws {
        #expect(makeView(try charlevoix("CC_CC1")).whereRows == nil)

        let medical = makeView(try charlevoix("CC_CC2_med"), locationCheck: OnDemandLocationCheck(source: .rider, isInside: true, locality: nil, coordinate: charlevoixPoint))
        let rows = try #require(medical.whereRows)
        #expect(rows.serviceArea == String(format: Strings.onDemandDetailIncludesLocationFormat, OnDemandCopy.zoneCount(3)), "unnamed areas fall back to the count; the rider is inside")
        #expect(rows.dropOff != nil)

        let mapCentre = makeView(try charlevoix("CC_CC2_med"), locationCheck: OnDemandLocationCheck(source: .mapCenter, isInside: true, locality: nil, coordinate: charlevoixPoint))
        #expect(mapCentre.whereRows?.serviceArea == OnDemandCopy.zoneCount(3), "only the rider source says includes your location")
    }

    // MARK: - When (item 6)

    @Test func `When merges rules with equal hours into weekday ranges`() throws {
        // Split CC1 into a Mon–Fri rule and a Sat rule with the same hours.
        let split = try charlevoix("CC_CC1") { json in
            var body = json["data"] as! [String: Any]
            body["list"] = (body["list"] as! [[String: Any]]).map { service in
                guard service["id"] as? String == "CC_CC1" else { return service }
                var service = service
                var weekdays = (service["rules"] as! [[String: Any]])[0]
                var saturday = weekdays
                weekdays["calendarIds"] = ["CC_mon-tues-wed-thurs-fri"]
                saturday["calendarIds"] = ["CC_sat"]
                service["rules"] = [weekdays, saturday]
                return service
            }
            json["data"] = body
        }
        let view = makeView(split)
        #expect(view.whenRows.count == 1)
        #expect(view.whenRows[0].days == "Mon–Sat")
        #expect(view.whenRows[0].hours?.contains("7:20") == true)
    }

    @Test func `Weekdays without service get a No service row`() throws {
        #expect(makeView(try charlevoix("CC_CC1")).noServiceDays == "Sun")
        let weekdaysOnly = try charlevoix("CC_CC1") { json in
            self.rewriteRules(&json) { $0["calendarIds"] = ["CC_mon-tues-wed-thurs-fri"] }
        }
        #expect(makeView(weekdaysOnly).noServiceDays == "Sat–Sun")
        #expect(makeView(try charlevoix("CC_CC3")).noServiceDays == nil, "seven-day service")
    }

    // MARK: - How to book (item 7)

    @Test func `More information is hidden when it equals the service url`() throws {
        #expect(makeView(try alexandria()).infoURL == URL(string: "https://www.alexandriava.gov/Paratransit"))
        let sameURL = try alexandriaWithURL("https://www.alexandriava.gov/Paratransit")
        #expect(makeView(sameURL).infoURL == nil)
        #expect(makeView(sameURL).service.url == URL(string: "https://www.alexandriava.gov/Paratransit"), "the agency website row still shows it")
    }

    private func alexandriaWithURL(_ url: String) throws -> OnDemandService {
        let data = Fixtures.loadData(file: "ondemand_service_alexandria.json")
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var body = try #require(json["data"] as? [String: Any])
        var entry = try #require(body["entry"] as? [String: Any])
        entry["url"] = url
        body["entry"] = entry
        json["data"] = body
        return try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<OnDemandService>.self, from: JSONSerialization.data(withJSONObject: json)).entry
    }

    private func rewriteReferences(_ json: inout [String: Any], _ key: String, _ transform: (inout [String: Any]) -> Void) {
        var body = json["data"] as! [String: Any]
        var references = body["references"] as! [String: Any]
        references[key] = (references[key] as! [[String: Any]]).map { element in
            var element = element
            transform(&element)
            return element
        }
        body["references"] = references
        json["data"] = body
    }

    private func rewriteRules(_ json: inout [String: Any], _ transform: (inout [String: Any]) -> Void) {
        var body = json["data"] as! [String: Any]
        body["list"] = (body["list"] as! [[String: Any]]).map { service in
            var service = service
            service["rules"] = (service["rules"] as! [[String: Any]]).map { rule in
                var rule = rule
                transform(&rule)
                return rule
            }
            return service
        }
        json["data"] = body
    }

    @Test func `Footnotes show every booking message verbatim`() throws {
        let view = makeView(try alexandria())
        #expect(view.footnotes.count == 1)
        #expect(view.footnotes[0].hasPrefix("DOT is the City of Alexandria's paratransit program"))
    }

    @Test func `Hosting controller carries the location check into the view`() throws {
        let dataLoader = MockDataLoader(testName: name)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        let application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
        let check = OnDemandLocationCheck(source: .rider, isInside: true, locality: "Boyne City", coordinate: charlevoixPoint)
        let controller = OnDemandServiceViewController(application: application, service: try charlevoix("CC_CC1"), locationCheck: check, now: { self.instant("2026-03-10T16:00:00Z") })
        #expect(controller.rootView.locationRowText == Strings.onDemandDetailLocationInside)
        #expect(normalizeSpaces(controller.rootView.statusLineText) == "Open now · until 4:40 PM")
    }

    // MARK: - Dismissal (spec 2.3, ruling F15)

    /// Appearance callbacks only run in a window with a real scene.
    private func withSceneWindow(_ root: UIViewController, _ body: () async throws -> Void) async throws {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = try #require(scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first, "No UIWindowScene in the test host.")
        let window = UIWindow(windowScene: scene)
        window.rootViewController = root
        window.isHidden = false
        defer {
            root.presentedViewController?.dismiss(animated: false)
            window.rootViewController = nil
            window.isHidden = true
        }
        try await body()
    }

    private func makeDetail(countingDismissalsIn counter: SendableBox<Int>) throws -> OnDemandServiceViewController {
        let dataLoader = MockDataLoader(testName: name)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        let application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
        let detail = OnDemandServiceViewController(application: application, service: try alexandria())
        detail.onDismiss = { counter.value += 1 }
        return detail
    }

    @Test func `Popping the page reports its dismissal, covering it does not`() async throws {
        let dismissals = SendableBox(0)
        let detail = try makeDetail(countingDismissalsIn: dismissals)
        let navigation = UINavigationController(rootViewController: UIViewController())
        try await withSceneWindow(navigation) {
            navigation.pushViewController(detail, animated: false)
            await poll(until: { detail.viewIfLoaded?.window != nil }, "the detail appears")
            let cover = UIViewController()
            navigation.pushViewController(cover, animated: false)
            await poll(until: { detail.viewIfLoaded?.window == nil }, "the cover hides the detail")
            navigation.popViewController(animated: false)
            await poll(until: { detail.viewIfLoaded?.window != nil }, "the detail reappears")
            #expect(dismissals.value == 0, "a page pushed over the detail and popped back keeps the highlight")

            navigation.popViewController(animated: false)
            await poll(until: { dismissals.value > 0 }, "popping reports the dismissal")
            #expect(dismissals.value == 1)
        }
    }

    @Test func `Dismissing the presented page reports its dismissal`() async throws {
        let dismissals = SendableBox(0)
        let detail = try makeDetail(countingDismissalsIn: dismissals)
        let host = UIViewController()
        try await withSceneWindow(host) {
            host.present(detail, animated: false)
            await poll(until: { detail.viewIfLoaded?.window != nil && !detail.isBeingPresented }, "the detail is presented")
            #expect(dismissals.value == 0)

            detail.dismiss(animated: false)
            await poll(until: { dismissals.value > 0 }, "dismissing reports the dismissal")
            #expect(dismissals.value == 1)
        }
    }
}

// swiftlint:enable force_cast
