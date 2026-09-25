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
/// Contact details never depend on that zone being known.
///
/// Carries no localized sentences of its own — only Foundation-formatted
/// dates, times and day names — so OBAKit (and the watch, later) wrap the
/// pieces in their own templates and OBAKitCore adds no strings.
public struct OnDemandServiceSummary: Equatable, Sendable {

    public enum BookingLine: Equatable, Sendable {
        /// "Book by `deadline` for a ride on `travelDate`."
        case bookBy(deadline: String, travelDate: String)
        /// No service day is bookable yet: booking for the first not-yet-open
        /// service day opens at this time. That day need not be the next
        /// service day, which may already be closed.
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
    /// When the booking line can next read differently: the earliest cutoff
    /// or opening instant after `now` among the rules' candidates, or the
    /// agency's next midnight if sooner, when "tomorrow" becomes "today".
    /// Nil when the zone is unknown, so nothing ahead would change the line.
    public let nextChangeInstant: Date?

    /// - Parameter timeZone: The agency's zone, or nil when it is unknown.
    ///   Without a zone the booking line is `.unknown`, because a deadline is
    ///   an instant and cannot be placed. Windows and contact details are
    ///   still computed: pickup times are GTFS wall-clock times of day, which
    ///   are always formatted through a fixed UTC zone (see `wallClock`).
    public init(service: OnDemandService, timeZone: TimeZone?, now: Date, locale: Locale) {
        let resolvedZone = timeZone ?? .gmt
        let evaluator = BookingDeadlineEvaluator(timeZone: resolvedZone, calendars: service.calendars)
        let formatters = SummaryFormatters(timeZone: resolvedZone, locale: locale, now: now)

        windows = Self.windows(for: service, formatters: formatters)
        if timeZone == nil {
            bookingLine = .unknown
            nextChangeInstant = nil
        } else {
            let (line, boundary) = Self.bookingLine(for: service, evaluator: evaluator, formatters: formatters, now: now)
            bookingLine = line
            nextChangeInstant = [boundary, formatters.nextMidnight].compactMap { $0 }.min()
        }

        let contact = service.rules.lazy.compactMap { service.bookingRule(id: $0.pickupBookingRuleID) }.first
        phoneNumber = contact?.phoneNumber
        phoneURL = contact?.phoneNumber.flatMap(Self.telephoneURL)
        bookingURL = contact?.bookingURL
        infoURL = contact?.infoURL
        message = contact?.message ?? contact?.pickupMessage
    }

    // MARK: - Windows

