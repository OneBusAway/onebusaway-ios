//
//  FoundationExtensions.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 8/17/19.
//

import Foundation

// MARK: - Date

public extension Date {
    static func fromComponents(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) -> Date {
        let timeZone = TimeZone(secondsFromGMT: 0)
        let components = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: timeZone, era: nil, year: year, month: month, day: day, hour: hour, minute: minute, second: second, nanosecond: nil, weekday: nil, weekdayOrdinal: nil, quarter: nil, weekOfMonth: nil, weekOfYear: nil, yearForWeekOfYear: nil)
        return components.date!
    }
}

// MARK: - URL

public extension URLComponents {
    func queryItemValueMatching(name: String) -> String? {
        guard let queryItems = queryItems else {
            return nil
        }

        return queryItems.filter({$0.name == name}).first?.value
    }
}
