//
//  VehicleModelOperation.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/18/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CoreLocation

public class VehicleStatus: NSObject, Decodable {

    /// The id of the vehicle
    let vehicleID: String

    /// The last known real-time update from the transit vehicle
    let lastUpdateTime: Date?

    /// The last known real-time update from the transit vehicle containing a location update
    let lastLocationUpdateTime: Date?

    /// The last known location of the vehicle
    let location: CLLocation?

    /// The id of the vehicle's current trip, which can be used to look up the referenced `trip` element in the `references` section of the data.
    let tripID: String

    private enum CodingKeys: String, CodingKey {
        case vehicleID = "vehicleId"
        case lastUpdateTime = "lastUpdateTime"
        case lastLocationUpdateTime = "lastLocationUpdateTime"
        case location = "location"
        case tripID = "tripId"
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        vehicleID = try container.decode(String.self, forKey: .vehicleID)
        lastUpdateTime = try container.decode(Date.self, forKey: .lastUpdateTime)
        lastLocationUpdateTime = try container.decode(Date.self, forKey: .lastLocationUpdateTime)

        if let locationModel = try? container.decode(LocationModel.self, forKey: .location) {
            location = CLLocation(latitude: locationModel.latitude, longitude: locationModel.longitude)
        }
        else {
            location = nil
        }

        tripID = try container.decode(String.self, forKey: .tripID)
    }
}

private struct LocationModel: Codable {
    let latitude: Double
    let longitude: Double

    enum CodingKeys: String, CodingKey {
        case latitude = "lat"
        case longitude = "lon"
    }
}

@objc(OBAVehicleModelOperation)
public class VehicleModelOperation: Operation {
    public var apiOperation: RESTAPIOperation?
    public private(set) var vehicles: [VehicleStatus] = []

    override public func main() {
        guard
            let apiOperation = apiOperation,
            let entries = apiOperation.entries
        else {
            return
        }

        let decoder = DictionaryDecoder()
        self.vehicles = entries.compactMap { vehicleDict -> VehicleStatus? in
            do {
                return try decoder.decode(VehicleStatus.self, from: vehicleDict)
            }
            catch {
                print("Unable to decode vehicle from data: \(error)")
                return nil
            }
        }
    }
}
