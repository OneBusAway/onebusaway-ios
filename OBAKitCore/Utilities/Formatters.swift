//
//  Formatters.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 12/11/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import MapKit

public class Formatters: NSObject {
    private let locale: Locale
    private let themeColors: ThemeColors
    private let calendar: Calendar

    /// Creates a new `Formatters` object that will use the provided `Calendar` and `Locale` for locale-specific customization.
    ///
    /// - Note: You probably should pass in the `autoupdatingCurrent` instances of `Locale` and `Calendar` to this method.
    ///
    /// - Parameter locale: The current locale of the user's device.
    public init(locale: Locale, calendar: Calendar, themeColors: ThemeColors) {
        self.locale = locale
        self.calendar = calendar
        self.themeColors = themeColors
    }

    // MARK: - Distance Formatting

    /// Formats distances into human-readable strings that conform to the user's locale.
    public lazy var distanceFormatter: MKDistanceFormatter = {
        let formatter = MKDistanceFormatter()
        formatter.locale = locale
        return formatter
    }()

    // MARK: - Formatted Times

    /// Returns a representation of `date` that varies depending on whether `date` happens to be from today or another day.
    ///
    /// For instance, if `date` is from today, the `String` returned will simply be the time. If `date` is from any other day, then
    /// the `String` returned will look something like "Formatted short date, 9:41".
    /// - Parameter date: The date from which the return value will be created.
    public func contextualDateTimeString(_ date: Date) -> String {
        if calendar.isDateInToday(date) {
            return timeFormatter.string(from: date)
        }
        else {
            return shortDateTimeFormatter.string(from: date)
        }
    }

    /// Converts a date into a human-readable date/time string that conforms to the user's locale.
    public lazy var shortDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = locale

