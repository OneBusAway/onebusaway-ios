//
//  Frequency.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/20/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

/// The `frequency` element captures information about a trip that uses frequency-based scheduling.
/// Frequency-based scheduling is where a trip doesn't have specifically scheduled stop times,
/// but instead just a headway specifying the frequency of service (ex. service every 10 minutes).
/// The frequency element can be a sub-element of `TripStatus` and `ArrivalAndDeparture`
public class Frequency: NSObject, Decodable {
    /// the start time when the frequency block starts
    public let startTime: Date

    /// the end time when the frequency block ends
    public let endTime: Date

    /// The frequency of service, in seconds
    public let headway: TimeInterval

    private enum CodingKeys: String, CodingKey {
        case startTime, endTime, headway
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        startTime = try container.decode(Date.self, forKey: .startTime)
        endTime = try container.decode(Date.self, forKey: .endTime)
        headway = try container.decode(TimeInterval.self, forKey: .headway)
    }
}
