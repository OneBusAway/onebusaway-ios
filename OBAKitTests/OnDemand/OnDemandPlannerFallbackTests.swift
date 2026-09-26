//
//  OnDemandPlannerFallbackTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import OTPKit
import SwiftUI
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

/// Spec 3.8: which services qualify, and where the endpoints come from.
@MainActor
@Suite(.serialized)
final class OnDemandPlannerFallbackTests: OBATestCase {

    private let now = ISO8601DateFormatter().date(from: "2026-03-10T16:00:00Z")!
    private let origin = CLLocationCoordinate2D(latitude: 45.3, longitude: -85.2)
    private let destination = CLLocationCoordinate2D(latitude: 45.0, longitude: -84.7)

    /// A point-mode response for one service with the given rules, where the
    /// areas in `insideAreaIDs` contain the point (distance 0) and the rest are 400 m away.
    private func match(
        serviceID: String,
        rules: [(from: [String], to: [String])],
        areaIDs: [String],
        insideAreaIDs: Set<String>,
        eligibility: [String: Any]? = nil,
        phone: String? = "(231) 582-6900"
    ) throws -> OnDemandServiceMatch {
        var service: [String: Any] = [
            "id": serviceID, "agencyId": "CC", "routeId": serviceID, "name": "Service \(serviceID)", "serviceKind": "zoneToZone",
            "description": NSNull(), "url": NSNull(),
            "rules": rules.map { rule -> [String: Any] in
                ["fromIds": rule.from, "toIds": rule.to, "startPickupTime": "07:20:00", "endPickupTime": "16:40:00", "endDropOffTime": NSNull(),
                 "calendarIds": ["CC_all"], "pickupType": 2, "dropOffType": 2, "pickupBookingRuleId": "CC_rule", "dropOffBookingRuleId": "CC_rule",
                 "safeDurationFactor": NSNull(), "safeDurationOffset": NSNull()]
            },
            "matchReason": insideAreaIDs.isEmpty ? "areaNearby" : "areaContainsPoint"
        ]
        if let eligibility { service["eligibility"] = eligibility }
        let json: [String: Any] = ["code": 200, "currentTime": 0, "text": "OK", "version": 2, "data": [
            "limitExceeded": false, "outOfRange": false, "list": [service],
            "references": [
                "agencies": [["id": "CC", "name": "CC", "url": "https://example.com", "timezone": "America/Detroit", "lang": "en", "phone": "", "privateService": false]],
                "routes": [], "situations": [], "stopTimes": [], "stops": [], "trips": [], "locationGroups": [],
                "serviceAreas": areaIDs.map { id -> [String: Any] in
                    ["id": id, "name": NSNull(), "description": NSNull(), "bbox": [-85.4, 45.1, -84.7, 45.4],
                     "distanceToArea": insideAreaIDs.contains(id) ? 0 : 400, "nearestPointOnBoundary": insideAreaIDs.contains(id) ? NSNull() : [-85.2, 45.31]]
                },
                "bookingRules": [["id": "CC_rule", "bookingType": 1, "priorNoticeDurationMin": 90, "priorNoticeDurationMax": NSNull(), "priorNoticeLastDay": NSNull(), "priorNoticeLastTime": NSNull(), "priorNoticeStartDay": NSNull(), "priorNoticeStartTime": NSNull(), "priorNoticeCalendarId": NSNull(), "message": NSNull(), "pickupMessage": NSNull(), "dropOffMessage": NSNull(), "phoneNumber": phone ?? NSNull(), "infoUrl": NSNull(), "bookingUrl": NSNull()]],
                "calendars": [["id": "CC_all", "days": ["mon", "tue", "wed", "thu", "fri", "sat", "sun"], "startDate": "2024-01-01", "endDate": "2027-12-31", "exceptedDates": []]]
            ]
        ]]
        let services = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<[OnDemandService]>.self, from: JSONSerialization.data(withJSONObject: json)).list
        return OnDemandServiceMatch.matches(from: services, now: now)[0]
    }

    /// `DateFormatter` inserts a narrow no-break space (U+202F) before AM/PM
    /// on this OS; normalise it so the expectation reads as plain text.
    private func normalized(_ string: String?) -> String? {
        string?.replacingOccurrences(of: "\u{202F}", with: " ")
    }

    private func result(origin: [OnDemandServiceMatch], destination: [OnDemandServiceMatch]) -> OnDemandPlannerResult {
        OnDemandPlannerQualifier.result(origin: origin, destination: destination, originCoordinate: self.origin, destinationCoordinate: self.destination)
    }

    @Test func `A single zone containing both ends qualifies`() throws {
        let zone = [(from: ["A"], to: ["A"])]
        let result = result(
            origin: [try match(serviceID: "Z", rules: zone, areaIDs: ["A"], insideAreaIDs: ["A"])],
            destination: [try match(serviceID: "Z", rules: zone, areaIDs: ["A"], insideAreaIDs: ["A"])]
        )
        #expect(result.qualifying.map(\.id) == ["Z"])
        #expect(result.hiddenCount == 0)
    }

    @Test func `Zone to zone qualifies only in the rule's direction`() throws {
        let aToB = [(from: ["A"], to: ["B"])]
        let originInA = try match(serviceID: "Z", rules: aToB, areaIDs: ["A", "B"], insideAreaIDs: ["A"])
        let destinationInB = try match(serviceID: "Z", rules: aToB, areaIDs: ["A", "B"], insideAreaIDs: ["B"])
        #expect(result(origin: [originInA], destination: [destinationInB]).qualifying.map(\.id) == ["Z"])

        let reversed = result(origin: [destinationInB], destination: [originInA])
        #expect(reversed.qualifying.isEmpty, "only B→A would serve this trip; the rule runs A→B")
        #expect(reversed.hiddenCount == 1)
    }

    @Test func `Eligibility-required services and services covering one end are hidden`() throws {
        let zone = [(from: ["A"], to: ["A"])]
        let certified: [String: Any] = ["requirement": "certificationRequired", "infoUrl": NSNull()]
        let tierFour = result(
            origin: [try match(serviceID: "Z", rules: zone, areaIDs: ["A"], insideAreaIDs: ["A"], eligibility: certified)],
            destination: [try match(serviceID: "Z", rules: zone, areaIDs: ["A"], insideAreaIDs: ["A"], eligibility: certified)]
        )
        #expect(tierFour.qualifying.isEmpty)
        #expect(tierFour.hiddenCount == 1)

        let oneEnd = result(
            origin: [try match(serviceID: "Z", rules: zone, areaIDs: ["A"], insideAreaIDs: ["A"])],
            destination: [try match(serviceID: "Z", rules: zone, areaIDs: ["A"], insideAreaIDs: [])]
        )
        #expect(oneEnd.qualifying.isEmpty)
        #expect(oneEnd.hiddenCount == 1)
        #expect(oneEnd.originInsideMatches.map(\.id) == ["Z"])
    }

    @Test func `A qualifying service without contact details has no pill`() throws {
        let zone = [(from: ["A"], to: ["A"])]
        let match = try match(serviceID: "Z", rules: zone, areaIDs: ["A"], insideAreaIDs: ["A"], phone: nil)
        let card = OnDemandPlannerCardModel(match: match, colors: [:], copy: OnDemandCopy(timeZone: TimeZone(identifier: "America/Detroit")!, locale: Locale(identifier: "en_US"), now: now))
        #expect(card.primary == nil)
        #expect(normalized(card.meta) == "Open · until 4:40 PM · Same-day booking")
    }

    /// Ruling P3/F2: the pill dials the same contact as the card and the detail page.
    @Test func `A qualifying service's pill dials the shared contact`() throws {
        let zone = [(from: ["A"], to: ["A"])]
        let match = try match(serviceID: "Z", rules: zone, areaIDs: ["A"], insideAreaIDs: ["A"])
        let card = OnDemandPlannerCardModel(match: match, colors: [:], copy: OnDemandCopy(timeZone: TimeZone(identifier: "America/Detroit")!, locale: Locale(identifier: "en_US"), now: now))
        #expect(card.primary == .call("(231) 582-6900".telephoneURL!))
    }

    @Test func `Notification endpoints win over the planner's originals`() {
        let userInfo: [AnyHashable: Any] = [
            Notifications.tripPlanEmptyReasonKey: "empty",
            Notifications.tripPlanEmptyOriginLatitudeKey: 45.31, Notifications.tripPlanEmptyOriginLongitudeKey: -85.21,
            Notifications.tripPlanEmptyDestinationLatitudeKey: 45.01, Notifications.tripPlanEmptyDestinationLongitudeKey: -84.71
        ]
        let resolved = TripPlanEmptyEndpoints.resolve(userInfo: userInfo, fallbackOrigin: origin, fallbackDestination: destination)
        #expect(resolved?.origin.latitude == 45.31)
        #expect(resolved?.destination.longitude == -84.71)

        let partial = TripPlanEmptyEndpoints.resolve(userInfo: [Notifications.tripPlanEmptyReasonKey: "error"], fallbackOrigin: origin, fallbackDestination: destination)
        #expect(partial?.origin.latitude == origin.latitude)
        #expect(partial?.destination.latitude == destination.latitude)

        #expect(TripPlanEmptyEndpoints.resolve(userInfo: nil, fallbackOrigin: nil, fallbackDestination: destination) == nil)
    }

    // MARK: - Fitting above the planner (half height)

    private func threeQualifying() throws -> OnDemandPlannerResult {
        let zone = [(from: ["A"], to: ["A"])]
        let ids = ["X", "Y", "Z"]
        return result(
            origin: try ids.map { try match(serviceID: $0, rules: zone, areaIDs: ["A"], insideAreaIDs: ["A"]) },
            destination: try ids.map { try match(serviceID: $0, rules: zone, areaIDs: ["A"], insideAreaIDs: ["A"]) }
        )
    }

    @Test func `The card shows at most two services and leaves the rest to Show all`() throws {
        let result = try threeQualifying()
        #expect(result.qualifying.count == 3)
        #expect(OnDemandPlannerFallbackView.visibleServices(in: result).map(\.id) == ["X", "Y"])
    }

    /// Two cards and the captions outgrow the space between the map
    /// controls and a half-height planner on a phone; the card then scrolls
    /// within the height it is given instead of running under the status bar.
    @Test func `The card scrolls within a height shorter than its content`() throws {
        let result = try threeQualifying()
        let view = OnDemandPlannerFallbackView(
            result: result,
            copy: OnDemandCopy(timeZone: TimeZone(identifier: "America/Detroit")!, locale: Locale(identifier: "en_US"), now: now),
            colors: [:],
            actions: .none
        )
        let host = UIHostingController(rootView: view)
        let natural = host.sizeThatFits(in: CGSize(width: 343, height: CGFloat.greatestFiniteMagnitude)).height
        let limit: CGFloat = 220
        #expect(natural > limit, "precondition: two cards need more than \(limit) pt, got \(natural)")

        #expect(host.sizeThatFits(in: CGSize(width: 343, height: limit)).height <= limit)
    }

    @Test func `The planner card's placement stops below its ceiling`() throws {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let controls = UIView()
        let surface = UIView()
        let dock = UIView()
        [controls, surface, dock].forEach(container.addSubview)

        let constraints = OnDemandDockPlacement.compact.constraints(dockView: dock, safeArea: container.safeAreaLayoutGuide, surface: surface, ceiling: controls.bottomAnchor)
        let top = try #require(constraints.first { $0.firstItem === dock && $0.firstAttribute == .top })
        #expect(top.relation == .greaterThanOrEqual)
        #expect(top.secondItem === controls)
        #expect(top.secondAttribute == .bottom)
        #expect(top.constant == OnDemandDockPlacement.gap)

        let uncapped = OnDemandDockPlacement.compact.constraints(dockView: dock, safeArea: container.safeAreaLayoutGuide, surface: surface)
        #expect(!uncapped.contains { $0.firstAttribute == .top })
    }
}
