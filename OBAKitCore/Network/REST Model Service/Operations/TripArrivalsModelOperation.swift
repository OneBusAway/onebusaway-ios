//
//  TripArrivalsModelOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/4/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class TripArrivalsModelOperation: RESTModelOperation {
    public private(set) var arrivalDeparture: ArrivalDeparture?

    override public func main() {
        super.main()

        guard !hasError else {
            return
        }

        arrivalDeparture = decodeModels(type: ArrivalDeparture.self).first
    }
}
