//
//  TransferOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 6/11/19.
//

import Foundation

/// Internal `Operation` subclass used to shuttle data from a `RESTAPIOperation` to a `RESTModelOperation`.
///
/// This class checks to make sure that neither of its subordinate operations have been cancelled before transfering data
/// across, thereby helping to mitigate crashes.
class TransferOperation: Operation {
    private var serviceOperation: RESTAPIOperation?
    private var dataOperation: RESTModelOperation?

    required init(serviceOperation: RESTAPIOperation, dataOperation: RESTModelOperation) {
        self.serviceOperation = serviceOperation
        self.dataOperation = dataOperation
    }

    public override func main() {
        super.main()

        guard
            let serviceOperation = self.serviceOperation,
            let dataOperation = self.dataOperation,
            !serviceOperation.isCancelled,
            !dataOperation.isCancelled
        else {
            cancel()
            return
        }

        dataOperation.apiOperation = serviceOperation

        self.dataOperation = nil
        self.serviceOperation = nil
    }
}

public protocol APIAssignee {
    var apiOperation: Operation? { get set }
}

public typealias DataOperation = Operation & APIAssignee

class GenericTransferOperation: Operation {
    private let serviceOperation: Operation
    private var dataOperation: DataOperation

    init(serviceOperation: Operation, dataOperation: DataOperation) {
        self.serviceOperation = serviceOperation
        self.dataOperation = dataOperation
    }

    public override func main() {
        super.main()

        guard
            !serviceOperation.isCancelled,
            !dataOperation.isCancelled
            else {
                cancel()
                return
        }

        dataOperation.apiOperation = serviceOperation
    }
}
