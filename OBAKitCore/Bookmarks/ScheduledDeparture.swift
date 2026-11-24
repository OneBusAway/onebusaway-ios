//
//  ScheduledDeparture.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// One trip's time at a stop from the stop's printed timetable: what a
/// bookmark can still show offline once its saved real-time departures run out.
///
/// `@unchecked Sendable` for the same reason as `ArrivalDeparture`: `route` is
/// a decoded model that nothing changes once its references are loaded.
public struct ScheduledDeparture: Hashable, @unchecked Sendable {
    public let tripID: TripIdentifier
    public let routeID: RouteID
    public let tripHeadsign: String

    /// The route, from the timetable's references, for its color.
    public let route: Route?

    /// When the trip leaves the stop, or reaches it if the stop is drop-off only.
    public let date: Date

    public init(tripID: TripIdentifier, routeID: RouteID, tripHeadsign: String, route: Route?, date: Date) {
        self.tripID = tripID
        self.routeID = routeID
        self.tripHeadsign = tripHeadsign
        self.route = route
        self.date = date
    }

    /// Minutes from now, counted the way `ArrivalDeparture.arrivalDepartureMinutes`
    /// counts them, so a timetable row and a live row read the same.
    public var minutes: Int {
        Int(date.timeIntervalSinceNow / 60.0)
    }

    /// Whether this departure is for the trips `key` bookmarks.
    func matches(_ key: TripBookmarkKey) -> Bool {
        routeID == key.routeID && tripHeadsign == key.tripHeadsign
    }
}

extension ScheduleForStop {
    /// Every trip in this timetable, soonest first.
    public var scheduledDepartures: [ScheduledDeparture] {
        stopRouteSchedules.flatMap { routeSchedule in
            routeSchedule.stopRouteDirectionSchedules.flatMap { direction in
                direction.scheduleStopTimes.map { stopTime in
                    ScheduledDeparture(
                        tripID: stopTime.tripID,
                        routeID: routeSchedule.routeID,
                        tripHeadsign: direction.tripHeadsign,
                        route: routeSchedule.route,
                        date: stopTime.departureEnabled || !stopTime.arrivalEnabled ? stopTime.departureDate : stopTime.arrivalDate
                    )
                }
            }
        }
        .sorted { $0.date < $1.date }
    }
}
