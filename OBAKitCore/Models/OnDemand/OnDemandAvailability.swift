//
//  OnDemandAvailability.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// What a rider can do with a service right now (spec 2.5): its rider-facing
/// status, chosen in a fixed order.
public enum OnDemandStatus: Equatable, Sendable {
    /// Running and bookable now; `until` is nil for a continuous service.
    case openNow(until: Date?)
    /// The service starts running at this instant.
    case opensAt(Date)
    /// The booking window (not the service) opens at this instant.
    case bookingOpens(Date)
    case bookBy(deadline: Date, travelDate: ServiceDate)
    case closed
    case unknown
}

/// Hours, booking tier, status, tags and sort tier for one service at `now`,
/// in the agency's time zone (spec 2.5, 2.6). A pure value: surfaces render
/// it and never re-derive any field.
public struct OnDemandAvailability: Equatable, Sendable {

    public enum BookingTier: Int, Comparable, Sendable {
        case realTime = 0
        case sameDay = 1
        case advance = 2

        public static func < (lhs: BookingTier, rhs: BookingTier) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public enum Tag: Equatable, Sendable {
        case noNoticeNeeded
        case sameDayBooking
        case advanceBooking
        case eligibilityRequired
    }

    public static let openNowTier = 1
    public static let sameDayTier = 2
    public static let advanceTier = 3
    public static let eligibilityTier = 4
    public static let unknownTier = 5

    /// How far ahead the next run start and booking tier look, in days.
    static let lookaheadDays = 400

    public let runningNow: Bool
    public let runningUntil: Date?
    public let nextRunStart: Date?
    public let bookingTier: BookingTier?
    public let bookableNow: Bool
    public let nextBookableServiceDate: ServiceDate?
    public let status: OnDemandStatus
    public let tags: [Tag]
    public let usabilityTier: Int
    public let nextChangeInstant: Date?
    /// The evaluator's booking line (the summary's resolution). The bar's
    /// tier-3 title reads it: `book_by` for `.bookBy`, `booking_opens` for
    /// `.opensAt` (spec 2.8 with ruling F1).
    public let bookingResolution: OnDemandBookingResolution

    public init(
        runningNow: Bool,
        runningUntil: Date?,
        nextRunStart: Date?,
        bookingTier: BookingTier?,
        bookableNow: Bool,
        nextBookableServiceDate: ServiceDate?,
        status: OnDemandStatus,
        tags: [Tag],
        usabilityTier: Int,
        nextChangeInstant: Date?,
        bookingResolution: OnDemandBookingResolution = .unknown
    ) {
        self.runningNow = runningNow
        self.runningUntil = runningUntil
        self.nextRunStart = nextRunStart
        self.bookingTier = bookingTier
        self.bookableNow = bookableNow
        self.nextBookableServiceDate = nextBookableServiceDate
        self.status = status
        self.tags = tags
        self.usabilityTier = usabilityTier
        self.nextChangeInstant = nextChangeInstant
        self.bookingResolution = bookingResolution
    }

    /// Every field null or false: the agency time zone is unknown.
    public static let unknown = OnDemandAvailability(
        runningNow: false, runningUntil: nil, nextRunStart: nil, bookingTier: nil, bookableNow: false,
        nextBookableServiceDate: nil, status: .unknown, tags: [], usabilityTier: unknownTier, nextChangeInstant: nil
    )

    // MARK: - Evaluation

    /// A rule's pickup window on one service date.
    private struct Window {
        let rule: AvailabilityRule
        let date: ServiceDate
        let start: Date
        let end: Date
    }

