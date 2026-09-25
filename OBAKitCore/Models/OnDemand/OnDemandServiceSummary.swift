//
//  OnDemandServiceSummary.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// The rider-facing facts about an on-demand service, formatted for a locale
/// in the agency's time zone: when it runs, by when to book, how to book.
///
/// Carries no localized sentences of its own — only Foundation-formatted
/// dates, times and day names — so OBAKit (and the watch, later) wrap the
/// pieces in their own templates and OBAKitCore adds no strings.
public struct OnDemandServiceSummary: Equatable, Sendable {

    public enum BookingLine: Equatable, Sendable {
        /// "Book by `deadline` for a ride on `travelDate`."
        case bookBy(deadline: String, travelDate: String)
        /// Booking for the next service day hasn't opened yet.
        case opensAt(String)
        /// The next service day's rule has no pickup booking rule.
        case noNoticeRequired
        /// Every remaining service day's deadline has passed (or the calendars ended).
        case closed
        /// A missing field or an unresolved booking rule; show contact details
        /// and no deadline line (spec §6.2).
        case unknown
    }

    public struct ServiceWindow: Equatable, Hashable, Sendable {
        /// e.g. "Mon–Sat".
        public let days: String
        /// e.g. "5:00 AM – 12:50 AM"; nil when the rule runs all service hours.
        public let hours: String?
    }

    public let bookingLine: BookingLine
    public let windows: [ServiceWindow]
    public let phoneNumber: String?
    public let phoneURL: URL?
    public let bookingURL: URL?
    public let infoURL: URL?
    public let message: String?

    public init(service: OnDemandService, timeZone: TimeZone, now: Date, locale: Locale) {
        let evaluator = BookingDeadlineEvaluator(timeZone: timeZone, calendars: service.calendars)
        let formatters = SummaryFormatters(timeZone: timeZone, locale: locale, now: now)

        windows = Self.windows(for: service, evaluator: evaluator, formatters: formatters, now: now)
        bookingLine = Self.bookingLine(for: service, evaluator: evaluator, formatters: formatters, now: now)

        let contact = service.rules.lazy.compactMap { service.bookingRule(id: $0.pickupBookingRuleID) }.first
        phoneNumber = contact?.phoneNumber
        phoneURL = contact?.phoneNumber.flatMap(Self.telephoneURL)
        bookingURL = contact?.bookingURL
        infoURL = contact?.infoURL
        message = contact?.message ?? contact?.pickupMessage
    }

    // MARK: - Windows