        return formatter
    }()

    /// Converts a date into a human-readable time string that conforms to the user's locale.
    public lazy var timeFormatter: DateFormatter = {
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        timeFormatter.locale = locale

        return timeFormatter
    }()

    public func formattedDateRange(from: Date, to: Date) -> String {
        let fromString = timeFormatter.string(from: from)
        let toString = timeFormatter.string(from: to)
        let format = OBALoc("formatters.date_range_fmt", value: "%@ — %@", comment: "Represents a timeframe. e.g. 9:00 AM — 11:00 AM.")

        return String(format: format, fromString, toString)
    }

    /// Creates formatted strings for time intervals.
    public lazy var positionalTimeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.calendar = locale.calendar
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    // MARK: - ArrivalDeparture

    public func fullAttributedExplanation(from arrivalDeparture: ArrivalDeparture) -> NSAttributedString {
        let arrDepTime = timeFormatter.string(from: arrivalDeparture.arrivalDepartureDate)

        let explanationText: String
        if arrivalDeparture.scheduleStatus == .unknown {
            explanationText = Strings.scheduledNotRealTime
        }
        else {
            explanationText = formattedScheduleDeviation(for: arrivalDeparture)
        }

        let scheduleStatusColor = colorForScheduleStatus(arrivalDeparture.scheduleStatus)

        let timeExplanationFont = UIFont.preferredFont(forTextStyle: .footnote)

        let attributedExplanation = NSMutableAttributedString(string: "\(arrDepTime) - ", attributes: [NSAttributedString.Key.font: timeExplanationFont])

        let explanation = NSAttributedString(string: explanationText, attributes: [NSAttributedString.Key.font: timeExplanationFont, NSAttributedString.Key.foregroundColor: scheduleStatusColor])
        attributedExplanation.append(explanation)

        return attributedExplanation
    }

    /// Creates a string that explains when the `ArrivalDeparture` arrives or departs.
    ///
    /// For example, it might generate a string that says "Arrived 3 min ago", "Departing now", or "Departs in 8 min".
    ///
    /// - Parameter arrivalDeparture: The ArrivalDeparture object representing the string
    /// - Returns: A localized string explaining the arrival/departure status.
    public func explanation(from arrivalDeparture: ArrivalDeparture) -> String {
        let temporalState = arrivalDeparture.temporalState
        let arrivalDepartureStatus = arrivalDeparture.arrivalDepartureStatus
        let apply: (String) -> String = { String(format: $0, abs(arrivalDeparture.arrivalDepartureMinutes)) }

        switch (temporalState, arrivalDepartureStatus) {
        case (.past, .arriving):
            return apply(OBALoc("formatters.arrived_x_min_ago_fmt", value: "Arrived %d min ago", comment: "Use for vehicles that arrived X minutes ago."))
        case (.past, .departing):
            return apply(OBALoc("formatters.departed_x_min_ago_fmt", value: "Departed %d min ago", comment: "Use for vehicles that departed X minutes ago."))
        case (.present, .arriving):
            return OBALoc("formatters.arriving_now", value: "Arriving now", comment: "Use for vehicles arriving now.")
        case (.present, .departing):
            return OBALoc("formatters.departing_now", value: "Departing now", comment: "Use for vehicles departing now.")
        case (.future, .arriving):
            return apply(OBALoc("formatters.arrives_in_x_min_fmt", value: "Arrives in %d min", comment: "Use for vehicles arriving in X minutes."))
        case (.future, .departing):
            return apply(OBALoc("formatters.departs_in_x_min_fmt", value: "Departs in %d min", comment: "Use for vehicles departing in X minutes."))
        }
    }

    // MARK: - ArrivalDeparture Schedule Deviation

    /// Creates a formatted string representing the deviation from schedule described by `arrivalDeparture`
    ///
    /// For example, if an `ArrivalDeparture` object representing an arrival is one minute late, it will
    /// return the string `"arrives 1 min late"`.
    ///
    /// - Parameter arrivalDeparture: The object used to determine the schedule deviation.
    /// - Returns: A formatted string representing the schedule deviation.
    public func formattedScheduleDeviation(for arrivalDeparture: ArrivalDeparture) -> String {
        switch (arrivalDeparture.temporalState, arrivalDeparture.arrivalDepartureStatus) {
        case (.past, .arriving):
            return explanationOfDeviationForPastArrival(minutes: arrivalDeparture.deviationFromScheduleInMinutes)
        case (.past, .departing):
            return explanationOfDeviationForPastDeparture(minutes: arrivalDeparture.deviationFromScheduleInMinutes)
        case (_, .arriving):
            return explanationOfDeviationForFutureArrival(minutes: arrivalDeparture.deviationFromScheduleInMinutes)
        case (_, .departing):
            fallthrough // swiftlint:disable:this no_fallthrough_only
        default:
            return explanationOfDeviationForFutureDeparture(minutes: arrivalDeparture.deviationFromScheduleInMinutes)
        }
    }

    private func explanationOfDeviationForPastArrival(minutes: Int) -> String {
        if minutes > 0 {
            let str = OBALoc("formatters.deviation.arrival_past_late_fmt", value: "arrived %d min late", comment: "Format string for describing a late arrival schedule deviation. e.g. Arrived 3 min late. Note that the abbrevation for 'minutes' should make sense for both singular and plural forms.")
            return String(format: str, minutes)
        }
        else if minutes < 0 {
            let str = OBALoc("formatters.deviation.arrival_past_early_fmt", value: "arrived %d min early", comment: "Format string for describing an early arrival schedule deviation. e.g. Arrived 3 min early. Note that the abbrevation for 'minutes' should make sense for both singular and plural forms.")
            return String(format: str, minutes)
        }
        else {
            return OBALoc("formatters.deviation.arrival_past_on_time", value: "arrived on time", comment: "Describes an on-time arrival. e.g. arrived on time.")
        }
    }

    private func explanationOfDeviationForPastDeparture(minutes: Int) -> String {
        if minutes > 0 {
            let str = OBALoc("formatters.deviation.departure_past_late_fmt", value: "departed %d min late", comment: "Format string for describing a late departure schedule deviation. e.g. Departed 3 min late. Note that the abbrevation for 'minutes' should make sense for both singular and plural forms.")
            return String(format: str, minutes)
        }
        else if minutes < 0 {
            let str = OBALoc("formatters.deviation.departure_past_early_fmt", value: "departed %d min early", comment: "Format string for describing an early departure schedule deviation. e.g. Departed 3 min early. Note that the abbrevation for 'minutes' should make sense for both singular and plural forms.")
            return String(format: str, minutes)
        }
        else {
            return OBALoc("formatters.deviation.departure_past_on_time", value: "departed on time", comment: "Describes an on-time departure. e.g. departed on time.")
        }
    }

    private func explanationOfDeviationForFutureArrival(minutes: Int) -> String {
        if minutes > 0 {
            let str = OBALoc("formatters.deviation.arrival_future_late_fmt", value: "arrives %d min late", comment: "Format string for describing a late future arrival schedule deviation. e.g. arrives 3 min late. Note that the abbrevation for 'minutes' should make sense for both singular and plural forms.")
            return String(format: str, minutes)
        }
        else if minutes < 0 {
            let str = OBALoc("formatters.deviation.arrival_future_early_fmt", value: "arrives %d min early", comment: "Format string for describing an early future arrival schedule deviation. e.g. arrives 3 min early. Note that the abbrevation for 'minutes' should make sense for both singular and plural forms.")
            return String(format: str, -minutes)
        }
        else {
            return OBALoc("formatters.deviation.arrival_future_on_time", value: "arrives on time", comment: "Describes an on-time arrival. e.g. arrives on time.")
        }
    }

    private func explanationOfDeviationForFutureDeparture(minutes: Int) -> String {
        if minutes > 0 {
            let str = OBALoc("formatters.deviation.departure_future_late_fmt", value: "departs %d min late", comment: "Format string for describing a late future departure schedule deviation. e.g. departs 3 min late. Note that the abbrevation for 'minutes' should make sense for both singular and plural forms.")
            return String(format: str, minutes)
        }
        else if minutes < 0 {
            let str = OBALoc("formatters.deviation.departure_future_early_fmt", value: "departs %d min early", comment: "Format string for describing an early future departure schedule deviation. e.g. departs 3 min early. Note that the abbrevation for 'minutes' should make sense for both singular and plural forms.")
            return String(format: str, abs(minutes))
        }
        else {
            return OBALoc("formatters.deviation.departs_future_on_time", value: "departs on time", comment: "Describes an on-time departure. e.g. departs on time.")
        }
    }

    /// Creates a formatted string from the `ArrivalDeparture` object that shows the short formatted time until this event occurs.
    ///
    /// For example, if the `ArrivalDeparture` happens 7 minutes in the future, this will return the string `"7m"`.
    /// 7 minutes in the past: `"-7m"`. If the `ArrivalDeparture` event occurs now, then this will return `"NOW"`.
    ///
    /// - Parameter arrivalDeparture: The event for which a formatted time distance is to be calculated.
    /// - Returns: The short formatted string representing the time until the `arrivalDeparture` event occurs.
    public func shortFormattedTime(until arrivalDeparture: ArrivalDeparture) -> String {
        switch arrivalDeparture.temporalState {
        case .present: return OBALoc("formatters.now", value: "NOW", comment: "Short formatted time text for arrivals/departures occurring now.")
        default:
            let formatString = OBALoc("formatters.short_time_fmt", value: "%dm", comment: "Short formatted time text for arrivals/departures. Example: 7m means that this event happens 7 minutes in the future. -7m means 7 minutes in the past.")
            return String(format: formatString, arrivalDeparture.arrivalDepartureMinutes)
        }
    }

    /// Creates a formatted string from the `ArrivalDeparture` object that shows the  formatted time until this event occurs.
    ///
    /// For example, if the `ArrivalDeparture` happens 7 minutes in the future, this will return the string `"7 minutes"`.
    /// 7 minutes in the past: `"-7 minutes"`. If the `ArrivalDeparture` event occurs now, then this will return `"NOW"`.
    /// Special casing is applied for times that occur -1/+1 minute from now: "One minute ago" and "One minute".
    /// This method is meant to be used as the value of `accessibilityLabel` properties, for instance, where the "m" suffix on
    /// `shortFormattedTime()` will be misinterpreted by VoiceOver.
    ///
    /// - Parameter arrivalDeparture: The event for which a formatted time distance is to be calculated.
    /// - Returns: The formatted string representing the time until the `arrivalDeparture` event occurs.
    public func formattedTime(until arrivalDeparture: ArrivalDeparture) -> String {
        switch (abs(arrivalDeparture.arrivalDepartureMinutes), arrivalDeparture.temporalState) {
        case (_, .present):
            return OBALoc("formatters.now", value: "NOW", comment: "Short formatted time text for arrivals/departures occurring now.")
        case (1, .past):
            return OBALoc("formatters.one_minute_ago", value: "One minute ago", comment: "Formatted time text for arrivals/departures that occurred one minute ago.")
        case (1, .future):
            return OBALoc("formatters.one_minute", value: "One minute", comment: "Formatted time text for arrivals/departures that occur in one minute.")
        default:
            let formatString = OBALoc("formatters.time_fmt", value: "%d minutes", comment: "Formatted time text for arrivals/departures. Used for accessibility labels, so be sure to spell out the word for 'minute'. Example: 7 minutes means that this event happens 7 minutes in the future. -7 minutes means 7 minutes in the past.")
            return String(format: formatString, arrivalDeparture.arrivalDepartureMinutes)
        }
    }

    /// Retrieves the appropriate background color for the passed-in `ScheduleStatus` value.
    /// - Parameter status: The schedule status to map to a color.
    /// - Returns: The background color corresponding to the passed-in status.
    public func backgroundColorForScheduleStatus(_ status: ScheduleStatus) -> UIColor {
        switch status {
        case .onTime: return themeColors.departureOnTimeBackground
        case .early: return themeColors.departureEarlyBackground
        case .delayed: return themeColors.departureLateBackground
        default: return themeColors.departureUnknownBackground
        }
    }

    /// Retrieves the appropriate color for the passed-in `ScheduleStatus` value.
    /// - Parameter status: The schedule status to map to a color.
    /// - Returns: The color corresponding to the passed-in status.
    public func colorForScheduleStatus(_ status: ScheduleStatus) -> UIColor {
        switch status {
        case .onTime: return themeColors.departureOnTime
        case .early: return themeColors.departureEarly
        case .delayed: return themeColors.departureLate
        default: return themeColors.departureUnknown
        }
    }

    // MARK: - Stops

    /// Generates a formatted title consisting of the stop name and direction.
    ///
    /// - Parameter stop: The `Stop` from which to generate a title.
    /// - Returns: A formatted title, including the stop's name and direction.
    public class func formattedTitle(stop: Stop) -> String {
        if let abbreviation = directionAbbreviation(stop.direction) {
            return "\(stop.name) (\(abbreviation))"
        }
        else {
            return stop.name
        }
    }

    public class func directionAbbreviation(_ direction: Direction) -> String? {
        switch direction {
        case .n: return OBALoc("formatters.cardinal_direction_abbrev.north", value: "N", comment: "Abbreviation for North")
        case .ne: return OBALoc("formatters.cardinal_direction_abbrev.northeast", value: "NE", comment: "Abbreviation for Northeast")
        case .e: return OBALoc("formatters.cardinal_direction_abbrev.east", value: "E", comment: "Abbreviation for East")
        case .se: return OBALoc("formatters.cardinal_direction_abbrev.southeast", value: "SE", comment: "Abbreviation for Southeast")
        case .s: return OBALoc("formatters.cardinal_direction_abbrev.south", value: "S", comment: "Abbreviation for South")
        case .sw: return OBALoc("formatters.cardinal_direction_abbrev.southwest", value: "SW", comment: "Abbreviation for Southwest")
        case .w: return OBALoc("formatters.cardinal_direction_abbrev.west", value: "W", comment: "Abbreviation for West")
        case .nw: return OBALoc("formatters.cardinal_direction_abbrev.northwest", value: "NW", comment: "Abbreviation for Northwest")
        case .unknown: return nil
        }
    }

    /// Creates a formatted string for a stop's stop ID/code plus direction (if available). e.g. "Stop #1234 — Southbound"
    ///
    /// - Parameter stop: The stop from which a formatted string will be created.
    /// - Returns: The formatted string representing code and direction.
    public class func formattedCodeAndDirection(stop: Stop) -> String {
        let formattedCode = formattedStopCode(stop: stop)

        if let adj = Formatters.adjectiveFormOfCardinalDirection(stop.direction) {
            return "\(formattedCode) — \(adj)"
        }
        else {
            return formattedCode
        }
    }

    /// Creates a formatted string for a stop's ID or code. e.g. "Stop #1234" or "Stop: 'Old Library'"
    ///
    /// - Parameter stop: The stop from which to generate a formatted stop code.
    /// - Returns: The formatted string, suitable for displaying to a user.
    public class func formattedStopCode(stop: Stop) -> String {
        let stopNumberFormat: String
        if stop.code.isNumeric {
            stopNumberFormat = OBALoc("formatters.stop.stop_code_numeric", value: "Stop #%@", comment: "Format string representing a numeric stop number. e.g. Stop #1234")
        }
        else {
            stopNumberFormat = OBALoc("formatters.stop.stop_code_non_numeric", value: "Stop: '%@'", comment: "Format string representing a non-numeric stop number. e.g. Stop: 'Old Library'")
        }

        return String(format: stopNumberFormat, stop.code)
    }

    // MARK: - Routes

    /// Generates a formatted, human readable list of routes.
    ///
    /// For example: "Routes: 10, 12, 49".
    ///
    /// - Parameter routes: An array of `Route`s from which the string will be generated.
    /// - Returns: A human-readable list of the passed-in `Route`s.s
    public class func formattedRoutes(_ routes: [Route]) -> String {
        let routeNames = routes.map { $0.shortName }
        let fmt = OBALoc("formatters.routes_label_fmt", value: "Routes: %@", comment: "A format string used to denote the list of routes served by this stop. e.g. 'Routes: 10, 12, 49'")
        return String(format: fmt, routeNames.joined(separator: ", "))
    }

    /// Returns an adjective form of the passed-in cardinal direction. For example `n` -> `Northbound`
    ///
    /// - Parameter direction: The cardinal direction
    /// - Returns: An adjective form of that direction
    public class func adjectiveFormOfCardinalDirection(_ direction: Direction) -> String? {
        switch direction {
        case .n: return OBALoc("formatters.cardinal_adjective.north", value: "Northbound", comment: "Headed in a northern direction")
        case .ne: return OBALoc("formatters.cardinal_adjective.northeast", value: "NE bound", comment: "Headed in a northeastern direction")
        case .e: return OBALoc("formatters.cardinal_adjective.east", value: "Eastbound", comment: "Headed in an eastern direction")
        case .se: return OBALoc("formatters.cardinal_adjective.southeast", value: "SE bound", comment: "Headed in an southeastern direction")
        case .s: return OBALoc("formatters.cardinal_adjective.south", value: "Southbound", comment: "Headed in a southern direction")
        case .sw: return OBALoc("formatters.cardinal_adjective.southwest", value: "SW bound", comment: "Headed in a southwestern direction")
        case .w: return OBALoc("formatters.cardinal_adjective.west", value: "Westbound", comment: "Headed in a western direction")
        case .nw: return OBALoc("formatters.cardinal_adjective.northwest", value: "NW bound", comment: "Headed in a northwestern direction")
        case .unknown: return nil
        }
    }

    // MARK: - Search

    /// Creates search bar placeholder text for the specified region. e.g. 'Search in Puget Sound'.
    /// - Parameter region: The region that will be specified in the placeholder text.
    public class func searchPlaceholderText(region: Region) -> String {
        let fmt = OBALoc("formatters.search_bar_placeholder_fmt", value: "Search in %@", comment: "Placeholder text for the search bar: 'Search in {REGION NAME}'")
        return String(format: fmt, region.name)
    }
}
