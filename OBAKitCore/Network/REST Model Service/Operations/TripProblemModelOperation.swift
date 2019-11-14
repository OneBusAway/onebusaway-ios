//
//  TripProblemModelOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/5/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class TripProblemModelOperation: RESTModelOperation {
    public private(set) var success: Bool?

    override public func main() {
        super.main()

        guard
            !hasError,
            let response = apiOperation?.response
        else {
            success = false
            return
        }

        success = response.statusCode == 200
    }
}
