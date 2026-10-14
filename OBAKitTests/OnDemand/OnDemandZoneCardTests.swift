//
//  OnDemandZoneCardTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast

@MainActor
@Suite(.serialized)
final class OnDemandZoneCardTests: OBATestCase {

    private let now = ISO8601DateFormatter().date(from: "2026-03-10T16:00:00Z")!
    private let detroit = TimeZone(identifier: "America/Detroit")!

    private func charlevoixServices(rewriting transform: ((inout [String: Any]) -> Void)? = nil) throws -> [OnDemandService] {
        let data = Fixtures.loadData(file: "ondemand_services_for_agency_charlevoix.json")
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        transform?(&json)
        return try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<[OnDemandService]>.self, from: JSONSerialization.data(withJSONObject: json)).list
    }

    private func insideMatch(_ service: OnDemandService) -> OnDemandServiceMatch {
        OnDemandServiceMatch(
            service: service,
            matchReason: .areaContainsPoint,
            distanceToArea: 0,
            nearestPointOnBoundary: nil,
            availability: OnDemandAvailability.evaluate(service: service, timeZone: service.timeZone, now: now)
        )
    }

    private var copy: OnDemandCopy { OnDemandCopy(timeZone: detroit, locale: Locale(identifier: "en_US"), now: now) }

    private func colors(_ services: [OnDemandService]) -> [String: UIColor] {
        OnDemandServiceColors.resolvedColors(for: services, brand: ThemeColors.shared.brand)
    }

    /// `DateFormatter` inserts a narrow no-break space (U+202F) before AM/PM
    /// on this OS; normalise it to a plain space so this assertion doesn't
    /// hard-code an ICU formatting detail (see `OnDemandCopyTests`).
    private func normalizeSpaces(_ string: String?) -> String? {
        string?.replacingOccurrences(of: "\u{202F}", with: " ")
    }

    @Test func `Card model for one inside match`() throws {
        let services = try charlevoixServices()
        let dialARide = services.first { $0.id == "CC_CC1" }!
        let model = try #require(OnDemandZoneCardModel(insideMatches: [insideMatch(dialARide)], colors: colors(services), copy: copy))

        #expect(model.eyebrow == Strings.onDemandCardEyebrow)
        #expect(model.title == "Charlevoix County Dial-a-Ride")
        #expect(normalizeSpaces(model.meta) == "Open · until 4:40 PM · Same-day booking")
        #expect(model.moreCount == 0)
        #expect(model.primary == .call("(231) 582-6900".telephoneURL!))
        #expect(model.color == ThemeColors.shared.brand)
    }

    /// Ruling P3: the contact is the first rule that resolves a pickup booking
    /// rule, not the literal first rule, and it dials the summary's URL.
    @Test func `Primary action skips a first rule without a pickup booking rule`() throws {
        let services = try charlevoixServices { json in
            var body = json["data"] as! [String: Any]
            body["list"] = (body["list"] as! [[String: Any]]).map { service in
                guard service["id"] as? String == "CC_CC1" else { return service }
                var service = service
                var rules = service["rules"] as! [[String: Any]]
                var noBooking = rules[0]
                noBooking["pickupBookingRuleId"] = NSNull()
                rules.insert(noBooking, at: 0)
                service["rules"] = rules
                return service
            }
            json["data"] = body
        }
        let dialARide = services.first { $0.id == "CC_CC1" }!
        #expect(dialARide.contactBookingRule?.id == "CC_booking_rule_CC1")
        #expect(OnDemandZoneCardModel.primaryAction(for: dialARide) == .call("(231) 582-6900".telephoneURL!))
    }

    @Test func `Footer counts the other inside matches and the first match is the soonest usable`() throws {
        let services = try charlevoixServices()
        let matches = [services.first { $0.id == "CC_CC4" }!, services.first { $0.id == "CC_CC1" }!, services.first { $0.id == "CC_CC2_med" }!].map(insideMatch)
        let model = try #require(OnDemandZoneCardModel(insideMatches: matches, colors: colors(services), copy: copy))
        #expect(model.moreCount == 2)
        #expect(model.match.id == sortedSoonestUsable(matches)[0].id)
    }

    @Test func `Primary action is the booking URL when there is no phone and nothing when neither exists`() throws {
        let urlOnly = try charlevoixServices { json in
            var body = json["data"] as! [String: Any]
            var references = body["references"] as! [String: Any]
            references["bookingRules"] = (references["bookingRules"] as! [[String: Any]]).map { rule in
                var rule = rule
                rule["phoneNumber"] = nil
                rule["bookingUrl"] = rule["id"] as? String == "CC_booking_rule_CC1" ? "https://book.example.com" : nil
                return rule
            }
            body["references"] = references
            json["data"] = body
        }
        let dialARide = urlOnly.first { $0.id == "CC_CC1" }!
        #expect(OnDemandZoneCardModel.primaryAction(for: dialARide) == .bookOnline(URL(string: "https://book.example.com")!))

        let beaverIsland = urlOnly.first { $0.id == "CC_CC4" }!
        #expect(OnDemandZoneCardModel.primaryAction(for: beaverIsland) == nil)
    }

    @Test func `No card when nothing is inside`() throws {
        let services = try charlevoixServices()
        let nearby = OnDemandServiceMatch(
            service: services[0], matchReason: .areaNearby, distanceToArea: 400, nearestPointOnBoundary: nil,
            availability: OnDemandAvailability.evaluate(service: services[0], timeZone: services[0].timeZone, now: now)
        )
        #expect(OnDemandZoneCardModel(insideMatches: [], colors: colors(services), copy: copy) == nil)
        #expect(OnDemandZoneCardModel(insideMatches: [nearby], colors: colors(services), copy: copy) == nil, "a nearby match is not inside")
    }

    /// The global 44 pt touch-target floor outranks the mock's 40 pt pill
    /// (review ruling): the primary and Details buttons both grow their hit
    /// area to this constant even though the drawn capsule stays smaller.
    @Test func `Buttons meet the 44pt touch target floor`() {
        #expect(OnDemandZoneCardView.minimumTouchTarget == 44)
    }

    // MARK: - Button row sizing

    /// The Details pill collapsed to a 24 pt capsule when the primary pill
    /// took the whole row, which stretched the card to about 320 pt. Both
    /// pills on one line keep the card near its header-plus-row height.
    @Test func `A Call to Book card keeps both pills on one row at phone width`() throws {
        let services = try charlevoixServices()
        let dialARide = try #require(services.first { $0.id == "CC_CC1" })
        let model = try #require(OnDemandZoneCardModel(insideMatches: [insideMatch(dialARide)], colors: colors(services), copy: copy))
        let check = OnDemandLocationCheck(source: .rider, isInside: true, locality: nil, coordinate: CLLocationCoordinate2D(latitude: 45.3, longitude: -85.2))
        let host = UIHostingController(rootView: OnDemandZoneCardView(model: model, locationCheck: check, actions: .none))

        let height = host.sizeThatFits(in: CGSize(width: 343, height: CGFloat.greatestFiniteMagnitude)).height

        #expect(height < 200, "card height \(height)")
    }

    @Test func `The pills share the row one and a half to one`() {
        let split = OnDemandPillRowLayout.widths(available: 311, spacing: 10, primaryMinimum: 130, secondaryMinimum: 80)
        expectClose(Double(split.primary + split.secondary), 301, within: 1e-9)
        expectClose(Double(split.primary / split.secondary), 1.5, within: 1e-9)
    }

    @Test func `Details grows to its one-line width while the primary keeps its own`() {
        let split = OnDemandPillRowLayout.widths(available: 311, spacing: 10, primaryMinimum: 130, secondaryMinimum: 150)
        #expect(split.secondary == 150)
        #expect(split.primary == 151)
    }

    @Test func `When both labels cannot fit on one line the proportion stands`() {
        let split = OnDemandPillRowLayout.widths(available: 261, spacing: 10, primaryMinimum: 200, secondaryMinimum: 150)
        expectClose(Double(split.primary / split.secondary), 1.5, within: 1e-9)
        #expect(split.secondary > 0)
    }
}
