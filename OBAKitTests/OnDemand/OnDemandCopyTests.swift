//
//  OnDemandCopyTests.swift
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
final class OnDemandCopyTests: OBATestCase {

    private let detroit = TimeZone(identifier: "America/Detroit")!
    private let now = ISO8601DateFormatter().date(from: "2026-03-10T16:00:00Z")! // Tue 12:00 EDT

    private func copy(_ locale: String = "en_US") -> OnDemandCopy {
        OnDemandCopy(timeZone: detroit, locale: Locale(identifier: locale), now: now)
    }

    private func instant(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    private func service(id: String = "CC_CC1", name: String = "Dial-a-Ride") throws -> OnDemandService {
        try Fixtures.dictionaryToModel(type: OnDemandService.self, dictionary: [
            "id": id, "agencyId": "CC", "routeId": id, "name": name, "serviceKind": "zone",
            "description": NSNull(), "url": NSNull(), "rules": []
        ])
    }

    private func availability(status: OnDemandStatus, tags: [OnDemandAvailability.Tag] = [.sameDayBooking], tier: Int, booking: OnDemandBookingResolution = .unknown) -> OnDemandAvailability {
        OnDemandAvailability(
            runningNow: false, runningUntil: nil, nextRunStart: nil, bookingTier: nil, bookableNow: false,
            nextBookableServiceDate: nil, status: status, tags: tags, usabilityTier: tier, nextChangeInstant: nil,
            bookingResolution: booking
        )
    }

    private func match(reason: MatchReason, distance: Double?, availability: OnDemandAvailability) throws -> OnDemandServiceMatch {
        OnDemandServiceMatch(service: try service(), matchReason: reason, distanceToArea: distance, nearestPointOnBoundary: nil, availability: availability)
    }

    // MARK: - Distances

    @Test func `Imperial distances use feet below a tenth of a mile and miles above`() {
        #expect(copy().distance(50) == "160 ft")
        #expect(copy().distance(152) == "500 ft")
        #expect(copy().distance(500) == "0.3 mi")
        #expect(copy().distance(6000) == "3.7 mi")
        #expect(copy("en_GB").distance(500) == "0.3 mi", "the UK measures road distance in miles")
    }

    @Test func `Metric distances use metres below a kilometre and kilometres above`() {
        let metric = copy("fr_FR")
        #expect(metric.distance(54) == "50\u{202F}m")
        let roundedUp = metric.distance(996)
        #expect(roundedUp.hasSuffix("m") && !roundedUp.hasSuffix("km") && roundedUp.contains("000"), "996 m rounds to 1 000 m, not 1,0 km: \(roundedUp)")
        let kilometres = metric.distance(1550)
        #expect(kilometres.hasSuffix("km") && kilometres.contains("1,6"), "\(kilometres)")
    }

    // MARK: - Status text

    @Test func `Status text follows the copy catalogue`() {
        let until = instant("2026-03-10T20:40:00Z")
        #expect(copy().statusText(.openNow(until: until), style: .card) == "Open · until 4:40\u{202F}PM")
        #expect(copy().statusText(.openNow(until: until), style: .detail) == "Open now · until 4:40\u{202F}PM")
        #expect(copy().statusText(.openNow(until: nil), style: .card) == "Open")
        let opens = copy().statusText(.opensAt(instant("2026-03-11T11:20:00Z")), style: .card) ?? ""
        #expect(opens.hasPrefix("Opens ") && opens.localizedCaseInsensitiveContains("tomorrow") && opens.contains("7:20"), "\(opens)")
        let bookingOpens = copy().statusText(.bookingOpens(instant("2026-03-11T04:00:00Z")), style: .card) ?? ""
        #expect(bookingOpens.hasPrefix("Booking opens "), "\(bookingOpens)")
        let bookBy = copy().statusText(.bookBy(deadline: instant("2026-03-10T19:10:00Z"), travelDate: ServiceDate(year: 2026, month: 3, day: 10)), style: .card) ?? ""
        #expect(bookBy.hasPrefix("Book by ") && bookBy.contains("3:10"), "\(bookBy)")
        #expect(copy().statusText(.closed, style: .card) == "Closed")
        #expect(copy().statusText(.unknown, style: .card) == nil)
    }

    @Test func `Card meta joins status and booking tag and omits empty segments`() {
        let until = instant("2026-03-10T20:40:00Z")
        #expect(copy().cardMeta(availability(status: .openNow(until: until), tags: [.sameDayBooking], tier: 1)) == "Open · until 4:40\u{202F}PM · Same-day booking")
        #expect(copy().cardMeta(availability(status: .unknown, tags: [.advanceBooking], tier: 5)) == "Advance booking")
        #expect(copy().cardMeta(availability(status: .closed, tags: [], tier: 5)) == "Closed")
        #expect(copy().cardMeta(availability(status: .unknown, tags: [], tier: 5)) == nil)
        #expect(copy().cardMeta(availability(status: .closed, tags: [.sameDayBooking, .eligibilityRequired], tier: 4)) == "Closed · Same-day booking", "the booking tag, not the eligibility tag")
    }

    @Test func `Picker second line lists areas or the zone count then the tag`() {
        let availability = availability(status: .unknown, tags: [.noNoticeNeeded], tier: 5)
        #expect(copy().pickerSecondLine(areaNames: ["Boyne City", "Petoskey"], areaCount: 2, availability: availability) == "Boyne City, Petoskey · No notice needed")
        #expect(copy().pickerSecondLine(areaNames: [], areaCount: 3, availability: availability) == "3 zones · No notice needed")
        #expect(copy().pickerSecondLine(areaNames: [], areaCount: 1, availability: self.availability(status: .unknown, tags: [], tier: 5)) == OnDemandCopy.zoneCount(1), "no tag, no separator")
    }

    // MARK: - Bar title precedence

    @Test func `Bar titles follow the precedence for each state and tier`() throws {
        let inside = { (tier: Int, status: OnDemandStatus, tags: [OnDemandAvailability.Tag]) in
            try self.match(reason: .areaContainsPoint, distance: 0, availability: self.availability(status: status, tags: tags, tier: tier))
        }
        #expect(copy().barTitle(for: try inside(1, .openNow(until: nil), [.sameDayBooking]), edge: nil) == "Pickups available here")
        let opens = copy().barTitle(for: try inside(2, .opensAt(instant("2026-03-10T11:20:00Z")), [.sameDayBooking]), edge: nil) ?? ""
        #expect(opens.hasPrefix("Opens "), "\(opens)")
        let bookBy = copy().barTitle(for: try inside(3, .bookBy(deadline: instant("2026-03-11T19:10:00Z"), travelDate: ServiceDate(year: 2026, month: 3, day: 12)), [.advanceBooking]), edge: nil) ?? ""
        #expect(bookBy.hasPrefix("Book by "), "\(bookBy)")
        #expect(copy().barTitle(for: try inside(3, .closed, [.advanceBooking]), edge: nil) == "Closed")
        #expect(copy().barTitle(for: try inside(4, .openNow(until: nil), [.sameDayBooking, .eligibilityRequired]), edge: nil) == "Eligibility required")
        #expect(copy().barTitle(for: try inside(5, .closed, []), edge: nil) == "Closed")
        #expect(copy().barTitle(for: try inside(5, .unknown, []), edge: nil) == nil, "unknown renders no title")
    }

    /// Ruling F1: a tier-3 title comes from the evaluator's booking line, so a
    /// same-day service running past its cutoff (status `.opensAt` tomorrow)
    /// reads "Book by …" when tomorrow is bookable and "Booking opens …" when
    /// booking has not opened yet — never "Opens …".
    @Test func `A tier-three title reads the booking line, not the opening`() throws {
        let opensTomorrow = OnDemandStatus.opensAt(instant("2026-03-11T11:20:00Z"))
        let bookable = try match(reason: .areaContainsPoint, distance: 0, availability: availability(
            status: opensTomorrow, tier: 3,
            booking: .bookBy(cutoff: instant("2026-03-11T19:10:00Z"), travelDate: ServiceDate(year: 2026, month: 3, day: 11))
        ))
        let bookBy = copy().barTitle(for: bookable, edge: nil) ?? ""
        #expect(bookBy.hasPrefix("Book by ") && bookBy.contains("3:10"), "\(bookBy)")

        let notYetOpen = try match(reason: .areaContainsPoint, distance: 0, availability: availability(
            status: opensTomorrow, tier: 3, booking: .opensAt(instant("2026-03-11T04:00:00Z"))
        ))
        let bookingOpens = copy().barTitle(for: notYetOpen, edge: nil) ?? ""
        #expect(bookingOpens.hasPrefix("Booking opens "), "\(bookingOpens)")
    }

    @Test func `Near the edge the title names the walk direction and distance`() throws {
        let match = try match(reason: .areaContainsPoint, distance: 0, availability: availability(status: .openNow(until: nil), tier: 1))
        let edge = OnDemandEdge(distanceMeters: 30, point: CLLocationCoordinate2D(latitude: 45.3, longitude: -85.2), bearingDegrees: 0)
        #expect(copy().barTitle(for: match, edge: edge) == "Inside · edge 100 ft north")
        let farEdge = OnDemandEdge(distanceMeters: 150, point: edge.point, bearingDegrees: 0)
        #expect(copy().barTitle(for: match, edge: farEdge) == "Pickups available here", "100 m or more is not near the edge")
    }

    /// Ruling: a zero-distance edge has no direction to walk, so it reads
    /// plain "inside" rather than naming a direction.
    @Test func `Standing on the boundary reads plain inside, not a direction`() throws {
        let match = try match(reason: .areaContainsPoint, distance: 0, availability: availability(status: .openNow(until: nil), tier: 1))
        let onBoundary = OnDemandEdge(distanceMeters: 0, point: CLLocationCoordinate2D(latitude: 45.3, longitude: -85.2), bearingDegrees: 0)
        #expect(copy().barTitle(for: match, edge: onBoundary) == "Pickups available here")
    }

    @Test func `Outside the title names where the rider stands`() throws {
        let match = try match(reason: .areaNearby, distance: 500, availability: availability(status: .openNow(until: nil), tier: 1))
        let edge = OnDemandEdge(distanceMeters: 500, point: CLLocationCoordinate2D(latitude: 45.3, longitude: -85.2), bearingDegrees: 0)
        #expect(copy().barTitle(for: match, edge: edge) == "0.3 mi south of the zone")
        #expect(copy().barTitle(for: match, edge: nil) == nil, "no edge, no direction, no title")
    }

    @Test func `Every compass point has its own sentence`() {
        for direction in CompassDirection.allCases {
            let inside = Strings.onDemandBarInsideNearEdgeFormat(direction)
            let outside = Strings.onDemandBarOutsideFormat(direction)
            #expect(inside.contains(direction.rawValue), "\(inside)")
            #expect(outside.contains(direction.rawValue), "\(outside)")
            #expect(inside.contains("%@") && outside.contains("%@"))
        }
    }

    // MARK: - Badge and plurals

    @Test func `Badge and plural helpers format counts`() {
        #expect(OnDemandCopy.badge(index: 1, count: 2) == "1 of 2")
        #expect(OnDemandCopy.moreServices(2).contains("2"))
        #expect(OnDemandCopy.pickerTitle(count: 2, nearby: false).contains("2"))
        #expect(OnDemandCopy.pickerTitle(count: 3, nearby: true).contains("3"))
        #expect(OnDemandCopy.addressInsideMore(name: "Dial-a-Ride", extra: 1).contains("Dial-a-Ride"))
    }

    // MARK: - Colours

    @Test func `Colour collisions take the fallback palette in service id order`() throws {
        let colors = OnDemandServiceColors.resolvedColors(
            for: [try service(id: "CC_CC4"), try service(id: "CC_CC1"), try service(id: "CC_CC2")],
            brand: ThemeColors.shared.brand
        )
        #expect(colors["CC_CC1"] == ThemeColors.shared.brand)
        #expect(colors["CC_CC2"] == OnDemandServiceColors.fallbackPalette[0])
        #expect(colors["CC_CC4"] == OnDemandServiceColors.fallbackPalette[1])
    }

    @Test func `Bar text colour clears WCAG contrast when the route has none`() throws {
        let onDark = OnDemandServiceColors.textColor(for: try service(), on: UIColor.black)
        let onLight = OnDemandServiceColors.textColor(for: try service(), on: UIColor.white)
        #expect(onDark == .white)
        #expect(onLight == .black)
    }

    @Test func `Theme carries the on-demand colours`() {
        let theme = ThemeColors(bundle: Bundle(for: OnDemandCopyTests.self))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
        theme.brandAccent.getRed(&red, green: &green, blue: &blue, alpha: nil)
        #expect(abs(red - 0x48 / 255.0) < 0.01 && abs(green - 0x66 / 255.0) < 0.01 && abs(blue - 0x21 / 255.0) < 0.01)
        theme.onDemandOutside.getRed(&red, green: &green, blue: &blue, alpha: nil)
        #expect(abs(red - 0x63 / 255.0) < 0.01 && abs(blue - 0x66 / 255.0) < 0.01)
        theme.onDemandOpenGreen.getRed(&red, green: &green, blue: &blue, alpha: nil)
        #expect(abs(green - 0x8a / 255.0) < 0.01)
    }
}
