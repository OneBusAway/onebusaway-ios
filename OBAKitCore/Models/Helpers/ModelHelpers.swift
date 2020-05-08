//
//  ModelHelpers.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/21/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class ModelHelpers: NSObject {
    /// Converts empty string fields into `nil`s.
    ///
    /// There are some parts of the OneBusAway REST API that return empty strings
    /// where null would actually be a more appropriate value to provide. Alas,
    /// this will probably never change because of backwards compatibility concerns
    /// but that doesn't mean we can't address it here.
    ///
    /// - Parameter str: The string to inspect.
    /// - Returns: Nil if the string's character count is zero, and the string otherwise.
    public static func nilifyBlankValue(_ str: String?) -> String? {
        guard let str = str else {
            return nil
        }

        return str.count > 0 ? str : nil
    }

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
