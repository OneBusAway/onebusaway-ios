//
//  ModelService.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/9/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class ModelService: NSObject {
    let dataQueue: OperationQueue

    public init(dataQueue: OperationQueue) {
        self.dataQueue = dataQueue
    }

    func transferData(from service: Operation, to data: DataOperation) {
        let xfer = GenericTransferOperation(serviceOperation: service, dataOperation: data)

        xfer.addDependency(service)
        data.addDependency(xfer)

        dataQueue.addOperations([xfer, data], waitUntilFinished: false)
    }
}