    public static func evaluate(service: OnDemandService, timeZone: TimeZone?, now: Date) -> OnDemandAvailability {
        guard let timeZone else { return .unknown }
        let evaluator = BookingDeadlineEvaluator(timeZone: timeZone, calendars: service.calendars)
        let today = evaluator.serviceDate(for: now)
        let yesterday = evaluator.adding(days: -1, to: today)

        // Windows pass 24:00, so the previous service day is checked too.
        let containing = windows(of: service, on: [yesterday, today], evaluator: evaluator).filter { $0.start <= now && now < $0.end }
        let runningNow = !containing.isEmpty
        let runningUntil = runningNow ? runningUntilInstant(containing, service: service, evaluator: evaluator) : nil
        let nextRunStart = runningNow ? nil : nextWindowStart(after: now, service: service, evaluator: evaluator, today: today)
        let firstActiveDate = firstDateWithService(service: service, evaluator: evaluator, from: today)
        let bookingTier = bookingTier(service: service, evaluator: evaluator, on: firstActiveDate)
        let bookableNow = containing.contains { window in isOpen(rule: window.rule, on: window.date, service: service, evaluator: evaluator, now: now) }
        let nextBookable = service.rules.compactMap { rule -> ServiceDate? in
            let bookingRule = service.bookingRule(id: rule.pickupBookingRuleID)
            if rule.pickupBookingRuleID != nil, bookingRule == nil { return nil }
            return evaluator.nextBookableServiceDate(rule: rule, bookingRule: bookingRule, now: now)
        }.min()
        let outcome = OnDemandBookingResolution.resolve(service: service, evaluator: evaluator, now: now)

        // A rule whose calendars the references do not carry has no service
        // days the evaluator can vouch for: unknown, not closed (spec §6.3).
        let hasUsableCalendar = service.rules.contains { evaluator.hasUsableCalendar($0) }
        // `nextRunStart` stays nil while running (spec 2.5), but a running
        // service past its cutoff still opens again: at the first window
        // after the current one.
        let isRunningPastCutoff = runningNow && !bookableNow
        // The window search after the running window's end must include a
        // window starting exactly there — an adjacent rule can pick up right
        // where the current one's cutoff left off (ruling: don't skip it and
        // report tomorrow instead).
        let nextOpening = isRunningPastCutoff
            ? nextWindowStart(after: runningUntil ?? now, service: service, evaluator: evaluator, today: today, inclusive: true)
            : nextRunStart
        let status = status(
            bookingTier: bookingTier, resolution: outcome.resolution, runningNow: runningNow, bookableNow: bookableNow,
            runningUntil: runningUntil, nextOpening: nextOpening, hasUsableCalendar: hasUsableCalendar, hasServiceDay: firstActiveDate != nil
        )
        let tags = tags(bookingTier: bookingTier, eligibility: service.eligibility)
        // `usabilityTier` depends on `today`, so the agency-zone midnight
        // rollover always counts as a next change, even for a continuous
        // service with no other boundary ahead of it (ruling: spec §2.5).
        let nextMidnight = evaluator.anchor(evaluator.adding(days: 1, to: today))
        let nextChange = [runningUntil, nextRunStart, outcome.nextChangeInstant, nextMidnight].compactMap { $0 }.filter { $0 > now }.min()

        return OnDemandAvailability(
            runningNow: runningNow,
            runningUntil: runningUntil,
            nextRunStart: nextRunStart,
            bookingTier: bookingTier,
            bookableNow: bookableNow,
            nextBookableServiceDate: nextBookable,
            status: status,
            tags: tags,
            usabilityTier: usabilityTier(status: status, tags: tags, nextBookableServiceDate: nextBookable, today: today),
            nextChangeInstant: nextChange,
            bookingResolution: outcome.resolution
        )
    }

    /// Spec 2.6: the first matching line wins.
    public static func usabilityTier(status: OnDemandStatus, tags: [Tag], nextBookableServiceDate: ServiceDate?, today: ServiceDate) -> Int {
        if tags.contains(.eligibilityRequired) { return eligibilityTier }
        if case .openNow = status { return openNowTier }
        switch status {
        case .closed, .unknown:
            return unknownTier
        default:
            break
        }
        guard let nextBookableServiceDate else { return unknownTier }
        return nextBookableServiceDate == today ? sameDayTier : advanceTier
    }

    // MARK: - Windows

    private static func isActive(_ rule: AvailabilityRule, on date: ServiceDate, evaluator: BookingDeadlineEvaluator) -> Bool {
        rule.calendarIDs.contains { evaluator.isActive(calendarID: $0, on: date) }
    }

    private static func window(of rule: AvailabilityRule, on date: ServiceDate, evaluator: BookingDeadlineEvaluator) -> Window {
        // An all-day rule spans true wall-clock midnight to midnight, not
        // `anchor(date) ..< anchor(date) + 24h`: on a DST transition day
        // those two are 23h/25h apart, which would otherwise open a false
        // gap between consecutive all-day windows (ruling: spec §2.5).
        guard rule.startPickupTime == nil, rule.endPickupTime == nil else {
            return Window(
                rule: rule,
                date: date,
                start: evaluator.instant(date, rule.startPickupTime ?? .midnight),
                end: evaluator.instant(date, rule.endPickupTime ?? .endOfServiceDay)
            )
        }
        return Window(
            rule: rule,
            date: date,
            start: startOfDay(date, evaluator: evaluator),
            end: startOfDay(evaluator.adding(days: 1, to: date), evaluator: evaluator)
        )
    }

    /// True wall-clock midnight of `date` in the agency zone — distinct from
    /// `BookingDeadlineEvaluator.anchor`, which is a fixed 12-hour offset from
    /// local noon and so can land off true midnight on a DST transition day.
    private static func startOfDay(_ date: ServiceDate, evaluator: BookingDeadlineEvaluator) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = evaluator.timeZone
        return calendar.startOfDay(for: evaluator.noon(date))
    }

