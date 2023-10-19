//
//  ModelHelpers.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

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
