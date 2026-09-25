//
//  GTFSTimeOfDay.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// A GTFS `"HH:MM:SS"` time of day, measured from the service-day anchor
/// (local noon minus twelve hours — see `BookingDeadlineEvaluator`). May exceed
/// `24:00:00`: the Alexandria feed accepts pickups until `24:50:00`.
///
/// `Int` on purpose, not `Int64`: seconds since midnight never approaches the
/// 32-bit limit that makes epoch values unsafe on `arm64_32` watches.
public struct GTFSTimeOfDay: Hashable, Comparable, Sendable, Decodable, CustomStringConvertible {
    public let seconds: Int

    public init(seconds: Int) {
        self.seconds = seconds
    }

    /// Parses `"H:MM:SS"` or `"HH:MM:SS"`; hours are unbounded, minutes and
    /// seconds must be `0...59`. Returns `nil` for anything else.
    public init?(_ string: String) {
        let parts = string.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let hours = Int(parts[0]), hours >= 0,
              let minutes = Int(parts[1]), (0..<60).contains(minutes),
              let seconds = Int(parts[2]), (0..<60).contains(seconds)
        else {
            return nil
        }
        self.seconds = hours * 3600 + minutes * 60 + seconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = GTFSTimeOfDay(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid GTFS time of day: \(raw)")
        }
        self = value
    }

    public static let midnight = GTFSTimeOfDay(seconds: 0)

    /// `24:00:00` — the wiki's default `endPickupTime` when a rule has none.
    public static let endOfServiceDay = GTFSTimeOfDay(seconds: 24 * 3600)

    public var description: String {
        String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }

    public static func < (lhs: GTFSTimeOfDay, rhs: GTFSTimeOfDay) -> Bool {
        lhs.seconds < rhs.seconds
    }
}
