//
//  StopsForRouteModelOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/5/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class StopsForRouteModelOperation: RESTModelOperation {
    public private(set) var stopsForRoute: StopsForRoute?

    override public func main() {
        super.main()
        stopsForRoute = decodeModels(type: StopsForRoute.self).first
    }
}
