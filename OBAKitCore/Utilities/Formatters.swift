//
//  Formatters.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
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

    public lazy var dateIntervalFormatter: DateIntervalFormatter = {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    public func formattedDateRange(_ interval: DateInterval) -> String? {
        return dateIntervalFormatter.string(from: interval)
    }

    public func formattedDateRange(from: Date, to: Date) -> String {
        return dateIntervalFormatter.string(from: from, to: to)
    }

    /// Creates formatted strings for time intervals.
    /// - Note: If you need strings for accessibility, use `accessibilityPositionalTimeFormatter`
    /// instead as `"15m"` is misinterpreted by VoiceOver as `"15 meters"`.
    public lazy var positionalTimeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.calendar = locale.calendar
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    /// Creates VoiceOver-friendly strings for time intervals.
    public lazy var accessibilityPositionalTimeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.calendar = locale.calendar
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .full
        return formatter
    }()

    // MARK: - ArrivalDeparture
    // MARK: Full attributed explanation
    public func fullAttributedExplanation(from arrivalDeparture: ArrivalDeparture) -> NSAttributedString {
        return fullAttributedArrivalDepartureExplanation(
            arrivalDepartureDate: arrivalDeparture.arrivalDepartureDate,
            scheduleStatus: arrivalDeparture.scheduleStatus,
            temporalState: arrivalDeparture.temporalState,
            arrivalDepartureStatus: arrivalDeparture.arrivalDepartureStatus,
            scheduleDeviationInMinutes: arrivalDeparture.deviationFromScheduleInMinutes)
    }

    public func fullAttributedArrivalDepartureExplanation(
        arrivalDepartureDate: Date,
        scheduleStatus: ScheduleStatus,
        temporalState: TemporalState,
        arrivalDepartureStatus: ArrivalDepartureStatus,
        scheduleDeviationInMinutes: Int) -> NSAttributedString {

        let arrDepTime = timeFormatter.string(from: arrivalDepartureDate)

        let explanationText: String
        if scheduleStatus == .unknown {
            explanationText = Strings.scheduledNotRealTime
        }
        else {
            explanationText = formattedScheduleDeviation(temporalState: temporalState, arrivalDepartureStatus: arrivalDepartureStatus, scheduleDeviation: scheduleDeviationInMinutes)
        }

        let scheduleStatusColor = colorForScheduleStatus(scheduleStatus)
        let timeExplanationFont = UIFont.preferredFont(forTextStyle: .footnote)

        let attributedExplanation = NSMutableAttributedString(
            string: "\(arrDepTime) - ",
            attributes: [NSAttributedString.Key.font: timeExplanationFont])

        let explanation = NSAttributedString(
            string: explanationText,
            attributes: [NSAttributedString.Key.font: timeExplanationFont,
                         NSAttributedString.Key.foregroundColor: scheduleStatusColor])

        attributedExplanation.append(explanation)

        return attributedExplanation
    }

    // MARK: Accessibility label
    /// Creates a localized string appropriate for using in UIAccessibility.accessibilityLabel. Example: "Route 49 - University District Broadway"
    public func accessibilityLabel(for arrivalDeparture: ArrivalDeparture) -> String {
        return accessibilityLabelForArrivalDeparture(routeAndHeadsign: arrivalDeparture.routeAndHeadsign)
    }

    /// Creates a localized string appropriate for using in UIAccessibility.accessibilityLabel. Example: "Route 49 - University District Broadway"
    public func accessibilityLabelForArrivalDeparture(routeAndHeadsign: String) -> String {
        return String(format: OBALoc("voiceover.arrivaldeparture_route_fmt", value: "Route %@", comment: "VoiceOver text describing the name of a route in a verbose fashion to compensate for no visuals."), routeAndHeadsign)
    }

    /// Creates a localized string appropriate for using in UIAccessibility.accessibilityValue.
    /// - Note: This does not include schedule deviation information.
    /// ## Examples
    /// - "arriving in 3 minutes at 9:57pm"
    /// - "scheduled to arrive in 3 minutes at 9:57pm"
    public func accessibilityValue(for arrivalDeparture: ArrivalDeparture) -> String {
        return accessibilityValueForArrivalDeparture(
            arrivalDepartureDate: arrivalDeparture.arrivalDepartureDate,
            arrivalDepartureMinutes: arrivalDeparture.arrivalDepartureMinutes,
            arrivalDepartureStatus: arrivalDeparture.arrivalDepartureStatus,
            temporalState: arrivalDeparture.temporalState,
            scheduleStatus: arrivalDeparture.scheduleStatus)
    }

    /// Creates a localized string appropriate for using in UIAccessibility.accessibilityValue.
    /// - Note: This does not include schedule deviation information.
    /// ## Examples
    /// - "arriving in 3 minutes at 9:57pm"
    /// - "scheduled to arrive in 3 minutes at 9:57pm"
    public func accessibilityValueForArrivalDeparture(arrivalDepartureDate: Date, arrivalDepartureMinutes: Int, arrivalDepartureStatus: ArrivalDepartureStatus, temporalState: TemporalState, scheduleStatus: ScheduleStatus) -> String {
        let arrDepTime = timeFormatter.string(from: arrivalDepartureDate)

        let apply: (String) -> String = { String(format: $0, abs(arrivalDepartureMinutes), arrDepTime) }

        let scheduleStatusString: String
        switch (arrivalDepartureStatus,
                temporalState,
                scheduleStatus == .unknown) {

        // Is a past event, regardless of realtime data availability.
        case (.arriving, .past, _):
            scheduleStatusString = apply(OBALoc("voiceover.arrivaldeparture_arrived_x_minutes_ago_fmt",
                                                value: "arrived %d minutes ago at %@.",
                                                comment: "VoiceOver text describing a route that has already arrived, regardless of realtime data availability."))

        case (.departing, .past, _):
            scheduleStatusString = apply(OBALoc("voiceover.arrivaldeparture_departed_x_minutes_ago_fmt",
                                                value: "departed %d minutes ago at %@.",
                                                comment: "VoiceOver text describing a route that has already departed, regardless of realtime data availability."))

        // Is a current event, regardless of realtime data availability.
        case (.arriving, .present, _):
            scheduleStatusString = OBALoc("voiceover.arrivaldeparture_arriving_now",
                                          value: "arriving now!",
                                          comment: "VoiceOver text describing a route that is arriving now, regardless of realtime data availability.")
        case (.departing, .present, _):
            scheduleStatusString = OBALoc("voiceover.arrivaldeparture_departing_now",
                                          value: "departing now!",
                                          comment: "VoiceOver text describing a route that is departing now, regardless of realtime data availability.")

        // Has realtime data and is a future event.
        case (.arriving, .future, false):
            scheduleStatusString = apply(OBALoc("voiceover.arrivaldeparture_arriving_in_x_minutes",
                                          value: "arriving in %d minutes at %@.",
                                          comment: "VoiceOver text describing a future arrival that is based off realtime data."))
        case (.departing, .future, false):
            scheduleStatusString = apply(OBALoc("voiceover.arrivaldeparture_departing_in_x_minutes_fmt",
                                          value: "departing in %d minutes at %@.",
                                          comment: "VoiceOver text describing a future departure that is based off realtime data."))

        // No realtime data and is a future event.
        case (.arriving, .future, true):
            scheduleStatusString = apply(OBALoc("voiceover.arrivaldeparture_scheduled_arrives_in_x_minutes_fmt",
                                          value: "scheduled to arrive in %d minutes at %@.",
                                          comment: "VoiceOver text describing a route that is scheduled to arrive (no realtime data was available)."))
        case (.departing, .future, true):
            scheduleStatusString = apply(OBALoc("voiceover.arrivaldeparture_scheduled_departs_in_x_minutes_fmt",
                                          value: "scheduled to depart in %d minutes at %@.",
                                          comment: "VoiceOver text describing a route that is scheduled to depart. (no realtime data was available)"))
        }

        return scheduleStatusString
    }

    /// Creates a string that explains when the `ArrivalDeparture` arrives or departs.
    /// For example, it might generate a string that says "Arrived 3 min ago", "Departing now", or "Departs in 8 min".
    ///
    /// - Parameter arrivalDeparture: The ArrivalDeparture object representing the string
    /// - Returns: A localized string explaining the arrival/departure status.
    public func explanation(from arrivalDeparture: ArrivalDeparture) -> String {
        return explanationForArrivalDeparture(tempuraState: arrivalDeparture.temporalState, arrivalDepartureStatus: arrivalDeparture.arrivalDepartureStatus, arrivalDepartureMinutes: arrivalDeparture.arrivalDepartureMinutes)
    }

    /// Creates a string that explains when the `ArrivalDeparture` arrives or departs.
    /// For example, it might generate a string that says "Arrived 3 min ago", "Departing now", or "Departs in 8 min".
    ///
    /// - Returns: A localized string explaining the arrival/departure status.
    public func explanationForArrivalDeparture(tempuraState: TemporalState, arrivalDepartureStatus: ArrivalDepartureStatus, arrivalDepartureMinutes: Int) -> String {
        let apply: (String) -> String = { String(format: $0, abs(arrivalDepartureMinutes)) }

        switch (tempuraState, arrivalDepartureStatus) {
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
        return formattedScheduleDeviation(temporalState: arrivalDeparture.temporalState, arrivalDepartureStatus: arrivalDeparture.arrivalDepartureStatus, scheduleDeviation: arrivalDeparture.deviationFromScheduleInMinutes)
    }

    public func formattedScheduleDeviation(temporalState: TemporalState, arrivalDepartureStatus: ArrivalDepartureStatus, scheduleDeviation: Int) -> String {
        switch (temporalState, arrivalDepartureStatus) {
        case (.past, .arriving):
            return explanationOfDeviationForPastArrival(minutes: scheduleDeviation)
        case (.past, .departing):
            return explanationOfDeviationForPastDeparture(minutes: scheduleDeviation)
        case (_, .arriving):
            return explanationOfDeviationForFutureArrival(minutes: scheduleDeviation)
        case (_, .departing):
            fallthrough // swiftlint:disable:this no_fallthrough_only
        default:
            return explanationOfDeviationForFutureDeparture(minutes: scheduleDeviation)
        }
    }

    private func explanationOfDeviationForPastArrival(minutes: Int) -> String {
        if minutes > 0 {
            let str = OBALoc("formatters.deviation.arrival_past_late_fmt", value: "arrived %d min late", comment: "Format string for describing a late arrival schedule deviation. e.g. Arrived 3 min late. Note that the abbrevation for 'minutes' should make sense for both singular and plural forms.")
            return String(format: str, minutes)
        }
        else if minutes < 0 {
            let str = OBALoc("formatters.deviation.arrival_past_early_fmt", value: "arrived %d min early", comment: "Format string for describing an early arrival schedule deviation. e.g. Arrived 3 min early. Note that the abbrevation for 'minutes' should make sense for both singular and plural forms.")
            return String(format: str, abs(minutes))
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
            return String(format: str, abs(minutes))
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
            return String(format: str, abs(minutes))
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
        return shortFormattedTime(untilMinutes: arrivalDeparture.arrivalDepartureMinutes, temporalState: arrivalDeparture.temporalState)
    }

    /// Creates a formatted string from the `ArrivalDeparture` object that shows the short formatted time until this event occurs.
    ///
    /// For example, if the `ArrivalDeparture` happens 7 minutes in the future, this will return the string `"7m"`.
    /// 7 minutes in the past: `"-7m"`. If the `ArrivalDeparture` event occurs now, then this will return `"NOW"`.
    ///
    /// - Returns: The short formatted string representing the time until the `arrivalDeparture` event occurs.
    public func shortFormattedTime(untilMinutes: Int, temporalState: TemporalState) -> String {
        switch temporalState {
        case .present: return OBALoc("formatters.now", value: "NOW", comment: "Short formatted time text for arrivals/departures occurring now.")
        default:
            let formatString = OBALoc("formatters.short_time_fmt", value: "%dm", comment: "Short formatted time text for arrivals/departures. Example: 7m means that this event happens 7 minutes in the future. -7m means 7 minutes in the past.")
            return String(format: formatString, untilMinutes)
        }
    }

    private lazy var relativeDateTimeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.locale = locale
        return f
    }()

    /// Creates a string that describes the time since `date`.
    ///
    /// Pass in a date that is less than 5 seconds old, and it will return "Just Now".
    /// Pass in a date older than that, and it will return a string like "31 seconds ago".
    ///
    /// - Parameter date: The date to calculate the time ago in words from.
    /// - Returns: A human-readable, localized representation of the time ago in words.
    public func timeAgoInWords(date: Date) -> String {
        if abs(date.timeIntervalSinceNow) < 5 {
            return OBALoc("formatters.time_ago_just_now", value: "Just Now", comment: "Indicates that an event just took place.")
        }

        return relativeDateTimeFormatter.localizedString(for: date, relativeTo: Date())
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
        return formattedTimeUntilArrivalDeparture(arrivalDepartureMinutes: arrivalDeparture.arrivalDepartureMinutes, temporalState: arrivalDeparture.temporalState)
    }

    /// Creates a formatted string from the `ArrivalDeparture` object that shows the  formatted time until this event occurs.
    ///
    /// For example, if the `ArrivalDeparture` happens 7 minutes in the future, this will return the string `"7 minutes"`.
    /// 7 minutes in the past: `"-7 minutes"`. If the `ArrivalDeparture` event occurs now, then this will return `"NOW"`.
    /// Special casing is applied for times that occur -1/+1 minute from now: "One minute ago" and "One minute".
    /// This method is meant to be used as the value of `accessibilityLabel` properties, for instance, where the "m" suffix on
    /// `shortFormattedTime()` will be misinterpreted by VoiceOver.
    ///
    /// - Returns: The formatted string representing the time until the `arrivalDeparture` event occurs.
    public func formattedTimeUntilArrivalDeparture(arrivalDepartureMinutes: Int, temporalState: TemporalState) -> String {
        switch (abs(arrivalDepartureMinutes), temporalState) {
        case (_, .present):
            return OBALoc("formatters.now", value: "NOW", comment: "Short formatted time text for arrivals/departures occurring now.")
        case (1, .past):
            return OBALoc("formatters.one_minute_ago", value: "One minute ago", comment: "Formatted time text for arrivals/departures that occurred one minute ago.")
        case (1, .future):
            return OBALoc("formatters.one_minute", value: "One minute", comment: "Formatted time text for arrivals/departures that occur in one minute.")
        default:
            let formatString = OBALoc("formatters.time_fmt", value: "%d minutes", comment: "Formatted time text for arrivals/departures. Used for accessibility labels, so be sure to spell out the word for 'minute'. Example: 7 minutes means that this event happens 7 minutes in the future. -7 minutes means 7 minutes in the past.")
            return String(format: formatString, arrivalDepartureMinutes)
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

    /// Creates a string suitable for use as an accessibility label for a stop annotation view on the map.
    /// - Parameter stop: The `Stop` object to generate an accessibility label from.
    /// - Returns: A localized string.
    public class func formattedAccessibilityLabel(stop: Stop) -> String {
        var parts = [stop.name]

        if let direction = directionString(stop.direction) {
            parts.append(direction)
        }

        // TODO: This
//        if let routes = Formatters.formattedRoutes(stop.routes) {
//            parts.append(routes)
//        }

        let fmt = OBALoc("formatters.stop_id_fmt", value: "Stop ID: %@", comment: "A string that prefixes a stop ID to tell the user what that value is.")
        parts.append(String(format: fmt, stop.code))

        return parts.joined(separator: "; ")
    }

    /// Provides the a localized string representing the cardinal direction that is passed in. For example, `.n` returns `"North"`.
    /// - Parameter direction: The direction enum value.
    /// - Returns: A localized string representing the direction.
    public class func directionString(_ direction: Stop.Direction) -> String? {
        switch direction {
        case .n: return OBALoc("formatters.cardinal_direction.north", value: "North", comment: "North Direction")
        case .ne: return OBALoc("formatters.cardinal_direction.northeast", value: "Northeast", comment: "Northeast Direction")
        case .e: return OBALoc("formatters.cardinal_direction.east", value: "East", comment: "East Direction")
        case .se: return OBALoc("formatters.cardinal_direction.southeast", value: "Southeast", comment: "Southeast Direction")
        case .s: return OBALoc("formatters.cardinal_direction.south", value: "South", comment: "South Direction")
        case .sw: return OBALoc("formatters.cardinal_direction.southwest", value: "Southwest", comment: "Southwest Direction")
        case .w: return OBALoc("formatters.cardinal_direction.west", value: "West", comment: "West Direction")
        case .nw: return OBALoc("formatters.cardinal_direction.northwest", value: "Northwest", comment: "Northwest Direction")
        case .unknown: return nil
        }
    }

    /// Provides an abbreviation of the cardinal direction that is passed in. For example, `.n` returns `"N"`.
    /// - Parameter direction: The direction enum value.
    /// - Returns: A localized string representing the direction.
    public class func directionAbbreviation(_ direction: Stop.Direction) -> String? {
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
    /// For example: "Routes: 10, 12, 49, + 3 more".
    ///
    /// - Parameter routes: An array of `Route`s from which the string will be generated.
    /// - Parameter limit: The number of `Route`s that be displayed in the returned string. By default, this is `Int.max`.
    /// - Returns: A human-readable list of the passed-in `Route`s.
    public class func formattedRoutes(_ routes: [Route], limit: Int = .max) -> String? {
        guard routes.count > 0 else { return nil }

        var routeNames = routes
            .map { $0.shortName }
            .filter { !$0.isEmpty && $0.count > 0 } // Some agencies may not provide a shortName (i.e. Washington State Ferries in Puget Sound)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        // If we don't have any shortNames (as is the case with WA State Ferries), then use route types instead.
        if routeNames.count == 0 {
            routeNames = routes.map { $0.routeType }.uniqued.compactMap { routeTypeToString($0) }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }

        guard !routeNames.isEmpty else {
            return nil
        }

        if routeNames.count > limit {
            let fmt = OBALoc("formatters.routes_label_plus_more_fmt", value: "Routes: %@, + %d more", comment: "A format string used to denote the overflowing list of routes served by this stop. e.g. 'Routes: 10, 12, 49, + 3 more")
            let shortList = routeNames.prefix(limit).joined(separator: ", ")
            let overflowCount = routeNames.count - limit
            return String(format: fmt, shortList, overflowCount)
        }
        else {
            let fmt = OBALoc("formatters.routes_label_fmt", value: "Routes: %@", comment: "A format string used to denote the list of routes served by this stop. e.g. 'Routes: 10, 12, 49'")
            return String(format: fmt, routeNames.joined(separator: ", "))
        }
    }

    /// Returns a localized, human-readable string representation of the passed-in route type value.
    /// - Parameter routeType: A route type, like train, light rail, or bus.
    public class func routeTypeToString(_ routeType: Route.RouteType) -> String? {
        switch routeType {
        case .lightRail:
            return OBALoc("route_type.light_rail", value: "Light Rail", comment: "Tram, Streetcar, Light rail. Any light rail or street level system within a metropolitan area.")
        case .subway:
            return OBALoc("route_type.subway", value: "Subway", comment: "Subway, Metro. Any underground rail system within a metropolitan area.")
        case .rail:
            return OBALoc("route_type.rail", value: "Rail", comment: "Rail. Used for intercity or long-distance travel.")
        case .bus:
            return OBALoc("route_type.bus", value: "Bus", comment: "Bus. Used for short- and long-distance bus routes.")
        case .ferry:
            return OBALoc("route_type.ferry", value: "Ferry", comment: "Ferry. Used for short- and long-distance boat service.")
        case .cableCar:
            return OBALoc("route_type.cable_car", value: "Cable Car", comment: "Cable car. Used for street-level cable cars where the cable runs beneath the car.")
        case .gondola:
            return OBALoc("route_type.gondola", value: "Gondola", comment: "Gondola, Suspended cable car. Typically used for aerial cable cars where the car is suspended from the cable.")
        case .funicular:
            return OBALoc("route_type.funicular", value: "Funicular", comment: "Funicular. Any rail system designed for steep inclines.")
        default:
            return nil
        }
    }

    /// Generates an alphabetical-ordered, formatted, human readable unique list of agencies.
    ///
    /// For example: "Community Transit, Sound Transit".
    ///
    /// - Parameter routes: An array of `Route`s from which the string will be generated.
    /// - Returns: A human-readable list of the passed-in `Route`s.
    public class func formattedAgenciesForRoutes(_ routes: [Route]) -> String {
        return routes
            .compactMap { $0.agencyID } // TODO: check me before merge!
            .uniqued
            .sorted()
            .joined(separator: ", ")
    }

    /// Returns an adjective form of the passed-in cardinal direction. For example `n` -> `Northbound`
    ///
    /// - Parameter direction: The cardinal direction
    /// - Returns: An adjective form of that direction
    public class func adjectiveFormOfCardinalDirection(_ direction: Stop.Direction) -> String? {
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
