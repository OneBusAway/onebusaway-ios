//
//  VehicleStatusModelOperation.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/18/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

@objc(OBAVehicleStatusModelOperation)
public class VehicleStatusModelOperation: RESTModelOperation {
    public private(set) var vehicles: [VehicleStatus] = []

    override public func main() {
        super.main()

        guard let entries = apiOperation?.entries else {
            return
        }

        do {
            self.vehicles = try DictionaryDecoder.decodeModels(entries, type: VehicleStatus.self)
        }
        catch {
            print("Unable to decode vehicle from data: \(error)")
        }
    }
}
