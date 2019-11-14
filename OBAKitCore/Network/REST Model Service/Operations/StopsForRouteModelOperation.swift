//
//  StopsForRouteModelOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/5/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

/// Creates a `StopsForRoute` model response to an API request to the `/api/where/stops-for-route/{id}.json` endpoint.
public class StopsForRouteModelOperation: RESTModelOperation {
    public private(set) var stopsForRoute: StopsForRoute?

    override public func main() {
        super.main()

        guard !hasError else {
            return
        }

        stopsForRoute = decodeModels(type: StopsForRoute.self).first
    }
}
