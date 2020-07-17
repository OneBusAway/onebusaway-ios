//
//  Frequency.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
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

    // MARK: - Hashing and Equality

    public override func isEqual(_ object: Any?) -> Bool {
        guard let rhs = object as? Frequency else {
            return false
        }

        return
            startTime == rhs.startTime &&
            endTime == rhs.endTime &&
            headway == rhs.headway
    }

    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(startTime)
        hasher.combine(endTime)
        hasher.combine(headway)
        return hasher.finalize()
    }
}
