//
//  OnDemandEligibilityTests.swift
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

@MainActor
@Suite(.serialized)
final class OnDemandEligibilityTests: OBATestCase {

    private let detroit = TimeZone(identifier: "America/Detroit")!
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
    private let now = ISO8601DateFormatter().date(from: "2026-03-10T16:00:00Z")!

    private func instant(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    private func charlevoix(_ id: String, rewriting transform: ((inout [String: Any]) -> Void)? = nil) throws -> OnDemandService {
        let data = Fixtures.loadData(file: "ondemand_services_for_agency_charlevoix.json")
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        transform?(&json)
        let list = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<[OnDemandService]>.self, from: JSONSerialization.data(withJSONObject: json)).list
        return try #require(list.first { $0.id == id })
    }

    private func alexandria(rewriting transform: ((inout [String: Any]) -> Void)? = nil) throws -> OnDemandService {
        let data = Fixtures.loadData(file: "ondemand_service_alexandria.json")
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        transform?(&json)
        return try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<OnDemandService>.self, from: JSONSerialization.data(withJSONObject: json)).entry
    }

    // MARK: - Missing Endpoint Tests

    @Test func `Missing endpoint evaluates missing origin, destination, or both`() throws {
        let service = try charlevoix("CC_CC1")
        let coord = CLLocationCoordinate2D(latitude: 45.3, longitude: -85.2)

        // 1. Both endpoints missing
        let bothMissing = OnDemandEligibilityEvaluator.evaluateTrip(
            service: service,
            originCoordinate: nil,
            destinationCoordinate: nil,
            originInside: nil,
            destinationInside: nil,
            now: now
        )
        #expect(bothMissing == .missingEndpoint(.both))
        #expect(!bothMissing.isEligible)
        #expect(bothMissing.domainExplanation.contains("Missing trip origin and destination"))

        // 2. Origin missing
        let originMissing = OnDemandEligibilityEvaluator.evaluateTrip(
            service: service,
            originCoordinate: nil,
            destinationCoordinate: coord,
            originInside: nil,
            destinationInside: true,
            now: now
        )
        #expect(originMissing == .missingEndpoint(.origin))
        #expect(originMissing.domainExplanation.contains("Missing trip origin"))

        // 3. Destination missing
        let destMissing = OnDemandEligibilityEvaluator.evaluateTrip(
            service: service,
            originCoordinate: coord,
            destinationCoordinate: nil,
            originInside: true,
            destinationInside: nil,
            now: now
        )
        #expect(destMissing == .missingEndpoint(.destination))
        #expect(destMissing.domainExplanation.contains("Missing trip destination"))

        // 4. Point check with missing coordinate
        let pointMissing = OnDemandEligibilityEvaluator.evaluatePoint(
            service: service,
            coordinate: nil,
            isInside: nil,
            now: now
        )
        #expect(pointMissing == .missingEndpoint(.origin))
    }

    // MARK: - Zone Failure Tests

    @Test func `Zone evaluation explains origin outside, destination outside, and disconnected`() throws {
        let service = try charlevoix("CC_CC1")
        let originCoord = CLLocationCoordinate2D(latitude: 45.3, longitude: -85.2)
        let destCoord = CLLocationCoordinate2D(latitude: 45.4, longitude: -85.1)

        // 1. Origin outside zone
        let originOutside = OnDemandEligibilityEvaluator.evaluateTrip(
            service: service,
            originCoordinate: originCoord,
            destinationCoordinate: destCoord,
            originInside: false,
            destinationInside: true,
            now: now
        )
        #expect(originOutside == .outsideZone(.originOutside))
        #expect(!originOutside.isEligible)
        #expect(originOutside.domainExplanation.contains("origin is outside"))

        // 2. Destination outside zone
        let destOutside = OnDemandEligibilityEvaluator.evaluateTrip(
            service: service,
            originCoordinate: originCoord,
            destinationCoordinate: destCoord,
            originInside: true,
            destinationInside: false,
            now: now
        )
        #expect(destOutside == .outsideZone(.destinationOutside))
        #expect(destOutside.domainExplanation.contains("destination is outside"))

        // 3. Disconnected zones
        let disconnected = OnDemandEligibilityEvaluator.evaluateTrip(
            service: service,
            originCoordinate: originCoord,
            destinationCoordinate: destCoord,
            originInside: true,
            destinationInside: true,
            connectsZones: false,
            now: now
        )
        #expect(disconnected == .outsideZone(.disconnected))
        #expect(disconnected.domainExplanation.contains("does not operate between"))

        // 4. Trip timing evaluates only across connecting rules when an unrelated rule is open
        let twoRuleService = try charlevoix("CC_CC1") { json in
            var body = json["data"] as! [String: Any]
            var list = body["list"] as! [[String: Any]]
            var service0 = list[0]
            service0["areas"] = [
                ["id": "zone_a", "name": "Zone A"],
                ["id": "zone_b", "name": "Zone B"],
                ["id": "zone_c", "name": "Zone C"],
                ["id": "zone_d", "name": "Zone D"]
            ]
            service0["rules"] = [
                [
                    "fromIds": ["zone_a"],
                    "toIds": ["zone_b"],
                    "startPickupTime": "08:00:00",
                    "endPickupTime": "12:00:00",
                    "calendarIds": ["cal_weekday"],
                    "pickupType": 2,
                    "dropOffType": 2
                ],
                [
                    "fromIds": ["zone_c"],
                    "toIds": ["zone_d"],
                    "startPickupTime": "08:00:00",
                    "endPickupTime": "18:00:00",
                    "calendarIds": ["cal_weekday"],
                    "pickupType": 2,
                    "dropOffType": 2
                ]
            ]
            list[0] = service0
            body["list"] = list
            json["data"] = body
        }

        let originArea = twoRuleService.areas.first { $0.id == "zone_a" }!
        let destArea = twoRuleService.areas.first { $0.id == "zone_b" }!
        let originAreaMatch = OnDemandAreaMatch(area: originArea, distanceToArea: 0)
        let destAreaMatch = OnDemandAreaMatch(area: destArea, distanceToArea: 0)
        let originMatch = OnDemandServiceMatch(service: twoRuleService, isInside: true, matchedAreas: [originAreaMatch])
        let destMatch = OnDemandServiceMatch(service: twoRuleService, isInside: true, matchedAreas: [destAreaMatch])

        // Travel date is Wednesday 2026-03-11.
        // At 14:00:00, Rule A->B closed at 12:00:00, while Rule C->D is open until 18:00:00.
        let tripTravelDate = ServiceDate("2026-03-11")!
        let timeAfterConnectingRuleEnd = detroit.date(bySettingHour: 14, minute: 0, second: 0, of: tripTravelDate.date(in: detroit)!)!
        let tripReason = OnDemandEligibilityEvaluator.evaluateTrip(
            service: twoRuleService,
            originMatch: originMatch,
            destinationMatch: destMatch,
            travelDate: tripTravelDate,
            now: timeAfterConnectingRuleEnd
        )
        // Must be tooLate based on connecting rule A->B, NOT eligible via unrelated rule C->D
        #expect(!tripReason.isEligible)
        if case .tooLate(let cutoff) = tripReason {
            let expectedCutoff = detroit.date(bySettingHour: 12, minute: 0, second: 0, of: tripTravelDate.date(in: detroit)!)!
            #expect(cutoff == expectedCutoff)
        } else {
            Issue.record("Expected .tooLate for expired connecting rule, got \(tripReason)")
        }

        // 4. Point outside
        let pointOutside = OnDemandEligibilityEvaluator.evaluatePoint(
            service: service,
            coordinate: originCoord,
            isInside: false,
            now: now
        )
        #expect(pointOutside == .outsideZone(.pointOutside))
        #expect(pointOutside.domainExplanation.contains("outside the service area"))
    }

    // MARK: - Timezone & Calendar Tests

    @Test func `Unavailable explains missing timezone, certification, and empty rules`() throws {
        // 1. Missing timezone
        let service = try charlevoix("CC_CC1")
        let tzReason = OnDemandAvailability.evaluateEligibility(service: service, timeZone: nil, now: now)
        #expect(tzReason == .unavailable(.missingTimeZone))

        // 2. Certification required
        let certReq = OnDemandEligibility(requirement: .certificationRequired, infoURL: nil)
        #expect(certReq.requiresCertification)
        let serviceCert = try charlevoix("CC_CC1") { json in
            var list = (json["data"] as! [String: Any])["list"] as! [[String: Any]]
            list[0]["eligibility"] = ["requirement": "certificationRequired", "infoUrl": NSNull()]
            var data = json["data"] as! [String: Any]
            data["list"] = list
            json["data"] = data
        }
        let certReason = OnDemandAvailability.evaluateEligibility(service: serviceCert, timeZone: detroit, now: now)
        #expect(certReason == .unavailable(.certificationRequired))

        // 3. No rules
        let serviceNoRules = try charlevoix("CC_CC1") { json in
            var list = (json["data"] as! [String: Any])["list"] as! [[String: Any]]
            list[0]["rules"] = []
            var data = json["data"] as! [String: Any]
            data["list"] = list
            json["data"] = data
        }
        let noRulesReason = OnDemandAvailability.evaluateEligibility(service: serviceNoRules, timeZone: detroit, now: now)
        #expect(noRulesReason == .unavailable(.noRules))
    }

    // MARK: - Service Date & Cutoff Tests

    @Test func `Cutoff evaluations accurately explain timing states`() throws {
        let service = try charlevoix("CC_CC1")
        let travelDate = ServiceDate("2026-03-10")!

        // Eligible at 12:00 EDT (cutoff is 15:10 EDT / 19:10 UTC)
        let eligibleReason = OnDemandAvailability.evaluateEligibility(
            service: service,
            timeZone: detroit,
            travelDate: travelDate,
            now: instant("2026-03-10T16:00:00Z")
        )
        #expect(eligibleReason == .eligible(cutoff: instant("2026-03-10T19:10:00Z")))
        #expect(eligibleReason.isEligible)

        // Too late at 16:00 EDT (20:00 UTC)
        let lateReason = OnDemandAvailability.evaluateEligibility(
            service: service,
            timeZone: detroit,
            travelDate: travelDate,
            now: instant("2026-03-10T20:00:00Z")
        )
        #expect(lateReason == .tooLate(cutoffInstant: instant("2026-03-10T19:10:00Z")))
        #expect(!lateReason.isEligible)

        // Alexandria too early when booking window has not opened yet
        let alexService = try alexandria { json in
            var body = json["data"] as! [String: Any]
            var references = body["references"] as! [String: Any]
            references["bookingRules"] = (references["bookingRules"] as! [[String: Any]]).map { rule in
                var rule = rule
                rule["priorNoticeStartDay"] = 1
                rule["priorNoticeStartTime"] = "09:00:00"
                return rule
            }
            body["references"] = references
            json["data"] = body
        }
        let advanceTravelDate = ServiceDate("2026-03-16")! // Monday
        // 2 days before: Saturday 2026-03-14 12:00 PDT -> too early
        let alexEarlyNow = instant("2026-03-14T19:00:00Z")
        let alexReason = OnDemandAvailability.evaluateEligibility(
            service: alexService,
            timeZone: losAngeles,
            travelDate: advanceTravelDate,
            now: alexEarlyNow
        )
        if case .tooEarly = alexReason {
            #expect(!alexReason.isEligible)
        } else {
            Issue.record("Expected .tooEarly, got \(alexReason)")
        }
    }

    @Test func `Service date evaluations accurately explain inactive and expired calendars`() throws {
        let service = try charlevoix("CC_CC1")
        let eligibleNow = instant("2026-03-10T16:00:00Z")

        // 1. Inactive weekday (Sunday 2026-03-15)
        let sunday = ServiceDate("2026-03-15")!
        let sundayReason = OnDemandAvailability.evaluateEligibility(
            service: service,
            timeZone: detroit,
            travelDate: sunday,
            now: eligibleNow
        )
        #expect(sundayReason == .unavailable(.noServiceOnDate(sunday)))

        // 2. Ended calendar (2030-01-01)
        let expired = ServiceDate("2030-01-01")!
        let expiredReason = OnDemandAvailability.evaluateEligibility(
            service: service,
            timeZone: detroit,
            travelDate: expired,
            now: eligibleNow
        )
        #expect(expiredReason == .unavailable(.serviceEnded))

        // 3. Unreferenced notice calendar ending later than rule calendars does not postpone serviceEnded
        let serviceWithNoticeCalendar = try charlevoix("CC_CC1") { json in
            var body = json["data"] as! [String: Any]
            var references = body["references"] as! [String: Any]
            var calendars = references["calendars"] as! [[String: Any]]
            calendars = calendars.map { cal in
                var cal = cal
                cal["endDate"] = "2025-12-31"
                return cal
            }
            calendars.append([
                "id": "unreferenced_notice_cal",
                "days": ["mon", "tue", "wed", "thu", "fri"],
                "startDate": "2024-01-01",
                "endDate": "2030-12-31",
                "exceptedDates": []
            ])
            references["calendars"] = calendars
            body["references"] = references
            json["data"] = body
        }
        let dateAfterRuleEnd = ServiceDate("2026-06-01")!
        let ruleExpiredReason = OnDemandAvailability.evaluateEligibility(
            service: serviceWithNoticeCalendar,
            timeZone: detroit,
            travelDate: dateAfterRuleEnd,
            now: eligibleNow
        )
        #expect(ruleExpiredReason == .unavailable(.serviceEnded))
    }

    // MARK: - User-Facing Copy Tests

    @Test func `User facing copy translates typed reasons correctly`() {
        let copy = OnDemandCopy(timeZone: detroit, locale: Locale(identifier: "en_US"), now: now)

        let eligibleNoCutoff = OnDemandEligibilityReason.eligible(cutoff: nil)
        #expect(copy.userFacingExplanation(for: eligibleNoCutoff) == Strings.onDemandEligibilityEligible)

        let eligibleCutoff = OnDemandEligibilityReason.eligible(cutoff: now)
        #expect(copy.userFacingExplanation(for: eligibleCutoff).contains("Eligible to book"))

        let tooEarly = OnDemandEligibilityReason.tooEarly(openInstant: now)
        #expect(copy.userFacingExplanation(for: tooEarly).contains("Booking not open yet"))

        let tooLate = OnDemandEligibilityReason.tooLate(cutoffInstant: now)
        #expect(copy.userFacingExplanation(for: tooLate).contains("Booking deadline passed"))

        let originOut = OnDemandEligibilityReason.outsideZone(.originOutside)
        #expect(copy.userFacingExplanation(for: originOut) == Strings.onDemandEligibilityOutsideZoneOrigin)

        let destOut = OnDemandEligibilityReason.outsideZone(.destinationOutside)
        #expect(copy.userFacingExplanation(for: destOut) == Strings.onDemandEligibilityOutsideZoneDestination)

        let disconn = OnDemandEligibilityReason.outsideZone(.disconnected)
        #expect(copy.userFacingExplanation(for: disconn) == Strings.onDemandEligibilityOutsideZoneDisconnected)

        let pointOut = OnDemandEligibilityReason.outsideZone(.pointOutside)
        #expect(copy.userFacingExplanation(for: pointOut) == Strings.onDemandEligibilityOutsideZonePoint)

        let missOrigin = OnDemandEligibilityReason.missingEndpoint(.origin)
        #expect(copy.userFacingExplanation(for: missOrigin) == Strings.onDemandEligibilityMissingEndpointOrigin)

        let missDest = OnDemandEligibilityReason.missingEndpoint(.destination)
        #expect(copy.userFacingExplanation(for: missDest) == Strings.onDemandEligibilityMissingEndpointDestination)

        let missBoth = OnDemandEligibilityReason.missingEndpoint(.both)
        #expect(copy.userFacingExplanation(for: missBoth) == Strings.onDemandEligibilityMissingEndpointBoth)

        let noTz = OnDemandEligibilityReason.unavailable(.missingTimeZone)
        #expect(copy.userFacingExplanation(for: noTz) == Strings.onDemandEligibilityUnavailableMissingTimeZone)

        let noDate = OnDemandEligibilityReason.unavailable(.noServiceOnDate(ServiceDate("2026-03-15")!))
        #expect(copy.userFacingExplanation(for: noDate) == Strings.onDemandEligibilityUnavailableNoServiceDate)

        let ended = OnDemandEligibilityReason.unavailable(.serviceEnded)
        #expect(copy.userFacingExplanation(for: ended) == Strings.onDemandEligibilityUnavailableServiceEnded)

        let cert = OnDemandEligibilityReason.unavailable(.certificationRequired)
        #expect(copy.userFacingExplanation(for: cert) == Strings.onDemandEligibilityUnavailableCertificationRequired)

        let unres = OnDemandEligibilityReason.unavailable(.unresolvedBookingRule)
        #expect(copy.userFacingExplanation(for: unres) == Strings.onDemandEligibilityUnavailableGeneral)
    }
}
// swiftlint:enable force_cast
