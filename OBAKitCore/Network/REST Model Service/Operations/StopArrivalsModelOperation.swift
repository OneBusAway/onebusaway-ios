//
//  StopArrivalsModelOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

/// Creates a `StopArrivals` model response to an API request to the `/api/where/arrivals-and-departures-for-stop/{id}.json` endpoint.
public class StopArrivalsModelOperation: RESTModelOperation {
    public private(set) var stopArrivals: StopArrivals?

    override public func main() {
        super.main()

        guard !hasError else {
            return
        }

        stopArrivals = decodeModels(type: StopArrivals.self).first
    }
}
