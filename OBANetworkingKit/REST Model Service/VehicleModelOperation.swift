//
//  VehicleModelOperation.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/18/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class Vehicle: NSObject, Codable {

}

@objc(OBAVehicleModelOperation)
public class VehicleModelOperation: Operation {
    public var apiOperation: RESTAPIOperation?
    public private(set) var vehicles: [Vehicle] = []

    override public func main() {
        guard
            let apiOperation = apiOperation,
            let entries = apiOperation.entries
        else {
            return
        }

        let decoder = DictionaryDecoder()
        self.vehicles = entries.compactMap { vehicleDict -> Vehicle? in
            do {
                return try decoder.decode(Vehicle.self, from: vehicleDict)
            }
            catch {
                print("Unable to decode vehicle from data: \(error)")
                return nil
            }
        }
    }
}
