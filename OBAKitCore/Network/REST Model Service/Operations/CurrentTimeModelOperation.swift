//
//  CurrentTimeModelOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/30/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class CurrentTimeModelOperation: RESTModelOperation {
    public private(set) var currentTime: Date?

    override public func main() {
        super.main()

        guard
            let apiOperation = apiOperation as? CurrentTimeOperation,
            let time = apiOperation.currentTime,
            !hasError
        else {
            return
        }

        currentTime = time
    }
}
