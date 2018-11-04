//
//  StopArrivalsModelOperation.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 11/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class StopArrivalsModelOperation: RESTModelOperation {
    public private(set) var stopArrivals: StopArrivals?

    override public func main() {
        super.main()
        stopArrivals = decodeModels(type: StopArrivals.self).first

        if let references = references {
            stopArrivals?.loadReferences(references)
        }
    }
}
