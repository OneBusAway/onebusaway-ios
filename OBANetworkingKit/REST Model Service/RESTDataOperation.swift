//
//  RESTDataOperation.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/19/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class RESTDataOperation: OBAOperation {
    var apiOperation: RESTAPIOperation?

    func processData() {
        // nop. Should be overriden by subclasses.
    }

    override public func start() {
        super.start()

        precondition(apiOperation != nil)
        guard
            let apiOperation = apiOperation,
            !apiOperation.isCancelled
            else {
                cancel()
                return
        }

        guard !isCancelled else {
            return
        }

        processData()

        finish()
    }
}
