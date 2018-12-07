//
//  RouteSearchModelOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/5/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import OBAModelKit

public class RouteSearchModelOperation: RESTModelOperation {
    public private(set) var routes = [Route]()

    override public func main() {
        super.main()
        routes = decodeModels(type: Route.self)
        routes.loadReferences(references!)
    }
}
