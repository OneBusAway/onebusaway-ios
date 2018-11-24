//
//  Operations.swift
//  OBAAppKit
//
//  Created by Aaron Brethorst on 11/21/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public extension Operation {
    /// A simple way to chain operations together.
    ///
    /// - Parameters:
    ///   - queue: The operation queue on which the passed-in block will execute.
    ///   - block: The block operation to perform when the receiver finishes executing.
    /// - Returns: The Operation form of the passed-in block, which is suitable for chaining.
    @discardableResult public func then(on queue: OperationQueue, block: @escaping () -> Void) -> Operation {
        let completion = BlockOperation(block: block)
        completion.addDependency(self)
        queue.addOperation(completion)
        return completion
    }

    /// A simple way to chain operations together. The passed-in block will be run on the main queue,
    /// which makes this method suitable for UI operations. 
    ///
    /// - Parameters:
    ///   - block: The block operation to perform when the receiver finishes executing.
    /// - Returns: The Operation form of the passed-in block, which is suitable for chaining.
    @discardableResult public func then(_ block: @escaping () -> Void) -> Operation {
        return then(on: OperationQueue.main, block: block)
    }
}
