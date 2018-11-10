//
//  AgencyVehicleModelOperation.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 11/10/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class AgencyVehicleModelOperation: Operation {
    var apiOperation: MatchingVehiclesOperation?
    public private(set) var matchingVehicles = [AgencyVehicle]()

    public override func main() {
        super.main()

        guard let data = apiOperation?.data else {
            return
        }

        let decoder = JSONDecoder()

        do {
            matchingVehicles = try decoder.decode([AgencyVehicle].self, from: data)
        }
        catch {
            print("unable to decode matching vehicles: \(error)")
        }
    }
}
