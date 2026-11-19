//
//  OnDemandEligibilityEvaluator.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation

/// High-level evaluation of on-demand booking eligibility for services, trips, and endpoints.
public struct OnDemandEligibilityEvaluator: Sendable {

    /// Evaluates the typed eligibility reason for one on-demand service on a given service date.
    public static func evaluateService(
        service: OnDemandService,
        timeZone: TimeZone?,
        travelDate: ServiceDate? = nil,
        now: Date
    ) -> OnDemandEligibilityReason {
        guard let timeZone else { return .unavailable(.missingTimeZone) }
        if service.eligibility?.requirement == .certificationRequired {
            return .unavailable(.certificationRequired)
        }
        guard !service.rules.isEmpty else { return .unavailable(.noRules) }

        let evaluator = BookingDeadlineEvaluator(timeZone: timeZone, calendars: service.calendars)
        guard service.rules.contains(where: { evaluator.hasUsableCalendar($0) }) else {
            return .unavailable(.unresolvedBookingRule)
        }

        let targetDate = travelDate ?? evaluator.serviceDate(for: now)
        let activeRules = service.rules.filter { rule in
            rule.calendarIDs.contains { evaluator.isActive(calendarID: $0, on: targetDate) }
        }

        guard !activeRules.isEmpty else {
            return inactiveDateReason(service: service, targetDate: targetDate)
        }

        return evaluateActiveRules(activeRules, in: service, evaluator: evaluator, targetDate: targetDate, now: now)
    }

    private static func inactiveDateReason(service: OnDemandService, targetDate: ServiceDate) -> OnDemandEligibilityReason {
        let latestEnd = service.calendars.compactMap(\.endDate).max()
        if let latestEnd, targetDate > latestEnd {
            return .unavailable(.serviceEnded)
        }
        return .unavailable(.noServiceOnDate(targetDate))
    }

    private static func evaluateActiveRules(
        _ activeRules: [AvailabilityRule],
        in service: OnDemandService,
        evaluator: BookingDeadlineEvaluator,
        targetDate: ServiceDate,
        now: Date
    ) -> OnDemandEligibilityReason {
        var openCutoffs: [Date?] = []
        var earlyOpens: [Date] = []
        var lateCutoffs: [Date] = []
        var sawUnknown = false

        for rule in activeRules {
            let bookingRule = service.bookingRule(id: rule.pickupBookingRuleID)
            if rule.pickupBookingRuleID != nil && bookingRule == nil {
                sawUnknown = true
                continue
            }
            let reason = evaluator.evaluateEligibility(rule: rule, bookingRule: bookingRule, travelDate: targetDate, now: now)
            switch reason {
            case .eligible(let cutoff):
                openCutoffs.append(cutoff)
            case .tooEarly(let openInstant):
                earlyOpens.append(openInstant)
            case .tooLate(let cutoffInstant):
                lateCutoffs.append(cutoffInstant)
            case .unavailable:
                sawUnknown = true
            case .outsideZone, .missingEndpoint:
                break
            }
        }

        if !openCutoffs.isEmpty {
            return .eligible(cutoff: openCutoffs.compactMap { $0 }.min())
        }
        if let earliestOpen = earlyOpens.min() {
            return .tooEarly(openInstant: earliestOpen)
        }
        if let latestCutoff = lateCutoffs.max() {
            return .tooLate(cutoffInstant: latestCutoff)
        }
        return sawUnknown ? .unavailable(.unresolvedBookingRule) : .unavailable(.noServiceOnDate(targetDate))
    }

    /// Evaluates eligibility for a proposed trip between origin and destination matches.
    public static func evaluateTrip(
        service: OnDemandService,
        originMatch: OnDemandServiceMatch?,
        destinationMatch: OnDemandServiceMatch?,
        travelDate: ServiceDate? = nil,
        now: Date
    ) -> OnDemandEligibilityReason {
        guard originMatch != nil || destinationMatch != nil else {
            return .missingEndpoint(.both)
        }
        guard let originMatch else {
            return .missingEndpoint(.origin)
        }
        guard let destinationMatch else {
            return .missingEndpoint(.destination)
        }

        guard originMatch.isInside else {
            return .outsideZone(.originOutside)
        }
        guard destinationMatch.isInside else {
            return .outsideZone(.destinationOutside)
        }

        let fromIDs = Set(originMatch.service.areas.filter { $0.distanceToArea == 0 }.map(\.id))
        let toIDs = Set(destinationMatch.service.areas.filter { $0.distanceToArea == 0 }.map(\.id))

        let hasConnectingRule = service.rules.contains { rule in
            !Set(rule.fromIDs).isDisjoint(with: fromIDs) && !Set(rule.toIDs).isDisjoint(with: toIDs)
        }

        guard hasConnectingRule else {
            return .outsideZone(.disconnected)
        }

        return evaluateService(
            service: service,
            timeZone: service.timeZone,
            travelDate: travelDate,
            now: now
        )
    }

    /// Evaluates eligibility for a trip given optional coordinates, zone containment flags, and connectivity.
    public static func evaluateTrip(
        service: OnDemandService,
        originCoordinate: CLLocationCoordinate2D?,
        destinationCoordinate: CLLocationCoordinate2D?,
        originInside: Bool?,
        destinationInside: Bool?,
        connectsZones: Bool = true,
        travelDate: ServiceDate? = nil,
        now: Date
    ) -> OnDemandEligibilityReason {
        guard originCoordinate != nil || destinationCoordinate != nil else {
            return .missingEndpoint(.both)
        }
        guard originCoordinate != nil else {
            return .missingEndpoint(.origin)
        }
        guard destinationCoordinate != nil else {
            return .missingEndpoint(.destination)
        }

        if originInside == false {
            return .outsideZone(.originOutside)
        }
        if destinationInside == false {
            return .outsideZone(.destinationOutside)
        }
        if !connectsZones {
            return .outsideZone(.disconnected)
        }

        return evaluateService(
            service: service,
            timeZone: service.timeZone,
            travelDate: travelDate,
            now: now
        )
    }

    /// Evaluates eligibility for a single probe location (e.g. pickup point check).
    public static func evaluatePoint(
        service: OnDemandService,
        coordinate: CLLocationCoordinate2D?,
        isInside: Bool?,
        travelDate: ServiceDate? = nil,
        now: Date
    ) -> OnDemandEligibilityReason {
        guard coordinate != nil else {
            return .missingEndpoint(.origin)
        }
        if isInside == false {
            return .outsideZone(.pointOutside)
        }

        return evaluateService(
            service: service,
            timeZone: service.timeZone,
            travelDate: travelDate,
            now: now
        )
    }
}
