//
//  ModelHelpers.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MetaCodable

extension Date {
    /// Nullifies a Date if it is from before the specified `earlierDate`.
    class NillifyDate: HelperCoder {
        let cutoff: Date

        init(ifEarlierThan cutoff: Date) {
            self.cutoff = cutoff
        }

        func decode(from decoder: Decoder) throws -> Date {
            let date = try decoder.singleValueContainer().decode(Date.self)
            guard date > cutoff else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Date is earlier than the cutoff: \(cutoff)"))
            }

            return date
        }

        func decodeIfPresent(from decoder: Decoder) throws -> Date? {
            let date = try decoder.singleValueContainer().decode(Date.self)
            guard date > cutoff else {
                return nil
            }

            return date
        }
    }

    /// Decodes a date expressed in milliseconds since the 1970 epoch date.
    class EpochMilliseconds: HelperCoder {
        func decode(from decoder: Decoder) throws -> Date {
            let container = try decoder.singleValueContainer()
            let milliseconds = try container.decode(Double.self)

            return Date(timeIntervalSince1970: milliseconds / 1000)
        }

        func encode(_ value: Date, to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(value.timeIntervalSince1970 * 1000)
        }
    }
}

class ModelHelpers: NSObject {
    /// Converts a date from before the specified `earlierDate` to `nil`.
    /// 
    /// - Parameter date: A date
    /// - Parameter earlierDate: The lower bound for returning `date`.
    /// - Returns: `date` if date >= `earlierDate`; otherwise `nil`.
    public static func nilifyDate(_ date: Date, earlierThan earlierDate: Date) -> Date? {
        if date < earlierDate {
            return nil
        }
        else {
            return date
        }
    }

    /// Converts a date expressed in milliseonds since the 1970 epoch date to a `Date` object. Returns `nil` if `milliseconds == 0`.
    /// - Parameter milliseconds: The time interval in milliseconds
    /// - Returns: A `Date` object.
    public static func epochMillisecondsToDate(_ milliseconds: Double) -> Date? {
        guard milliseconds != 0 else {
            return nil
        }

        return Date(timeIntervalSince1970: (milliseconds / 1000.0))
    }
}