    private static func windows(for service: OnDemandService, formatters: SummaryFormatters) -> [ServiceWindow] {
        let calendarsByID = Dictionary(service.calendars.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<ServiceWindow>()
        var result: [ServiceWindow] = []

        for rule in service.rules {
            let days = Set(rule.calendarIDs.compactMap { calendarsByID[$0] }.flatMap(\.days))
            let hours: String?
            if let start = rule.startPickupTime, let end = rule.endPickupTime {
                hours = "\(formatters.wallClock(start)) – \(formatters.wallClock(end))"
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

    private static func bookingLine(for service: OnDemandService, evaluator: BookingDeadlineEvaluator, formatters: SummaryFormatters, now: Date) -> (BookingLine, Date?) {
        guard !service.rules.isEmpty else { return (.unknown, nil) }

        var bookable: [Candidate] = []
        var notYetOpen: [Date] = []
        var sawUnknown = false

        for rule in service.rules {
            switch outcome(for: rule, service: service, evaluator: evaluator, now: now) {
            case .unresolvedBookingRule:
                return (.unknown, nil)
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

        let line = resolvedLine(bookable: bookable, notYetOpen: notYetOpen, sawUnknown: sawUnknown, evaluator: evaluator, formatters: formatters)
        let boundaries = bookable.compactMap(\.evaluation.cutoffInstant) + notYetOpen
        return (line, boundaries.filter { $0 > now }.min())
    }

    /// The single rule's outcome as of `now`: its own next bookable date if
    /// it has one, otherwise the first date whose booking is still to open,
    /// otherwise whether any remaining date can't be evaluated. One walk
    /// over the rule's service days answers all three.
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
        // The next service day may already be closed while a later one has
        // yet to open, so the walk keeps the first not-yet-open date it sees.
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
        let wallClockFormatter: DateFormatter
        let deadlineFormatterRelative: DateFormatter
        let deadlineFormatterAbsolute: DateFormatter
        let travelDateFormatter: DateFormatter
        let shortWeekdaySymbols: [String]
        let calendar: Calendar
        let now: Date

        init(timeZone: TimeZone, locale: Locale, now: Date) {
            wallClockFormatter = DateFormatter()
            wallClockFormatter.locale = locale
            wallClockFormatter.timeZone = .gmt
            wallClockFormatter.dateStyle = .none
            wallClockFormatter.timeStyle = .short

            deadlineFormatterRelative = DateFormatter()
            deadlineFormatterRelative.locale = locale
            deadlineFormatterRelative.timeZone = timeZone
            deadlineFormatterRelative.dateStyle = .medium
            deadlineFormatterRelative.timeStyle = .short
            deadlineFormatterRelative.doesRelativeDateFormatting = true
            // Every template places the deadline mid-sentence ("Book by
            // today at 5:00 PM"), so the relative word must not be capitalized.
            deadlineFormatterRelative.formattingContext = .middleOfSentence

            // Same styling, but never reads the live wall clock — used
            // whenever `relativeProbe` can't vouch for a "Today"/"Tomorrow"
            // label (see `deadline(_:today:)`).
            deadlineFormatterAbsolute = DateFormatter()
            deadlineFormatterAbsolute.locale = locale
            deadlineFormatterAbsolute.timeZone = timeZone
            deadlineFormatterAbsolute.dateStyle = .medium
            deadlineFormatterAbsolute.timeStyle = .short
            deadlineFormatterAbsolute.doesRelativeDateFormatting = false
            deadlineFormatterAbsolute.formattingContext = .middleOfSentence

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

        /// A nominal GTFS time of day, e.g. "5:00 AM"; `25:00:00` reads
        /// "1:00 AM". Formatted as that offset from a UTC midnight: UTC has
        /// no DST, so a transition day in the agency's zone cannot shift it.
        func wallClock(_ time: GTFSTimeOfDay) -> String {
            wallClockFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(time.seconds)))
        }

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
        /// keeps the label a pure function of `now` — except for the
        /// unavoidable race between the two clock reads this method and
        /// `SummaryFormatters.init` each make: if the presenter is built just
        /// before local midnight and this method runs just after, `now` and
        /// the live day it's compared against can disagree by one day. When
        /// `relativeProbe` can't safely vouch for a day offset (out of
        /// range, or a DST gap moved the probe's clock time — see
        /// `relativeProbe`), this falls back to `deadlineFormatterAbsolute`,
        /// which never reads the wall clock at all.
        func deadline(_ date: Date, today: Date = Date()) -> String {
            guard let probe = relativeProbe(for: date, today: today) else {
                return deadlineFormatterAbsolute.string(from: date)
            }
            return deadlineFormatterRelative.string(from: probe)
        }

        func travelDate(_ date: Date) -> String { travelDateFormatter.string(from: date) }

        /// The start of the day after `now`'s, in the agency zone.
        var nextMidnight: Date? {
            calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        }

        /// `today` stands in for the live wall clock; production always
        /// passes `Date()` (the caller's default). Exposed as a parameter
        /// only so tests can pin a specific "live" day — e.g. a DST
        /// spring-forward day — deterministically.
        private func relativeProbe(for date: Date, today: Date) -> Date? {
            let dayOffset = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? Int.max
            guard (-1...1).contains(dayOffset), let shiftedDay = calendar.date(byAdding: .day, value: dayOffset, to: today) else {
                return nil
            }

            let targetTime = calendar.dateComponents([.hour, .minute, .second], from: date)
            guard let probe = calendar.date(bySettingHour: targetTime.hour ?? 0, minute: targetTime.minute ?? 0, second: targetTime.second ?? 0, of: shiftedDay) else {
                return nil
            }

            // A DST spring-forward gap can make `bySettingHour` roll a
            // nonexistent local time forward (02:30 in the gap becomes
            // 03:00) instead of failing — a probe like that would show a
            // later time than the real deadline. Treat a clock mismatch the
            // same as a hard failure.
            let probeTime = calendar.dateComponents([.hour, .minute], from: probe)
            guard probeTime.hour == targetTime.hour, probeTime.minute == targetTime.minute else {
                return nil
            }
            return probe
        }
    }

    /// Test-only seam for `SummaryFormatters.deadline`'s DST-gap guard: lets
    /// a test pin the "live now" `relativeProbe` reads instead of the real
    /// wall clock, so a spring-forward gap can be exercised deterministically.
    /// No production code path calls this.
    static func deadlineForTesting(now: Date, cutoff: Date, today: Date, timeZone: TimeZone, locale: Locale) -> String {
        SummaryFormatters(timeZone: timeZone, locale: locale, now: now).deadline(cutoff, today: today)
    }

    /// Same cleaning as `Agency.callURL`: keep digits and `+`.
    private static func telephoneURL(_ raw: String) -> URL? {
        let cleaned = raw.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        guard !cleaned.isEmpty else { return nil }
        return URL(string: "tel://\(cleaned)")
    }
}
