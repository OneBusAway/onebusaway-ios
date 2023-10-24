//
//  VehicleStatus.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation

public struct VehicleStatus: Identifiable, Codable, Hashable {
    public var id: String {
        return self.vehicleID
    }

    /// The id of the vehicle
    public let vehicleID: String

    /// The last known real-time update from the transit vehicle
    public let lastUpdateTime: Date?

    /// The last known real-time update from the transit vehicle containing a location update
    public let lastLocationUpdateTime: Date?

    /// The last known location of the vehicle
    public let location: CLLocation?

    /// The id of the vehicle's current trip, which can be used to look up the referenced `trip` element in the `references` section of the data.
    public let tripID: TripIdentifier?

    /// The vehicle's current trip
//    public private(set) var trip: Trip?

    /// the current journey phase of the vehicle
    public let phase: String

    /// status modifiers for the vehicle
    public let status: String

    /// Provides additional status information for the vehicle's trip.
    public let tripStatus: TripStatus

    private enum CodingKeys: String, CodingKey {
        case vehicleID = "vehicleId"
        case lastUpdateTime = "lastUpdateTime"
        case lastLocationUpdateTime = "lastLocationUpdateTime"
        case location = "location"
        case tripID = "tripId"
        case phase = "phase"
        case status = "status"
        case tripStatus = "tripStatus"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        vehicleID = try container.decode(String.self, forKey: .vehicleID)
        lastUpdateTime = try container.decode(Date.self, forKey: .lastUpdateTime)
        let updateTime = try container.decode(Date.self, forKey: .lastLocationUpdateTime)
        if updateTime == Date(timeIntervalSince1970: 0) {
            lastLocationUpdateTime = nil
        }
        else {
            lastLocationUpdateTime = updateTime
        }

        tripID = String.nilifyBlankValue(try container.decode(TripIdentifier.self, forKey: .tripID))

        phase = try container.decode(String.self, forKey: .phase)
        status = try container.decode(String.self, forKey: .status)
        location = try? CLLocation(container: container, key: .location)
        tripStatus = try container.decode(TripStatus.self, forKey: .tripStatus)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(vehicleID, forKey: .vehicleID)
        try container.encode(lastUpdateTime, forKey: .lastUpdateTime)
        try container.encode(lastLocationUpdateTime, forKey: .lastLocationUpdateTime)
        try container.encode(tripID, forKey: .tripID)
        try container.encode(phase, forKey: .phase)
        try container.encode(status, forKey: .status)
        try container.encode(location?.asOBALocationModel(), forKey: .location)
        try container.encode(tripStatus, forKey: .tripStatus)
    }
}
