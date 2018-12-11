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
        guard
            let dir = direction?.lowercased(),
            ["n", "e", "s", "w"].contains(dir)
        else {
            return direction
        }

        switch dir {
        case "n": return NSLocalizedString("formatters.cardinal_adjective.north", value: "Northbound", comment: "Headed in a northern direction")
        case "e": return NSLocalizedString("formatters.cardinal_adjective.east", value: "Eastbound", comment: "Headed in an eastern direction")
        case "s": return NSLocalizedString("formatters.cardinal_adjective.south", value: "Southbound", comment: "Headed in a southern direction")
        case "w": return NSLocalizedString("formatters.cardinal_adjective.west", value: "Westbound", comment: "Headed in a western direction")
        default:  return direction
        }
    }
}
