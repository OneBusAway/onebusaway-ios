//
//  OnDemandDockBarTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class OnDemandDockBarTests: OBATestCase {

    private let now = ISO8601DateFormatter().date(from: "2026-03-10T16:00:00Z")!
    private let detroit = TimeZone(identifier: "America/Detroit")!
    private let probe = CLLocationCoordinate2D(latitude: 45.3, longitude: -85.2)

    private func charlevoix() throws -> [OnDemandService] {
        try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<[OnDemandService]>.self, from: Fixtures.loadData(file: "ondemand_services_for_agency_charlevoix.json")).list
    }

    private func match(_ service: OnDemandService, reason: MatchReason = .areaContainsPoint, distance: Double? = 0, point: CLLocationCoordinate2D? = nil) -> OnDemandServiceMatch {
        OnDemandServiceMatch(
            service: service, matchReason: reason, distanceToArea: distance, nearestPointOnBoundary: point,
            availability: OnDemandAvailability.evaluate(service: service, timeZone: service.timeZone, now: now)
        )
    }

    private var copy: OnDemandCopy { OnDemandCopy(timeZone: detroit, locale: Locale(identifier: "en_US"), now: now) }

    private func model(_ matches: [OnDemandServiceMatch], edges: [String: OnDemandEdge] = [:], fullAreas: [String: [ServiceArea]] = [:], failed: Set<String> = []) throws -> OnDemandDockBarModel {
        let services = try charlevoix()
        return OnDemandDockBarModel(
            matches: matches, probePoint: probe, edges: edges, fullAreas: fullAreas, failedGeometry: failed,
            colors: OnDemandServiceColors.resolvedColors(for: services, brand: ThemeColors.shared.brand), copy: copy
        )
    }

    @Test func `Inside page: service name eyebrow, precedence title, phone trailing`() throws {
        let dialARide = try charlevoix().first { $0.id == "CC_CC1" }!
        let page = try model([match(dialARide)]).pages[0]
        #expect(page.eyebrow == "Charlevoix County Dial-a-Ride")
        #expect(page.title == "Pickups available here")
        #expect(page.trailing == .call("(231) 582-6900".telephoneURL!))
        #expect(page.trailingSystemImage == "phone.fill")
        #expect(page.trailingAccessibilityLabel == String(format: Strings.onDemandBarCallFormat, "Charlevoix County Dial-a-Ride"))
        #expect(page.backgroundColor == ThemeColors.shared.brand)
        #expect(page.textColor == .black, "brand #78AA36: black reaches 7.6:1, white only 2.8:1 (spec 5 WCAG rule)")
    }

    @Test func `Near the edge the title moves in place when geometry arrives`() throws {
        let dialARide = try charlevoix().first { $0.id == "CC_CC1" }!
        let plain = try model([match(dialARide)]).pages[0]
        #expect(plain.title == "Pickups available here")
        let edge = OnDemandEdge(distanceMeters: 40, point: probe, bearingDegrees: 0)
        let near = try model([match(dialARide)], edges: ["CC_CC1": edge]).pages[0]
        #expect(near.title == "Inside · edge 130 ft north")
    }

    @Test func `Outside page is gray with a chevron that pans to the boundary`() throws {
        let dialARide = try charlevoix().first { $0.id == "CC_CC1" }!
        let boundary = CLLocationCoordinate2D(latitude: 45.31, longitude: -85.2)
        let edge = OnDemandGeometry.edge(from: probe, toServerPoint: boundary, distanceMeters: 500)
        let page = try model([match(dialARide, reason: .areaNearby, distance: 500, point: boundary)], edges: ["CC_CC1": edge]).pages[0]
        #expect(page.title == "0.3 mi south of the zone")
        #expect(page.backgroundColor == ThemeColors.shared.onDemandOutside)
        #expect(page.textColor == .white)
        #expect(page.trailing == .panToEdge(boundary))
        #expect(page.trailingAccessibilityLabel == Strings.onDemandBarShowEdge)
    }

    @Test func `Outside with no boundary point hides the chevron and moves the name to the title`() throws {
        let dialARide = try charlevoix().first { $0.id == "CC_CC1" }!
        let page = try model([match(dialARide, reason: .areaNearby, distance: 500, point: nil)]).pages[0]
        #expect(page.trailing == .none)
        #expect(page.eyebrow == nil)
        #expect(page.title == "Charlevoix County Dial-a-Ride")
    }

    @Test func `Inside without contact details the chevron opens the detail`() throws {
        let beaverIsland = try charlevoix().first { $0.id == "CC_CC4" }!
        let page = try model([match(beaverIsland)]).pages[0]
        #expect(page.trailing == .detail)
        #expect(page.trailingAccessibilityLabel == Strings.onDemandCardDetails)
        #expect(page.trailingSystemImage == "chevron.right")
    }

    @Test func `Pages follow the sort and the badge shows only for more than one page`() throws {
        let services = try charlevoix()
        let matches = [services.first { $0.id == "CC_CC4" }!, services.first { $0.id == "CC_CC1" }!].map { match($0) }
        let model = try model(matches)
        #expect(model.pages.map(\.id) == sortedSoonestUsable(matches).map(\.id))
        #expect(model.showsBadge)
        #expect(model.badge(forPageAt: 1) == "2 of 2")
        #expect(!(try self.model([matches[0]]).showsBadge))
    }

    @Test func `Thumbnail rings appear only once every page's geometry has loaded`() throws {
        let services = try charlevoix()
        let dialARide = services.first { $0.id == "CC_CC1" }!
        let beaverIsland = services.first { $0.id == "CC_CC4" }!
        let matches = [match(dialARide), match(beaverIsland)]
        let areas = Dictionary(uniqueKeysWithValues: services.map { ($0.id, $0.areas) })

        #expect(try model(matches).thumbnailRings == nil, "placeholder before geometry")
        #expect(try model(matches, fullAreas: ["CC_CC1": areas["CC_CC1"]!]).thumbnailRings == nil, "one page still loading")
        let loaded = try model(matches, fullAreas: ["CC_CC1": areas["CC_CC1"]!, "CC_CC4": areas["CC_CC4"]!])
        #expect((loaded.thumbnailRings?.count ?? 0) == 2)
        #expect(try model(matches, fullAreas: ["CC_CC1": areas["CC_CC1"]!, "CC_CC4": areas["CC_CC4"]!], failed: ["CC_CC4"]).thumbnailRings == nil, "a failed fetch keeps the placeholder")
    }

    @Test func `Thumbnail projection keeps every vertex and the probe point inside the square`() {
        let ring = OnDemandThumbnailRing(points: [
            CLLocationCoordinate2D(latitude: 45.0, longitude: -85.5),
            CLLocationCoordinate2D(latitude: 45.0, longitude: -85.0),
            CLLocationCoordinate2D(latitude: 45.4, longitude: -85.0),
            CLLocationCoordinate2D(latitude: 45.4, longitude: -85.5)
        ], color: .red)
        let projection = OnDemandThumbnailProjection(rings: [ring], probePoint: CLLocationCoordinate2D(latitude: 45.5, longitude: -85.9), side: 56, inset: 4)
        for coordinate in ring.points + [CLLocationCoordinate2D(latitude: 45.5, longitude: -85.9)] {
            let point = projection.point(coordinate)
            #expect(point.x >= 4 && point.x <= 52, "\(point)")
            #expect(point.y >= 4 && point.y <= 52, "\(point)")
        }
        #expect(projection.centre == CGPoint(x: 28, y: 28))
        #expect(projection.point(CLLocationCoordinate2D(latitude: 45.5, longitude: -85.9)) == projection.centre, "centred on the probe point")
    }

    @Test func `The bar's accessibility label joins the eyebrow and the title`() throws {
        let dialARide = try charlevoix().first { $0.id == "CC_CC1" }!
        #expect(try model([match(dialARide)]).accessibilityLabel(forPageAt: 0) == "Charlevoix County Dial-a-Ride, Pickups available here")
        let nameOnly = try model([match(dialARide, reason: .areaNearby, distance: 500, point: nil)])
        #expect(nameOnly.accessibilityLabel(forPageAt: 0) == "Charlevoix County Dial-a-Ride", "no eyebrow: the name alone")
    }
}
