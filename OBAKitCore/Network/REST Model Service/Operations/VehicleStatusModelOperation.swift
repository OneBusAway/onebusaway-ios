//
//  VehicleStatusModelOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/18/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

/// Creates a `[VehicleStatus]` model response from a request to `/api/where/vehicle/{id}.json`.
public class VehicleStatusModelOperation: RESTModelOperation {
    public private(set) var vehicles: [VehicleStatus] = []

    override public func main() {
        super.main()

        guard !hasError else {
            return
        }

        vehicles = decodeModels(type: VehicleStatus.self)
    }
}
