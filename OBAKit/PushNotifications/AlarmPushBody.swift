//
//  AlarmPushBody.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// Represent the body of a push notification for an alarm.
public struct AlarmPushBody: Codable {
    let tripID: TripIdentifier
    let stopID: StopID
    let regionID: Int
    let vehicleID: String?
    let serviceDate: Date
    let serviceDateEpochTimestamp: Int64
    let stopSequence: Int

    private enum CodingKeys: String, CodingKey {
        case tripID = "trip_id"
        case stopID = "stop_id"
        case regionID = "region_id"
        case vehicleID = "vehicle_id"
        case serviceDate = "service_date"
        case stopSequence = "stop_sequence"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tripID = try container.decode(TripIdentifier.self, forKey: .tripID)
        stopID = try container.decode(StopID.self, forKey: .stopID)
        regionID = try container.decode(Int.self, forKey: .regionID)
        vehicleID = try container.decodeIfPresent(String.self, forKey: .vehicleID)
        serviceDateEpochTimestamp = try container.decode(Int64.self, forKey: .serviceDate)
        serviceDate = Date(timeIntervalSince1970: Double(serviceDateEpochTimestamp) / 1000)
        stopSequence = try container.decode(Int.self, forKey: .stopSequence)
    }
}
