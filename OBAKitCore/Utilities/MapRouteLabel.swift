//
//  MapRouteLabel.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// The content of a stop's route label on the panel map: up to a few route
/// names, plus a count of the routes that didn't fit. Built by
/// `Formatters.mapRouteLabel(_:limit:)`.
///
/// The names are in the same order as everywhere else in the app
/// (`localizedStandardCompare`, so 65, 75, 372). This type carries no
/// accessibility text: the pin's own label already reads the full route list.
public struct MapRouteLabel: Equatable, Sendable {
    /// The route names to show, in display order.
    public let routeNames: [String]

    /// How many routes are left out of `routeNames`. Zero when all of them fit.
    public let overflowCount: Int

    /// The text of the trailing overflow segment, e.g. "+2", or `nil` when
    /// every route fits. The count uses the current locale's digits.
    public let overflowText: String?

    /// Every segment to draw, in order: the route names, then the overflow text.
    public let segments: [String]

    public init(routeNames: [String], overflowCount: Int) {
        self.routeNames = routeNames
        self.overflowCount = overflowCount
        if overflowCount > 0 {
            let fmt = OBALoc(
                "formatters.map_route_pill_overflow_fmt",
                value: "+%d",
                comment: "Last segment of a stop's route label on the map, counting the routes that didn't fit. The argument is the number of hidden routes. e.g. '+2' after '65 | 75 | 372'"
            )
            let text = String.localizedStringWithFormat(fmt, overflowCount)
            self.overflowText = text
            self.segments = routeNames + [text]
        } else {
            self.overflowText = nil
            self.segments = routeNames
        }
    }
}
