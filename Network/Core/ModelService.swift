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

    func transferData(from serviceOperation: Operation, to dataOperation: Operation, transfer: @escaping () -> Void) {
        let transferOperation = BlockOperation(block: transfer)

        transferOperation.addDependency(serviceOperation)
        dataOperation.addDependency(transferOperation)

        dataQueue.addOperations([transferOperation, dataOperation], waitUntilFinished: false)
    }
}
