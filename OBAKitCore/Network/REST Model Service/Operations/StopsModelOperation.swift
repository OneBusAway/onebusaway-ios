//
//  StopsModelOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/1/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

/// Creates a `[Stop]` model response to an API request to the `/api/where/stops-for-location.json` endpoint.
public class StopsModelOperation: RESTModelOperation {
    public private(set) var stops: [Stop] = []

    override public func main() {
        super.main()

        guard !hasError else {
            return
        }

        stops = decodeModels(type: Stop.self)
        stops.loadReferences(references!)
    }
}
