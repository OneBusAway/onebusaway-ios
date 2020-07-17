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
    /// Converts a date that represents the 1970 epoch date to `nil`.
    ///
    /// - Parameter date: A date
    /// - Returns: Nil if the date was represented by the value `0` and the date otherwise.
    public static func nilifyEpochDate(_ date: Date) -> Date? {
        if date == Date(timeIntervalSince1970: 0) {
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
