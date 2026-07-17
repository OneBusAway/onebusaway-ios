//
//  Dispatch.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

// Derived from https://gist.github.com/fjcaetano/ff3e994c4edb4991ab8280f34994beb4

import Dispatch
import OBAKitCore

@MainActor private var throttleWorkItems = [AnyHashable: DispatchWorkItem]()
@MainActor private var lastDebounceCallTimes = [AnyHashable: DispatchTime]()
private let nilContext: AnyHashable = UInt32.random(in: UInt32.min...UInt32.max)

// These helpers are main-actor-only: they have only ever been used on
// `DispatchQueue.main` from UI code, and their debounce/throttle bookkeeping
// is main-actor state. Calling them on any other queue is unsupported.
public extension DispatchQueue {
    /**
     - parameters:
     - interval: The interval in which new calls will be ignored
     - context: The context in which the debounce should be executed
     - action: The closure to be executed
     Executes a closure and ensures no other executions will be made during the interval.
     */
    @MainActor func debounce(interval: Double, context: AnyHashable? = nil, action: @escaping @MainActor () -> Void) {
        assert(self === DispatchQueue.main, "debounce is main-queue-only; the dispatched block enters the main actor.")
        if let last = lastDebounceCallTimes[context ?? nilContext], last + interval > .now() {
            return
        }

        lastDebounceCallTimes[context ?? nilContext] = .now()
        async { MainActor.assumeIsolated(action) }

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
    @MainActor func throttle(deadline: DispatchTime, context: AnyHashable? = nil, action: @escaping @MainActor () -> Void) {
        assert(self === DispatchQueue.main, "throttle is main-queue-only; the dispatched block enters the main actor.")
        let worker = DispatchWorkItem {
            MainActor.assumeIsolated {
                defer { throttleWorkItems.removeValue(forKey: context ?? nilContext) }
                action()
            }
        }

        asyncAfter(deadline: deadline, execute: worker)

        throttleWorkItems[context ?? nilContext]?.cancel()
        throttleWorkItems[context ?? nilContext] = worker
    }
}
