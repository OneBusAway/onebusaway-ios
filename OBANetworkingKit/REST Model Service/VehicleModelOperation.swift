//
//  VehicleModelOperation.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/18/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

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

        do {
            self.vehicles = try VehicleStatus.decodeEntries(entries)
        }
        catch {
            print("Unable to decode vehicle from data: \(error)")
        }
    }
}
