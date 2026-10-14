//
//  ServiceDate.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// A calendar date in the agency's service-day sense (`"YYYY-MM-DD"` on the
/// wire). Deliberately not a `Date`: a service day has no instant until it is
/// anchored in a time zone by `BookingDeadlineEvaluator`.
public struct ServiceDate: Hashable, Comparable, Sendable, Decodable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses exactly `"YYYY-MM-DD"`.
    public init?(_ string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day)
        else {
            return nil
        }
        self.init(year: year, month: month, day: day)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = ServiceDate(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid service date: \(raw)")
        }
        self = value
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: ServiceDate, rhs: ServiceDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

/// The `days` vocabulary of an on-demand calendar (wiki §2.4).
public enum Weekday: String, CaseIterable, Sendable {
    case mon, tue, wed, thu, fri, sat, sun

    /// `Calendar.component(.weekday, from:)` order: 1 = Sunday … 7 = Saturday.
    private static let calendarOrder: [Weekday] = [.sun, .mon, .tue, .wed, .thu, .fri, .sat]

    /// Out-of-range numbers read as Saturday.
    public init(calendarWeekday: Int) {
        let index = calendarWeekday - 1
        self = Self.calendarOrder.indices.contains(index) ? Self.calendarOrder[index] : .sat
    }

    public var calendarWeekday: Int {
        Self.calendarOrder.firstIndex(of: self)! + 1
    }
}
