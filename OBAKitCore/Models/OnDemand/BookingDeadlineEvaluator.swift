//
//  BookingDeadlineEvaluator.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// The rider-facing booking state of one rule on one travel date.
public enum BookingState: String, Sendable {
    /// `priorNoticeStartDay`/`priorNoticeDurationMax` says booking hasn't opened yet.
    case notYetOpen
    case open
    /// The cutoff has passed for this date.
    case closedForDate
    /// The feed omitted a conditionally-required field, so no deadline can be
    /// computed. A client-only state, never on the wire (spec §6.2).
    case unknown
}

public struct BookingEvaluation: Equatable, Sendable {
    public let state: BookingState
    public let cutoffInstant: Date?
    public let openInstant: Date?

    public init(state: BookingState, cutoffInstant: Date?, openInstant: Date?) {
        self.state = state
        self.cutoffInstant = cutoffInstant
        self.openInstant = openInstant
    }

    public static let unknown = BookingEvaluation(state: .unknown, cutoffInstant: nil, openInstant: nil)
}

/// The normative booking-deadline algorithm (wiki §2.5 as corrected by spec
/// §6), shared with Android and verified by `flex-booking-vectors.json`.
///
/// Every value is a **service day in the agency's time zone**. Service days
/// are anchored GTFS-style at local noon minus twelve hours, so a `25:00:00`
/// window and a DST transition both come out right. `now` is supplied by the
/// caller: the UI passes the device wall clock, never the envelope
/// `currentTime` (responses are long-cached and it can be hours stale).
public struct BookingDeadlineEvaluator: Sendable {
    public let timeZone: TimeZone
    private let calendar: Calendar
    private let calendarsByID: [String: OnDemandCalendar]

    /// Caps every day-stepping loop: a calendar with no active days, or a
    /// rule whose calendars end years out, must not spin.
    private static let maximumLookaheadDays = 400

