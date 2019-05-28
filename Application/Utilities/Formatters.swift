//
//  Formatters.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 12/11/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

@objc(OBAFormatters)
public class Formatters: NSObject {

    private let locale: Locale

    @objc public init(locale: Locale) {
        self.locale = locale
        super.init()
    }

    // MARK: - Formatted Times

    /// Converts a date into a human-readable time string that conforms to the user's locale.
    public lazy var timeFormatter: DateFormatter = {
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        timeFormatter.locale = locale

        return timeFormatter
    }()

    // MARK: - ArrivalDeparture

    /// Creates a string that explains when the `ArrivalDeparture` arrives or departs.
    ///
    /// For example, it might generate a string that says "Arrived 3 min ago", "Departing now", or "Departs in 8 min".
    ///
    /// - Parameter arrivalDeparture: The ArrivalDeparture object representing the string
    /// - Returns: A localized string explaining the arrival/departure status.
    public func explanation(from arrivalDeparture: ArrivalDeparture) -> String {
        let temporalState = arrivalDeparture.temporalStateOfArrivalDepartureDate
        let arrivalDepartureStatus = arrivalDeparture.arrivalDepartureStatus
        let apply: (String) -> String = { String(format: $0, abs(arrivalDeparture.arrivalDepartureMinutes)) }

        switch (temporalState, arrivalDepartureStatus) {
        case (.past, .arriving):
            return apply(NSLocalizedString("formatters.arrived_x_min_ago_fmt", value: "Arrived %d min ago", comment: "Use for vehicles that arrived X minutes ago."))
        case (.past, .departing):
            return apply(NSLocalizedString("formatters.departed_x_min_ago_fmt", value: "Departed %d min ago", comment: "Use for vehicles that departed X minutes ago."))
        case (.present, .arriving):
            return NSLocalizedString("formatters.arriving_now", value: "Arriving now", comment: "Use for vehicles arriving now.")
        case (.present, .departing):
            return NSLocalizedString("formatters.departing_now", value: "Departing now", comment: "Use for vehicles departing now.")
        case (.future, .arriving):
            return apply(NSLocalizedString("formatters.arrives_in_x_min_fmt", value: "Arrives in %d min", comment: "Use for vehicles arriving in X minutes."))
        case (.future, .departing):
            return apply(NSLocalizedString("formatters.departs_in_x_min_fmt", value: "Departs in %d min", comment: "Use for vehicles departing in X minutes."))
        }
    }
    
    // MARK: - Stops
    
    /// Generates a formatted title consisting of the stop name and direction.
    ///
    /// - Parameter stop: The `Stop` from which to generate a title.
    /// - Returns: A formatted title, including the stop's name and direction.
    public class func formattedTitle(stop: Stop) -> String {
        if let direction = stop.direction {
            return "\(stop.name) \(direction)"
        }
        else {
            return stop.name
        }
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
        let fmt = NSLocalizedString("formatters.routes_label_fmt", value: "Routes: %@", comment: "A format string used to denote the list of routes served by this stop. e.g. 'Routes: 10, 12, 49'")
        return String(format: fmt, routeNames.joined(separator: ", "))
    }

    /// Returns an adjective form of the passed-in cardinal direction. For example `n` -> `Northbound`
    ///
    /// - Parameter direction: The cardinal direction
    /// - Returns: An adjective form of that direction
    public class func adjectiveFormOfCardinalDirection(_ direction: String?) -> String? {
        guard let direction = direction else {
            return nil
        }

        switch direction.lowercased() {
        case "n": return NSLocalizedString("formatters.cardinal_adjective.north", value: "Northbound", comment: "Headed in a northern direction")
        case "e": return NSLocalizedString("formatters.cardinal_adjective.east", value: "Eastbound", comment: "Headed in an eastern direction")
        case "s": return NSLocalizedString("formatters.cardinal_adjective.south", value: "Southbound", comment: "Headed in a southern direction")
        case "w": return NSLocalizedString("formatters.cardinal_adjective.west", value: "Westbound", comment: "Headed in a western direction")
        default:
            let fmt = NSLocalizedString("formatters.cardinal_adjective.fallback_fmt", value: "%@ bound", comment: "Format string for a generic directional indicator. e.g. NW bound.")
            return String(format: fmt, direction)
        }
    }
}