    private static func windows(for service: OnDemandService, evaluator: BookingDeadlineEvaluator, formatters: SummaryFormatters, now: Date) -> [ServiceWindow] {
        let calendarsByID = Dictionary(service.calendars.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Hours are a time-of-day; any day works, today keeps DST offsets current.
        let today = evaluator.serviceDate(for: now)
        var seen = Set<ServiceWindow>()
        var result: [ServiceWindow] = []

        for rule in service.rules {
            let days = Set(rule.calendarIDs.compactMap { calendarsByID[$0] }.flatMap(\.days))
            let hours: String?
            if let start = rule.startPickupTime, let end = rule.endPickupTime {
                hours = "\(formatters.time(evaluator.instant(today, start))) – \(formatters.time(evaluator.instant(today, end)))"
            } else {
                hours = nil
            }
            let window = ServiceWindow(days: daysText(Array(days), shortWeekdaySymbols: formatters.shortWeekdaySymbols), hours: hours)
            if seen.insert(window).inserted {
                result.append(window)
            }
        }
        return result
    }

    /// Collapses weekdays into localized runs: `Mon–Sat`, `Sat–Sun`,
    /// `Mon, Wed, Fri`, `Mon–Tue, Thu–Sun`. `shortWeekdaySymbols` is indexed
    /// Sunday-first, as `DateFormatter` supplies it.
    public static func daysText(_ days: [Weekday], shortWeekdaySymbols: [String]) -> String {
        let ordered = Weekday.allCases.filter { days.contains($0) }
        guard !ordered.isEmpty else { return "" }

        func symbol(_ day: Weekday) -> String {
            let index = day.calendarWeekday - 1
            return shortWeekdaySymbols.indices.contains(index) ? shortWeekdaySymbols[index] : day.rawValue
        }

        var runs: [[Weekday]] = []
        for day in ordered {
            if let last = runs.last?.last, Weekday.allCases.firstIndex(of: day) == Weekday.allCases.firstIndex(of: last)! + 1 {
                runs[runs.count - 1].append(day)
            } else {
                runs.append([day])
            }
        }
        return runs.map { run in
            run.count >= 2 ? "\(symbol(run[0]))–\(symbol(run[run.count - 1]))" : symbol(run[0])
        }.joined(separator: ", ")
    }

    // MARK: - Booking line

    private struct Candidate {
        let travelDate: ServiceDate
        let evaluation: BookingEvaluation
    }

    /// One rule's contribution to the service-wide booking line: either a
    /// bookable candidate, a still-closed date's open instant, a rule this
    /// build can't evaluate, an unresolved `pickupBookingRuleID` (which
    /// collapses the whole line to `.unknown`), or nothing worth surfacing.
    private enum RuleOutcome {
        case unresolvedBookingRule
        case bookable(Candidate)
        case notYetOpen(Date)
        case unknown
        case settled
    }

    private static func bookingLine(for service: OnDemandService, evaluator: BookingDeadlineEvaluator, formatters: SummaryFormatters, now: Date) -> BookingLine {
        guard !service.rules.isEmpty else { return .unknown }

        var bookable: [Candidate] = []
        var notYetOpen: [Date] = []
        var sawUnknown = false

        for rule in service.rules {
            switch outcome(for: rule, service: service, evaluator: evaluator, now: now) {
            case .unresolvedBookingRule:
                return .unknown
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

        return resolvedLine(bookable: bookable, notYetOpen: notYetOpen, sawUnknown: sawUnknown, evaluator: evaluator, formatters: formatters)
    }

    /// The single rule's outcome as of `now`: its own next bookable date if
    /// it has one, otherwise how its next active date currently evaluates.
    private static func outcome(for rule: AvailabilityRule, service: OnDemandService, evaluator: BookingDeadlineEvaluator, now: Date) -> RuleOutcome {
        let bookingRule = service.bookingRule(id: rule.pickupBookingRuleID)
        // Referenced but missing is not "no notice": nothing can be promised.
        guard !(rule.pickupBookingRuleID != nil && bookingRule == nil) else {
            return .unresolvedBookingRule
        }

        if let date = evaluator.nextBookableServiceDate(rule: rule, bookingRule: bookingRule, now: now) {
            let evaluation = evaluator.evaluate(rule: rule, bookingRule: bookingRule, travelDate: date, now: now)
            return .bookable(Candidate(travelDate: date, evaluation: evaluation))
        }

        guard let nextActive = evaluator.nextActiveServiceDate(rule: rule, from: evaluator.serviceDate(for: now)) else {
            return .settled
        }
        let evaluation = evaluator.evaluate(rule: rule, bookingRule: bookingRule, travelDate: nextActive, now: now)
        switch evaluation.state {
        case .notYetOpen:
            return evaluation.openInstant.map(RuleOutcome.notYetOpen) ?? .settled
        case .unknown:
            return .unknown
        case .open, .closedForDate:
            return .settled
        }
    }

    /// Turns the rules' individual outcomes into one line: the earliest
    /// bookable candidate wins outright; otherwise the earliest not-yet-open
    /// date; otherwise `.unknown` if any rule couldn't be evaluated, else
    /// every remaining date is closed.
    private static func resolvedLine(bookable: [Candidate], notYetOpen: [Date], sawUnknown: Bool, evaluator: BookingDeadlineEvaluator, formatters: SummaryFormatters) -> BookingLine {
        // Earliest date wins; on the same date the earliest cutoff is the one
        // to show — never later than any real deadline the rider might hit.
        if let best = bookable.min(by: { lhs, rhs in
            if lhs.travelDate != rhs.travelDate { return lhs.travelDate < rhs.travelDate }
            return (lhs.evaluation.cutoffInstant ?? .distantFuture) < (rhs.evaluation.cutoffInstant ?? .distantFuture)
        }) {
            guard let cutoff = best.evaluation.cutoffInstant else { return .noNoticeRequired }
            return .bookBy(deadline: formatters.deadline(cutoff), travelDate: formatters.travelDate(evaluator.noon(best.travelDate)))
        }

        if let earliestOpen = notYetOpen.min() {
            return .opensAt(formatters.deadline(earliestOpen))
        }
        return sawUnknown ? .unknown : .closed
    }

    // MARK: - Formatting

    /// Named to avoid shadowing OBAKitCore's `Formatters` inside this type.
    private struct SummaryFormatters {
        let timeFormatter: DateFormatter
        let deadlineFormatter: DateFormatter
        let travelDateFormatter: DateFormatter
        let shortWeekdaySymbols: [String]
        let calendar: Calendar
        let now: Date

        init(timeZone: TimeZone, locale: Locale, now: Date) {
            timeFormatter = DateFormatter()
            timeFormatter.locale = locale
            timeFormatter.timeZone = timeZone
            timeFormatter.dateStyle = .none
            timeFormatter.timeStyle = .short

            deadlineFormatter = DateFormatter()
            deadlineFormatter.locale = locale
            deadlineFormatter.timeZone = timeZone
            deadlineFormatter.dateStyle = .medium
            deadlineFormatter.timeStyle = .short
            deadlineFormatter.doesRelativeDateFormatting = true

            travelDateFormatter = DateFormatter()
            travelDateFormatter.locale = locale
            travelDateFormatter.timeZone = timeZone
            travelDateFormatter.setLocalizedDateFormatFromTemplate("EEEMMMd")

            let symbols = DateFormatter()
            symbols.locale = locale
            shortWeekdaySymbols = symbols.shortWeekdaySymbols ?? Weekday.allCases.map(\.rawValue)

            var gregorian = Calendar(identifier: .gregorian)
            gregorian.timeZone = timeZone
            calendar = gregorian
            self.now = now
        }

        func time(_ date: Date) -> String { timeFormatter.string(from: date) }

        /// `dateStyle: .medium, timeStyle: .short`, in the agency zone,
        /// reading "Today"/"Tomorrow" for the day (or the one after) around
        /// `now`.
        ///
        /// `DateFormatter.doesRelativeDateFormatting` compares the date being
        /// formatted against the *live* wall clock, not against this
        /// presenter's `now` — so on its own it would ignore the injected
        /// clock entirely and label a deadline relative to whatever day the
        /// process happens to be running on, not the day the presenter was
        /// built for. `relativeProbe` asks the formatter to describe a
        /// stand-in that really is that many calendar days from the live
        /// clock (so the relative word it produces is genuine, locale-correct
        /// Foundation vocabulary) but carries `date`'s own time of day, which
        /// keeps the label a pure function of `now`.
        func deadline(_ date: Date) -> String {
            guard let probe = relativeProbe(for: date) else {
                return deadlineFormatter.string(from: date)
            }
            return deadlineFormatter.string(from: probe)
        }

        func travelDate(_ date: Date) -> String { travelDateFormatter.string(from: date) }

        private func relativeProbe(for date: Date) -> Date? {
            let dayOffset = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? Int.max
            guard (-1...1).contains(dayOffset), let shiftedDay = calendar.date(byAdding: .day, value: dayOffset, to: Date()) else {
                return nil
            }
            let timeOfDay = calendar.dateComponents([.hour, .minute, .second], from: date)
            return calendar.date(bySettingHour: timeOfDay.hour ?? 0, minute: timeOfDay.minute ?? 0, second: timeOfDay.second ?? 0, of: shiftedDay)
        }
    }

    /// Same cleaning as `Agency.callURL`: keep digits and `+`.
    private static func telephoneURL(_ raw: String) -> URL? {
        let cleaned = raw.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        guard !cleaned.isEmpty else { return nil }
        return URL(string: "tel://\(cleaned)")
    }
}