    public init(timeZone: TimeZone, calendars: [OnDemandCalendar]) {
        self.timeZone = timeZone
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone
        self.calendar = gregorian
        self.calendarsByID = Dictionary(calendars.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Service-day arithmetic

    /// Local noon of `date`. Always exists in the Gregorian calendar, which is
    /// why noon — not midnight, which DST can skip — is the anchor.
    public func noon(_ date: ServiceDate) -> Date {
        var components = DateComponents()
        components.year = date.year
        components.month = date.month
        components.day = date.day
        components.hour = 12
        guard let noon = calendar.date(from: components) else {
            preconditionFailure("Gregorian noon must exist for \(date)")
        }
        return noon
    }

    /// `anchor(D) = local noon of D − 12 h`.
    public func anchor(_ date: ServiceDate) -> Date {
        noon(date).addingTimeInterval(-12 * 3600)
    }

    /// `instant(D, hms) = anchor(D) + hms`; `hms` may exceed 24 h.
    public func instant(_ date: ServiceDate, _ time: GTFSTimeOfDay) -> Date {
        anchor(date).addingTimeInterval(TimeInterval(time.seconds))
    }

    /// The agency-local calendar date containing `instant`.
    public func serviceDate(for instant: Date) -> ServiceDate {
        let components = calendar.dateComponents([.year, .month, .day], from: instant)
        return ServiceDate(year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1)
    }

    /// `date` shifted by `days` calendar days, stepping through noon so DST
    /// changes cannot land on the wrong day.
    public func adding(days: Int, to date: ServiceDate) -> ServiceDate {
        guard let shifted = calendar.date(byAdding: .day, value: days, to: noon(date)) else {
            return date
        }
        return serviceDate(for: shifted)
    }

    public func weekday(of date: ServiceDate) -> Weekday {
        Weekday(calendarWeekday: calendar.component(.weekday, from: noon(date)))
    }

    // MARK: - Calendars

    /// Whether `calendarID` runs on `date`: inside its range, on one of its
    /// weekdays, and not an `exceptedDates` entry. Unknown ids, and calendars
    /// without a usable `startDate` or `endDate`, are never active.
    public func isActive(calendarID: String, on date: ServiceDate) -> Bool {
        guard let serviceCalendar = calendarsByID[calendarID],
              let startDate = serviceCalendar.startDate,
              let endDate = serviceCalendar.endDate else {
            return false
        }
        guard date >= startDate, date <= endDate else { return false }
        guard serviceCalendar.days.contains(weekday(of: date)) else { return false }
        return !serviceCalendar.exceptedDates.contains(date)
    }

    /// Whether any of `rule`'s calendars is known and has a usable
    /// `startDate` and `endDate`. Without one the rule has no service days
    /// the evaluator can vouch for, which spec §6.3 makes unknown, not closed.
    public func hasUsableCalendar(_ rule: AvailabilityRule) -> Bool {
        rule.calendarIDs.contains { calendarID in
            guard let serviceCalendar = calendarsByID[calendarID] else { return false }
            return serviceCalendar.startDate != nil && serviceCalendar.endDate != nil
        }
    }

    /// `countBack(D, n, calendarId)` from spec §6.1/§6.3: calendar days when
    /// there is no (known) calendar, otherwise the n-th preceding day active
    /// on it. `n == 0` returns `D` unconditionally, without validating the
    /// calendar. A known calendar with no active weekdays or no usable
    /// `startDate`, or whose `startDate` the walk reaches before `n` days are
    /// consumed, fails closed (`nil`) rather than returning a date outside
    /// its range.
    public func countBack(from date: ServiceDate, days count: Int, calendarID: String?) -> ServiceDate? {
        guard count > 0 else { return date }
        guard let calendarID, let serviceCalendar = calendarsByID[calendarID] else {
            return adding(days: -count, to: date)
        }
        guard !serviceCalendar.days.isEmpty, let startDate = serviceCalendar.startDate else { return nil }

        var remaining = count
        var cursor = date
        var stepped = 0
        while stepped < Self.maximumLookaheadDays {
            cursor = adding(days: -1, to: cursor)
            stepped += 1
            guard cursor >= startDate else { return nil }
            if isActive(calendarID: calendarID, on: cursor) {
                remaining -= 1
                if remaining == 0 {
                    return cursor
                }
            }
        }
        return nil
    }

    // MARK: - Evaluation

    /// A resolved cutoff/open pair, ahead of turning it into rider-facing
    /// state (spec §6). Each booking-type helper returns nil when a
    /// conditionally-required field is missing, which `evaluate` maps to
    /// `BookingEvaluation.unknown`.
    private typealias Deadlines = (cutoff: Date, open: Date?)

    /// `evaluate(rule, bookingRule, D, now)` from spec §6. `bookingRule` is
    /// the rule's *pickup* booking rule; pass nil when the rule has no
    /// `pickupBookingRuleId` (no notice required).
    public func evaluate(
        rule: AvailabilityRule,
        bookingRule: OnDemandBookingRule?,
        travelDate: ServiceDate,
        now: Date
    ) -> BookingEvaluation {
        guard let bookingRule else {
            return BookingEvaluation(state: .open, cutoffInstant: nil, openInstant: nil)
        }

        let deadlines: Deadlines?
        switch bookingRule.bookingType {
        case 0:
            deadlines = realTimeDeadlines(rule: rule, travelDate: travelDate)
        case 1:
            deadlines = sameDayDeadlines(rule: rule, bookingRule: bookingRule, travelDate: travelDate)
        case 2:
            deadlines = priorDayDeadlines(bookingRule: bookingRule, travelDate: travelDate)
        default:
            deadlines = nil
        }
        guard let deadlines else { return .unknown }

        return BookingEvaluation(
            state: bookingState(now: now, cutoff: deadlines.cutoff, open: deadlines.open),
            cutoffInstant: deadlines.cutoff,
            openInstant: deadlines.open
        )
    }

    /// `latestPickup(D) = instant(D, rule.endPickupTime ?? 24:00:00)` — the
    /// deadline every booking type anchors to, computed once rather than
    /// duplicated per type (mirrors Android's `latestPickup`).
    private func latestPickup(rule: AvailabilityRule, travelDate: ServiceDate) -> Date {
        instant(travelDate, rule.endPickupTime ?? .endOfServiceDay)
    }

    /// Type 0, real-time: booked at ride time. Notice fields are forbidden
    /// for this type and ignored even when a feed ships them (Charlevoix
    /// `booking_rule_CC4`).
    private func realTimeDeadlines(rule: AvailabilityRule, travelDate: ServiceDate) -> Deadlines {
        (latestPickup(rule: rule, travelDate: travelDate), nil)
    }

    /// Type 1, same-day minutes-based notice. A missing minimum would invent
    /// the latest possible deadline — the worst failure — so it is unknown
    /// instead. `priorNoticeCalendarId` is honoured only for type 2, so the
    /// start day here counts plain calendar days.
    private func sameDayDeadlines(rule: AvailabilityRule, bookingRule: OnDemandBookingRule, travelDate: ServiceDate) -> Deadlines? {
        guard let minimumMinutes = bookingRule.priorNoticeDurationMin else { return nil }
        let cutoff = latestPickup(rule: rule, travelDate: travelDate).addingTimeInterval(-Double(minimumMinutes) * 60)

        let open: Date?
        if let maximumMinutes = bookingRule.priorNoticeDurationMax {
            open = instant(travelDate, rule.startPickupTime ?? .midnight)
                .addingTimeInterval(-Double(maximumMinutes) * 60)
        } else if let startDay = bookingRule.priorNoticeStartDay {
            open = instant(adding(days: -startDay, to: travelDate), bookingRule.priorNoticeStartTime ?? .midnight)
        } else {
            open = nil
        }
        return (cutoff, open)
    }

    /// Type 2, prior day(s). The notice calendar counts service days for both
    /// the last day and the start day (spec §6.1); a count-back that can't
    /// complete (spec §6.3) makes the whole evaluation unknown.
    private func priorDayDeadlines(bookingRule: OnDemandBookingRule, travelDate: ServiceDate) -> Deadlines? {
        guard let lastDay = bookingRule.priorNoticeLastDay else { return nil }
        let noticeCalendarID = bookingRule.priorNoticeCalendarID
        guard let lastDayDate = countBack(from: travelDate, days: lastDay, calendarID: noticeCalendarID) else { return nil }
        // A missing last time means 00:00 — never later than any real deadline.
        let cutoff = instant(lastDayDate, bookingRule.priorNoticeLastTime ?? .midnight)

        guard let startDay = bookingRule.priorNoticeStartDay else {
            return (cutoff, nil)
        }
        guard let startDayDate = countBack(from: travelDate, days: startDay, calendarID: noticeCalendarID) else { return nil }
        return (cutoff, instant(startDayDate, bookingRule.priorNoticeStartTime ?? .midnight))
    }

    private func bookingState(now: Date, cutoff: Date, open: Date?) -> BookingState {
        if let open, now < open {
            return .notYetOpen
        } else if now > cutoff {
            return .closedForDate
        } else {
            return .open
        }
    }

    /// The earliest active service day of `rule`, on or after `date`, bounded
    /// by the rule's latest usable calendar `endDate`.
    private func nextActiveServiceDate(rule: AvailabilityRule, from date: ServiceDate) -> ServiceDate? {
        guard let lastDate = rule.calendarIDs.compactMap({ calendarsByID[$0]?.endDate }).max() else {
            return nil
        }
        var cursor = date
        var stepped = 0
        while cursor <= lastDate && stepped < Self.maximumLookaheadDays {
            if rule.calendarIDs.contains(where: { isActive(calendarID: $0, on: cursor) }) {
                return cursor
            }
            cursor = adding(days: 1, to: cursor)
            stepped += 1
        }
        return nil
    }

    /// `nextBookableServiceDate` from spec §6.4: the earliest active service
    /// day from the agency-local today whose evaluation is `open`. A
    /// candidate that evaluates `unknown` (e.g. its own count-back can't
    /// complete) is skipped, not treated as a search-ending failure — Android
    /// and maglev both keep walking past it.
    public func nextBookableServiceDate(
        rule: AvailabilityRule,
        bookingRule: OnDemandBookingRule?,
        now: Date
    ) -> ServiceDate? {
        nextServiceDate(in: .open, rule: rule, bookingRule: bookingRule, now: now)?.date
    }

    /// The earliest active service day from the agency-local today, within the
    /// same bounds as `nextBookableServiceDate`, whose evaluation is `state`,
    /// together with that evaluation. Asking for `.notYetOpen` finds the first
    /// date whose booking is still to open, which need not be the rule's next
    /// service day — that one may already be closed.
    public func nextServiceDate(
        in state: BookingState,
        rule: AvailabilityRule,
        bookingRule: OnDemandBookingRule?,
        now: Date
    ) -> (date: ServiceDate, evaluation: BookingEvaluation)? {
        var found: (date: ServiceDate, evaluation: BookingEvaluation)?
        walkServiceDates(rule: rule, bookingRule: bookingRule, now: now) { date, evaluation in
            guard evaluation.state == state else { return true }
            found = (date, evaluation)
            return false
        }
        return found
    }

    /// Hands `body` each active service day of `rule` from the agency-local
    /// today, in order and with its evaluation, until `body` returns false
    /// or the walk reaches the bounds `nextBookableServiceDate` uses.
    func walkServiceDates(
        rule: AvailabilityRule,
        bookingRule: OnDemandBookingRule?,
        now: Date,
        _ body: (ServiceDate, BookingEvaluation) -> Bool
    ) {
        var cursor: ServiceDate? = serviceDate(for: now)
        var stepped = 0
        while let candidate = cursor.flatMap({ nextActiveServiceDate(rule: rule, from: $0) }), stepped < Self.maximumLookaheadDays {
            let evaluation = evaluate(rule: rule, bookingRule: bookingRule, travelDate: candidate, now: now)
            guard body(candidate, evaluation) else { return }
            cursor = adding(days: 1, to: candidate)
            stepped += 1
        }
    }
}
