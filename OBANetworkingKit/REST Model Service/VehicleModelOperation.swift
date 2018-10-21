//
//  VehicleModelOperation.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/18/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

@objc(OBAVehicleModelOperation)
public class VehicleModelOperation: RESTModelOperation {
    public private(set) var vehicles: [VehicleStatus] = []

    override public func main() {
        super.main()

        if let entries = apiOperation?.entries {
            do {
                self.vehicles = try VehicleStatus.decodeEntries(entries)
            }
            catch {
                print("Unable to decode vehicle from data: \(error)")
            }
        }
    }
}
