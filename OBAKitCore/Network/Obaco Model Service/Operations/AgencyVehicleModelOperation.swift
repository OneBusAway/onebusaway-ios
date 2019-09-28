//
//  AgencyVehicleModelOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/10/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CocoaLumberjackSwift

public class AgencyVehicleModelOperation: DataOperation {
    public var apiOperation: Operation?
    public private(set) var matchingVehicles = [AgencyVehicle]()

    public override func main() {
        super.main()

        guard
            let apiOperation = apiOperation as? MatchingVehiclesOperation,
            let data = apiOperation.data else {
            return
        }

        let decoder = JSONDecoder()

        do {
            matchingVehicles = try decoder.decode([AgencyVehicle].self, from: data)
        }
        catch {
            DDLogError("unable to decode matching vehicles: \(error)")
        }
    }
}
