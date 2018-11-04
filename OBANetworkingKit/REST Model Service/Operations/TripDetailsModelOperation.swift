//
//  TripDetailsModelOperation.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/27/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

@objc(OBATripDetailsModelOperation)
public class TripDetailsModelOperation: RESTModelOperation {
    public private(set) var tripDetails: TripDetails?

    override public func main() {
        super.main()
        tripDetails = decodeModels(type: TripDetails.self).first
    }
}
