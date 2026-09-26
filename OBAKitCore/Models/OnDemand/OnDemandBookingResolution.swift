//
//  OnDemandBookingResolution.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// The service-wide booking outcome as instants: what `OnDemandServiceSummary`
/// formats into its booking line and what `OnDemandAvailability` turns into a
/// status. One walk over each rule's service days answers both.
public enum OnDemandBookingResolution: Equatable, Sendable {
    /// The earliest bookable date and its cutoff.
    case bookBy(cutoff: Date, travelDate: ServiceDate)
    /// No date is bookable yet; booking for the first not-yet-open date opens then.
    case opensAt(Date)
    /// The next bookable date's rule has no pickup booking rule.
    case noNoticeRequired
    /// Every remaining date's deadline has passed (or the calendars ended).
    case closed
    /// A missing field or an unresolved booking rule (spec §6.2).
    case unknown

    public struct Outcome: Equatable, Sendable {
        public let resolution: OnDemandBookingResolution
        /// The earliest cutoff or opening instant after `now`, or nil.
        public let nextChangeInstant: Date?

        public init(resolution: OnDemandBookingResolution, nextChangeInstant: Date?) {
            self.resolution = resolution
            self.nextChangeInstant = nextChangeInstant
        }
    }

    private struct Candidate {
        let travelDate: ServiceDate
        let evaluation: BookingEvaluation
    }

    /// One rule's contribution: a bookable candidate, a still-closed date's
    /// open instant, a rule this build can't evaluate, an unresolved
    /// `pickupBookingRuleID` (which collapses the whole outcome to
    /// `.unknown`), or nothing worth surfacing.
    private enum RuleOutcome {
        case unresolvedBookingRule
        case bookable(Candidate)
        case notYetOpen(Date)
        case unknown
        case settled
    }

    public static func resolve(service: OnDemandService, evaluator: BookingDeadlineEvaluator, now: Date) -> Outcome {
        guard !service.rules.isEmpty else { return Outcome(resolution: .unknown, nextChangeInstant: nil) }

        var bookable: [Candidate] = []
        var notYetOpen: [Date] = []
        var sawUnknown = false

        for rule in service.rules {
            switch outcome(for: rule, service: service, evaluator: evaluator, now: now) {
            case .unresolvedBookingRule:
                return Outcome(resolution: .unknown, nextChangeInstant: nil)
            case .bookable(let candidate):
                bookable.append(candidate)
            case .notYetOpen(let open):
                notYetOpen.append(open)
            case .unknown:
                sawUnknown = true
            case .settled:
                break
            }
        }

        let resolution = resolved(bookable: bookable, notYetOpen: notYetOpen, sawUnknown: sawUnknown)
        let boundaries = bookable.compactMap(\.evaluation.cutoffInstant) + notYetOpen
        return Outcome(resolution: resolution, nextChangeInstant: boundaries.filter { $0 > now }.min())
    }

    /// The single rule's outcome as of `now`: its own next bookable date if it
    /// has one, otherwise the first date whose booking is still to open,
    /// otherwise whether any remaining date can't be evaluated.
    private static func outcome(for rule: AvailabilityRule, service: OnDemandService, evaluator: BookingDeadlineEvaluator, now: Date) -> RuleOutcome {
        let bookingRule = service.bookingRule(id: rule.pickupBookingRuleID)
        // Referenced but missing is not "no notice": nothing can be promised.
        if rule.pickupBookingRuleID != nil, bookingRule == nil {
            return .unresolvedBookingRule
        }
        // No usable calendar means no dates to walk; that is unknown, not
        // closed (spec §6.3).
        guard evaluator.hasUsableCalendar(rule) else { return .unknown }

        var bookable: Candidate?
        var firstOpenInstant: Date?
        var sawUnknown = false
        evaluator.walkServiceDates(rule: rule, bookingRule: bookingRule, now: now) { date, evaluation in
            switch evaluation.state {
            case .open:
                bookable = Candidate(travelDate: date, evaluation: evaluation)
                return false
            case .notYetOpen:
                firstOpenInstant = firstOpenInstant ?? evaluation.openInstant
            case .unknown:
                sawUnknown = true
            case .closedForDate:
                break
            }
            return true
        }

        if let bookable { return .bookable(bookable) }
        if let firstOpenInstant { return .notYetOpen(firstOpenInstant) }
        return sawUnknown ? .unknown : .settled
    }

    /// The earliest bookable candidate wins outright (same date: the earliest
    /// cutoff); otherwise the earliest not-yet-open date; otherwise unknown if
    /// any rule couldn't be evaluated, else closed.
    private static func resolved(bookable: [Candidate], notYetOpen: [Date], sawUnknown: Bool) -> OnDemandBookingResolution {
        if let best = bookable.min(by: { lhs, rhs in
            if lhs.travelDate != rhs.travelDate { return lhs.travelDate < rhs.travelDate }
            return (lhs.evaluation.cutoffInstant ?? .distantFuture) < (rhs.evaluation.cutoffInstant ?? .distantFuture)
        }) {
            guard let cutoff = best.evaluation.cutoffInstant else { return .noNoticeRequired }
            return .bookBy(cutoff: cutoff, travelDate: best.travelDate)
        }
        if let earliestOpen = notYetOpen.min() {
            return .opensAt(earliestOpen)
        }
        return sawUnknown ? .unknown : .closed
    }
}