    private static func windows(of service: OnDemandService, on dates: [ServiceDate], evaluator: BookingDeadlineEvaluator) -> [Window] {
        dates.flatMap { date in
            service.rules.filter { isActive($0, on: date, evaluator: evaluator) }.map { window(of: $0, on: date, evaluator: evaluator) }
        }
    }

    /// The latest end among the containing windows — or nil when that end
    /// touches or overlaps the start of a window on the next service day, so
    /// a continuous service reads "Open" rather than "until 12:00 AM".
    private static func runningUntilInstant(_ containing: [Window], service: OnDemandService, evaluator: BookingDeadlineEvaluator) -> Date? {
        guard let latest = containing.max(by: { $0.end < $1.end }) else { return nil }
        let nextDay = evaluator.adding(days: 1, to: latest.date)
        let abuts = windows(of: service, on: [nextDay], evaluator: evaluator).contains { $0.start <= latest.end }
        return abuts ? nil : latest.end
    }

    /// The earliest window start after `now` from `today − 1` through
    /// `today + lookaheadDays`. Stops once a day's anchor is past the best
    /// candidate: no later day can start earlier. `inclusive` widens "after"
    /// to "at or after", so a window starting exactly at `now` — e.g. an
    /// adjacent rule picking up right where the current one's cutoff left
    /// off — is not skipped.
    private static func nextWindowStart(after now: Date, service: OnDemandService, evaluator: BookingDeadlineEvaluator, today: ServiceDate, inclusive: Bool = false) -> Date? {
        var best: Date?
        for offset in -1...lookaheadDays {
            let date = evaluator.adding(days: offset, to: today)
            if let best, evaluator.anchor(date) >= best { break }
            for window in windows(of: service, on: [date], evaluator: evaluator) where inclusive ? window.start >= now : window.start > now {
                best = min(best ?? window.start, window.start)
            }
        }
        return best
    }

    private static func firstDateWithService(service: OnDemandService, evaluator: BookingDeadlineEvaluator, from today: ServiceDate) -> ServiceDate? {
        for offset in 0...lookaheadDays {
            let date = evaluator.adding(days: offset, to: today)
            if service.rules.contains(where: { isActive($0, on: date, evaluator: evaluator) }) {
                return date
            }
        }
        return nil
    }

    // MARK: - Booking

    /// The least demanding pickup booking type among the rules active on the
    /// next date with service. A null id counts as real-time; a dangling id is skipped.
    private static func bookingTier(service: OnDemandService, evaluator: BookingDeadlineEvaluator, on date: ServiceDate?) -> BookingTier? {
        guard let date else { return nil }
        return service.rules
            .filter { isActive($0, on: date, evaluator: evaluator) }
            .compactMap { rule -> BookingTier? in
                guard let id = rule.pickupBookingRuleID else { return .realTime }
                guard let bookingRule = service.bookingRule(id: id) else { return nil }
                return BookingTier(rawValue: bookingRule.bookingType)
            }
            .min()
    }

    private static func isOpen(rule: AvailabilityRule, on date: ServiceDate, service: OnDemandService, evaluator: BookingDeadlineEvaluator, now: Date) -> Bool {
        let bookingRule = service.bookingRule(id: rule.pickupBookingRuleID)
        if rule.pickupBookingRuleID != nil, bookingRule == nil { return false }
        return evaluator.evaluate(rule: rule, bookingRule: bookingRule, travelDate: date, now: now).state == .open
    }

    private static func status(
        bookingTier: BookingTier?,
        resolution: OnDemandBookingResolution,
        runningNow: Bool,
        bookableNow: Bool,
        runningUntil: Date?,
        nextOpening: Date?,
        hasUsableCalendar: Bool,
        hasServiceDay: Bool
    ) -> OnDemandStatus {
        if bookingTier == .advance {
            switch resolution {
            case .bookBy(let cutoff, let travelDate): return .bookBy(deadline: cutoff, travelDate: travelDate)
            case .opensAt(let open): return .bookingOpens(open)
            case .closed: return .closed
            case .noNoticeRequired, .unknown: return .unknown
            }
        }
        if runningNow && bookableNow { return .openNow(until: runningUntil) }
        if let nextOpening { return .opensAt(nextOpening) }
        // Running past the cutoff on the last service day: nothing is left to book.
        if runningNow { return .closed }
        // Empty rules, or rules with no usable calendar, promise nothing.
        guard hasUsableCalendar else { return .unknown }
        return hasServiceDay ? .unknown : .closed
    }

    private static func tags(bookingTier: BookingTier?, eligibility: OnDemandEligibility?) -> [Tag] {
        var tags: [Tag] = []
        switch bookingTier {
        case .realTime: tags.append(.noNoticeNeeded)
        case .sameDay: tags.append(.sameDayBooking)
        case .advance: tags.append(.advanceBooking)
        case nil: break
        }
        if eligibility?.requirement == .certificationRequired {
            tags.append(.eligibilityRequired)
        }
        return tags
    }
}
