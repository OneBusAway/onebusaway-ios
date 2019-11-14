//
//  RouteSearchModelOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/5/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

/// Creates a `[Route]` model response to an API request to the `/api/where/routes-for-location.json` endpoint.
public class RouteSearchModelOperation: RESTModelOperation {
    public private(set) var routes = [Route]()

    override public func main() {
        super.main()

        guard !hasError else {
            return
        }

        routes = decodeModels(type: Route.self)
        routes.loadReferences(references!)
    }
}
