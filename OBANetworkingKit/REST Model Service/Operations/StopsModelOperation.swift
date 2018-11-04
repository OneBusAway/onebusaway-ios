//
//  StopsModelOperation.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 11/1/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class StopsModelOperation: RESTModelOperation {
    public private(set) var stops: [Stop] = []

    override public func main() {
        super.main()
        stops = decodeModels(type: Stop.self)
    }
}
