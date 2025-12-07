//
//  ScheduleForStop.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

// swiftlint:disable nesting

/// Retrieves the full schedule for a stop on a particular day.
///
/// The schedule includes all arrival/departure times for all routes serving the stop,
/// organized by route and direction.
public class ScheduleForStop: NSObject, Identifiable, Decodable, HasReferences {
    public var id: String {
        return stopID
    }

    /// The stop ID
    public let stopID: String

    /// The date for which the schedule applies (Unix timestamp in milliseconds converted to Date)
    public let date: Date

    /// Schedules organized by route
    public let stopRouteSchedules: [StopRouteSchedule]

    /// The stop object, populated from references
    public private(set) var stop: Stop?

    /// Region identifier for reference loading
    public private(set) var regionIdentifier: Int?

    private enum CodingKeys: String, CodingKey {
        case stopID = "stopId"
        case date
        case stopRouteSchedules
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        stopID = try container.decode(String.self, forKey: .stopID)

        // date is in milliseconds since epoch
        let dateMs = try container.decode(Double.self, forKey: .date)
        date = Date(timeIntervalSince1970: dateMs / 1000.0)

        stopRouteSchedules = try container.decode([StopRouteSchedule].self, forKey: .stopRouteSchedules)
    }

    // MARK: - HasReferences

    public func loadReferences(_ references: References, regionIdentifier: Int?) {
        stop = references.stopWithID(stopID)
        stopRouteSchedules.loadReferences(references, regionIdentifier: regionIdentifier)
        self.regionIdentifier = regionIdentifier
    }

    // MARK: - Nested Types

    /// Schedule for a single route at the stop
    public class StopRouteSchedule: NSObject, Decodable, HasReferences {
        /// The route ID
        public let routeID: String

        /// Schedules organized by direction
        public let stopRouteDirectionSchedules: [StopRouteDirectionSchedule]

        /// The route object, populated from references
        public private(set) var route: Route?

        /// Region identifier for reference loading
        public private(set) var regionIdentifier: Int?

        private enum CodingKeys: String, CodingKey {
            case routeID = "routeId"
            case stopRouteDirectionSchedules
        }

        public required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            routeID = try container.decode(String.self, forKey: .routeID)
            stopRouteDirectionSchedules = try container.decode([StopRouteDirectionSchedule].self, forKey: .stopRouteDirectionSchedules)
        }

        public func loadReferences(_ references: References, regionIdentifier: Int?) {
            route = references.routeWithID(routeID)
            self.regionIdentifier = regionIdentifier
        }
    }

    /// Schedule for a single direction of a route at the stop
    public class StopRouteDirectionSchedule: NSObject, Decodable {
        /// The headsign for this direction
        public let tripHeadsign: String

        /// Frequency-based schedule entries (if applicable)
        public let scheduleFrequencies: [ScheduleFrequency]

        /// Individual stop times
        public let scheduleStopTimes: [StopScheduleStopTime]

        private enum CodingKeys: String, CodingKey {
            case tripHeadsign
            case scheduleFrequencies
            case scheduleStopTimes
        }

        public required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            tripHeadsign = try container.decode(String.self, forKey: .tripHeadsign)
            scheduleFrequencies = try container.decodeIfPresent([ScheduleFrequency].self, forKey: .scheduleFrequencies) ?? []
            scheduleStopTimes = try container.decode([StopScheduleStopTime].self, forKey: .scheduleStopTimes)
        }
    }

    /// A single stop time entry in the stop schedule
    public class StopScheduleStopTime: NSObject, Decodable {
        /// The trip ID
        public let tripID: String

        /// The service ID
        public let serviceID: String

        /// Arrival time as Unix timestamp in milliseconds
        public let arrivalTime: Int64

        /// Departure time as Unix timestamp in milliseconds
        public let departureTime: Int64

        /// Whether arrival tracking is enabled
        public let arrivalEnabled: Bool

        /// Whether departure tracking is enabled
        public let departureEnabled: Bool

        /// Stop headsign override (may be empty string)
        public let stopHeadsign: String

        private enum CodingKeys: String, CodingKey {
            case tripID = "tripId"
            case serviceID = "serviceId"
            case arrivalTime
            case departureTime
            case arrivalEnabled
            case departureEnabled
            case stopHeadsign
        }

        public required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            tripID = try container.decode(String.self, forKey: .tripID)
            serviceID = try container.decode(String.self, forKey: .serviceID)
            arrivalTime = try container.decode(Int64.self, forKey: .arrivalTime)
            departureTime = try container.decode(Int64.self, forKey: .departureTime)
            arrivalEnabled = try container.decode(Bool.self, forKey: .arrivalEnabled)
            departureEnabled = try container.decode(Bool.self, forKey: .departureEnabled)
            stopHeadsign = try container.decodeIfPresent(String.self, forKey: .stopHeadsign) ?? ""
        }

        /// The arrival time as a Date
        public var arrivalDate: Date {
            return Date(timeIntervalSince1970: Double(arrivalTime) / 1000.0)
        }

        /// The departure time as a Date
        public var departureDate: Date {
            return Date(timeIntervalSince1970: Double(departureTime) / 1000.0)
        }
    }

    /// Frequency-based schedule entry (for routes that run at regular intervals)
    public class ScheduleFrequency: NSObject, Decodable {
        /// Start time as Unix timestamp in milliseconds
        public let startTime: Int64

        /// End time as Unix timestamp in milliseconds
        public let endTime: Int64

        /// Headway in seconds between departures
        public let headway: Int

        private enum CodingKeys: String, CodingKey {
            case startTime
            case endTime
            case headway
        }

        public required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            startTime = try container.decode(Int64.self, forKey: .startTime)
            endTime = try container.decode(Int64.self, forKey: .endTime)
            headway = try container.decode(Int.self, forKey: .headway)
        }

        /// The start time as a Date
        public var startDate: Date {
            return Date(timeIntervalSince1970: Double(startTime) / 1000.0)
        }

        /// The end time as a Date
        public var endDate: Date {
            return Date(timeIntervalSince1970: Double(endTime) / 1000.0)
        }
    }
}

// swiftlint:enable nesting
