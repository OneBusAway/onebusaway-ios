//
//  VehicleStatus.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/20/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CoreLocation

public class VehicleStatus: NSObject, Decodable {

    /// The id of the vehicle
    public let vehicleID: String

    /// The last known real-time update from the transit vehicle
    public let lastUpdateTime: Date?

    /// The last known real-time update from the transit vehicle containing a location update
    public let lastLocationUpdateTime: Date?

    /// The last known location of the vehicle
    public let location: CLLocation?

    /// The id of the vehicle's current trip, which can be used to look up the referenced `trip` element in the `references` section of the data.
    let tripID: String

    /// The vehicle's current trip
    public let trip: Trip

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

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let references = decoder.userInfo[CodingUserInfoKey.references] as! References

        vehicleID = try container.decode(String.self, forKey: .vehicleID)
        lastUpdateTime = try container.decode(Date.self, forKey: .lastUpdateTime)
        let updateTime = try container.decode(Date.self, forKey: .lastLocationUpdateTime)
        if updateTime == Date(timeIntervalSince1970: 0) {
            lastLocationUpdateTime = nil
        }
        else {
            lastLocationUpdateTime = updateTime
        }

        tripID = try container.decode(String.self, forKey: .tripID)
        trip = references.tripWithID(tripID)!

        phase = try container.decode(String.self, forKey: .phase)
        status = try container.decode(String.self, forKey: .status)
        location = try? CLLocation(container: container, key: .location)
        tripStatus = try container.decode(TripStatus.self, forKey: .tripStatus)
    }
}
