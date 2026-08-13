//
//  TripAttributes.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import ActivityKit

// swiftlint:disable nesting

/// Live Activities data contract for trip bookmark tracking.
///
/// `ContentState` is the semantic wire contract with OBACloud: the server
/// pushes exactly this JSON shape (snake_case keys, epoch-second dates) via
/// APNs `content-state`, and the app builds the identical shape locally for
/// foreground refreshes. Apple decodes pushed content-state with a
/// default-strategy JSONDecoder, so every struct declares explicit
/// CodingKeys and dates travel as epoch-second integers, never `Date`.
/// The canonical fixture is OBAKitTests/fixtures/live_activity_content_state.json,
/// mirrored in the obacloud repo.
public struct TripAttributes: ActivityAttributes, Sendable {
    public struct StaticData: Codable, Hashable, Sendable {
        public let routeShortName: String
        public let routeHeadsign: String
        public let stopID: String
        public let routeColorHex: String?
        /// The region that hosts this stop, encoded in the widget URL so tapping
        /// the Live Activity opens the correct stop page.
        public let regionID: Int

        enum CodingKeys: String, CodingKey {
            case routeShortName, routeHeadsign, stopID, routeColorHex, regionID
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            routeShortName = try c.decode(String.self, forKey: .routeShortName)
            routeHeadsign = try c.decode(String.self, forKey: .routeHeadsign)
            stopID = try c.decode(String.self, forKey: .stopID)
            routeColorHex = try c.decodeIfPresent(String.self, forKey: .routeColorHex)
            regionID = (try? c.decode(Int.self, forKey: .regionID)) ?? 0
        }

        public init(routeShortName: String, routeHeadsign: String, stopID: String, routeColorHex: String? = nil, regionID: Int = 0) {
            self.routeShortName = routeShortName
            self.routeHeadsign = routeHeadsign
            self.stopID = stopID
            self.routeColorHex = routeColorHex
            self.regionID = regionID
        }
    }

    public struct ContentState: Codable, Hashable, Sendable {
        public enum ScheduleStatusValue: String, Codable, Hashable, Sendable {
            case onTime = "on_time"
            case early
            case delayed
            case unknown

            /// Bridges to the presentation enum used by Formatters.
            public var scheduleStatus: ScheduleStatus {
                switch self {
                case .onTime: return .onTime
                case .early: return .early
                case .delayed: return .delayed
                case .unknown: return .unknown
                }
            }

            public init(_ status: ScheduleStatus) {
                switch status {
                case .onTime: self = .onTime
                case .early: self = .early
                case .delayed: self = .delayed
                default: self = .unknown
                }
            }
        }

        public struct ArrivalInfo: Codable, Hashable, Sendable {
            /// Epoch seconds. An Int (not Date): the default JSONDecoder
            /// would decode a Date as seconds-since-2001 and corrupt it.
            public let departureTime: Int
            public let scheduleStatus: ScheduleStatusValue
            /// Seconds late (positive) or early (negative).
            public let scheduleDeviation: Int
            public let isArrival: Bool

            enum CodingKeys: String, CodingKey {
                case departureTime = "departure_time"
                case scheduleStatus = "schedule_status"
                case scheduleDeviation = "schedule_deviation"
                case isArrival = "is_arrival"
            }

            public init(departureTime: Int, scheduleStatus: ScheduleStatusValue, scheduleDeviation: Int, isArrival: Bool) {
                self.departureTime = departureTime
                self.scheduleStatus = scheduleStatus
                self.scheduleDeviation = scheduleDeviation
                self.isArrival = isArrival
            }

            public var departureDate: Date {
                Date(timeIntervalSince1970: TimeInterval(departureTime))
            }
        }

        /// Up to 3 upcoming arrivals, soonest first.
        public let arrivals: [ArrivalInfo]

        /// Arrivals whose departure time is at or after `now`, soonest first.
        /// Push updates and stale content states may include already-departed
        /// trips; use this for display rather than `arrivals` directly.
        public func upcomingArrivals(now: Date = Date()) -> [ArrivalInfo] {
            arrivals.filter { $0.departureDate >= now }
        }

        enum CodingKeys: String, CodingKey {
            case arrivals
        }

        public init(arrivals: [ArrivalInfo]) {
            self.arrivals = arrivals
        }
    }

    public let staticData: StaticData

    public init(staticData: StaticData) {
        self.staticData = staticData
    }
}

// swiftlint:enable nesting
