//
//  AlarmPushBody.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 9/12/19.
//

import Foundation
import OBAKitCore

/// Represent the body of a push notification for an alarm.
public struct AlarmPushBody: Codable {
    let tripID: TripIdentifier
    let stopID: StopID
    let regionID: Int
    let vehicleID: String
    let serviceDate: Date
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
        vehicleID = try container.decode(String.self, forKey: .vehicleID)
        serviceDate = try container.decode(Date.self, forKey: .serviceDate)
        stopSequence = try container.decode(Int.self, forKey: .stopSequence)
    }
}
