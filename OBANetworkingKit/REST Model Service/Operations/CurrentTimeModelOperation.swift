//
//  CurrentTimeModelOperation.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/30/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

@objc(OBACurrentTimeModelOperation)
public class CurrentTimeModelOperation: RESTModelOperation {
    public private(set) var currentTime: Date?

    override public func main() {
        super.main()

        guard
            let apiOperation = apiOperation as? CurrentTimeOperation,
            let currentTime = apiOperation.currentTime
        else {
            return
        }

        self.currentTime = currentTime

        print("Here it is: \(currentTime)")
    }
}
