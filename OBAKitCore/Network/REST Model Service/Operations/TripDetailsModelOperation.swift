//
//  TripDetailsModelOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/27/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

/// Creates a `TripDetails` model response to a request to the  `/api/where/trip-details/{id}.json` endpoint.
public class TripDetailsModelOperation: RESTModelOperation {
    public private(set) var tripDetails: TripDetails?

    override public func main() {
        super.main()

        guard !hasError else {
            return
        }

        tripDetails = decodeModels(type: TripDetails.self).first
    }
}
