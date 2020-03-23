//
//  Dispatch.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 1/13/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

// Derived from https://gist.github.com/fjcaetano/ff3e994c4edb4991ab8280f34994beb4

import Dispatch
import OBAKitCore

private var throttleWorkItems = [AnyHashable: DispatchWorkItem]()
private var lastDebounceCallTimes = [AnyHashable: DispatchTime]()
private let nilContext: AnyHashable = arc4random()

public extension DispatchQueue {
    /**
     - parameters:
     - interval: The interval in which new calls will be ignored
     - context: The context in which the debounce should be executed
     - action: The closure to be executed
     Executes a closure and ensures no other executions will be made during the interval.
     */
    func debounce(interval: Double, context: AnyHashable? = nil, action: @escaping VoidBlock) {
        if let last = lastDebounceCallTimes[context ?? nilContext], last + interval > .now() {
            return
        }

        lastDebounceCallTimes[context ?? nilContext] = .now()
        async(execute: action)

        // Cleanup & release context
        throttle(deadline: .now() + interval) {
            lastDebounceCallTimes.removeValue(forKey: context ?? nilContext)
        }
    }

    /**
     - parameters:
     - deadline: The timespan to delay a closure execution
     - context: The context in which the throttle should be executed
     - action: The closure to be executed
     Delays a closure execution and ensures no other executions are made during deadline
     */
    func throttle(deadline: DispatchTime, context: AnyHashable? = nil, action: @escaping VoidBlock) {
        let worker = DispatchWorkItem {
            defer { throttleWorkItems.removeValue(forKey: context ?? nilContext) }
            action()
        }

        asyncAfter(deadline: deadline, execute: worker)

        throttleWorkItems[context ?? nilContext]?.cancel()
        throttleWorkItems[context ?? nilContext] = worker
    }
}
