//
//  OnDemandCalendar.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// A service calendar in GOFS shape (wiki §2.4): active weekdays inside a date
/// range, minus explicit exceptions. Dates are service days in the agency's
/// time zone.
public struct OnDemandCalendar: Decodable, Identifiable, Hashable, Sendable {
    public let id: String
    public let days: [Weekday]
    public let startDate: ServiceDate
    public let endDate: ServiceDate
    public let exceptedDates: [ServiceDate]

    private enum CodingKeys: String, CodingKey {
        case id, days, startDate, endDate, exceptedDates
    }

    public init(id: String, days: [Weekday], startDate: ServiceDate, endDate: ServiceDate, exceptedDates: [ServiceDate]) {
        self.id = id
        self.days = days
        self.startDate = startDate
        self.endDate = endDate
        self.exceptedDates = exceptedDates
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        // A day name this build doesn't know is dropped rather than failing the
        // whole response; the calendar just has fewer active days.
        days = try container.decode([String].self, forKey: .days).compactMap(Weekday.init(rawValue:))
        startDate = try container.decode(ServiceDate.self, forKey: .startDate)
        endDate = try container.decode(ServiceDate.self, forKey: .endDate)
        exceptedDates = try container.decodeIfPresent([ServiceDate].self, forKey: .exceptedDates) ?? []
    }
}
