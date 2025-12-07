//
//  ScheduleForRoute.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

// swiftlint:disable nesting

/// Retrieves a full schedule for a route for a particular day.
///
/// The schedule includes arrival/departure times for all stops along the route,
/// organized by direction of travel and trip.
public class ScheduleForRoute: NSObject, Identifiable, Decodable, HasReferences {
    public var id: String {
        return routeID
    }

    /// The route ID
    public let routeID: String

    /// The date for which the schedule applies (Unix timestamp in milliseconds)
    public let scheduleDate: Date

    /// Service IDs active on this date
    public let serviceIDs: [String]

    /// Groupings of stops and trips by direction
    public let stopTripGroupings: [StopTripGrouping]

    /// The route object, populated from references
    public private(set) var route: Route?

    /// Region identifier for reference loading
    public private(set) var regionIdentifier: Int?

    private enum CodingKeys: String, CodingKey {
        case routeID = "routeId"
        case scheduleDate
        case serviceIDs = "serviceIds"
        case stopTripGroupings
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        routeID = try container.decode(String.self, forKey: .routeID)

        // scheduleDate is in milliseconds since epoch
        let scheduleDateMs = try container.decode(Double.self, forKey: .scheduleDate)
        scheduleDate = Date(timeIntervalSince1970: scheduleDateMs / 1000.0)

        serviceIDs = try container.decode([String].self, forKey: .serviceIDs)
        stopTripGroupings = try container.decode([StopTripGrouping].self, forKey: .stopTripGroupings)
    }

    // MARK: - HasReferences

    public func loadReferences(_ references: References, regionIdentifier: Int?) {
        route = references.routeWithID(routeID)
        stopTripGroupings.loadReferences(references, regionIdentifier: regionIdentifier)
        self.regionIdentifier = regionIdentifier
    }

    // MARK: - Nested Types

    /// A grouping of stops and trips for a particular direction
    public class StopTripGrouping: NSObject, Decodable, HasReferences {
        /// The direction ID (e.g., "0" or "1")
        public let directionID: String

        /// The list of stop IDs in order for this direction
        public let stopIDs: [String]

        /// The headsigns for trips in this direction
        public let tripHeadsigns: [String]

        /// The trip IDs for this direction
        public let tripIDs: [String]

        /// Detailed stop time information for each trip
        public let tripsWithStopTimes: [TripWithStopTimes]

        /// Stops for this direction, populated from references
        public private(set) var stops: [Stop] = []

        /// Region identifier for reference loading
        public private(set) var regionIdentifier: Int?

        private enum CodingKeys: String, CodingKey {
            case directionID = "directionId"
            case stopIDs = "stopIds"
            case tripHeadsigns
            case tripIDs = "tripIds"
            case tripsWithStopTimes
        }

        public required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            directionID = try container.decode(String.self, forKey: .directionID)
            stopIDs = try container.decode([String].self, forKey: .stopIDs)
            tripHeadsigns = try container.decode([String].self, forKey: .tripHeadsigns)
            tripIDs = try container.decode([String].self, forKey: .tripIDs)
            tripsWithStopTimes = try container.decode([TripWithStopTimes].self, forKey: .tripsWithStopTimes)
        }

        public func loadReferences(_ references: References, regionIdentifier: Int?) {
            stops = references.stopsWithIDs(stopIDs)
            self.regionIdentifier = regionIdentifier
        }
    }

    /// A single trip with its stop times
    public class TripWithStopTimes: NSObject, Decodable {
        /// The trip ID
        public let tripID: String

        /// Stop times for this trip
        public let stopTimes: [RouteScheduleStopTime]

        private enum CodingKeys: String, CodingKey {
            case tripID = "tripId"
            case stopTimes
        }

        public required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            tripID = try container.decode(String.self, forKey: .tripID)
            stopTimes = try container.decode([RouteScheduleStopTime].self, forKey: .stopTimes)
        }
    }

    /// A single stop time entry in the route schedule
    public class RouteScheduleStopTime: NSObject, Decodable {
        /// The stop ID
        public let stopID: String

        /// The trip ID
        public let tripID: String

        /// Arrival time in seconds from midnight
        public let arrivalTime: Int

        /// Departure time in seconds from midnight
        public let departureTime: Int

        /// Whether arrival tracking is enabled
        public let arrivalEnabled: Bool

        /// Whether departure tracking is enabled
        public let departureEnabled: Bool

        /// The service ID (may be empty string)
        public let serviceID: String

        /// Stop headsign override (may be empty string)
        public let stopHeadsign: String

        private enum CodingKeys: String, CodingKey {
            case stopID = "stopId"
            case tripID = "tripId"
            case arrivalTime
            case departureTime
            case arrivalEnabled
            case departureEnabled
            case serviceID = "serviceId"
            case stopHeadsign
        }

        public required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            stopID = try container.decode(String.self, forKey: .stopID)
            tripID = try container.decode(String.self, forKey: .tripID)
            arrivalTime = try container.decode(Int.self, forKey: .arrivalTime)
            departureTime = try container.decode(Int.self, forKey: .departureTime)
            arrivalEnabled = try container.decode(Bool.self, forKey: .arrivalEnabled)
            departureEnabled = try container.decode(Bool.self, forKey: .departureEnabled)
            serviceID = try container.decodeIfPresent(String.self, forKey: .serviceID) ?? ""
            stopHeadsign = try container.decodeIfPresent(String.self, forKey: .stopHeadsign) ?? ""
        }

        /// Formats the arrival time as a Date using the provided schedule date as the base
        public func arrivalDate(for scheduleDate: Date) -> Date {
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: scheduleDate)
            return startOfDay.addingTimeInterval(TimeInterval(arrivalTime))
        }

        /// Formats the departure time as a Date using the provided schedule date as the base
        public func departureDate(for scheduleDate: Date) -> Date {
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: scheduleDate)
            return startOfDay.addingTimeInterval(TimeInterval(departureTime))
        }
    }
}

// swiftlint:enable nesting
