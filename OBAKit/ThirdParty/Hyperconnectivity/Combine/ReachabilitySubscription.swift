//
//  ReachabilitySubscription.swift
//  Hyperconnectivity
//
//  Created by Ross Butler on 08/05/2020.
//

import Foundation
import Combine

class ReachabilitySubscription<S: Subscriber>: Subscription where S.Input == ReachabilityResult, S.Failure == Never {
    private let configuration: Hyperconnectivity.Configuration
    private var connectivity: Hyperconnectivity?
    private var subscriber: S?

    init(configuration: Hyperconnectivity.Configuration, subscriber: S) {
        self.configuration = configuration.cloneForReachability()
        self.subscriber = subscriber
        startNotifier(with: subscriber)
    }

    func cancel() {
        stopNotifier()
    }

    func request(_: Subscribers.Demand) {}
}

private extension ReachabilitySubscription {
    
    private func startNotifier(with subscriber: S) {
        connectivity = Hyperconnectivity(configuration: configuration)
        let reachabilityChanged: (ReachabilityResult) -> Void = { reachability in
            _ = subscriber.receive(reachability)
        }
        connectivity?.reachabilityChanged = reachabilityChanged
        connectivity?.startNotifier()
    }
    
    private func stopNotifier() {
        connectivity?.stopNotifier()
        connectivity = nil
        subscriber?.receive(completion: Subscribers.Completion<Never>.finished)
        subscriber = nil
    }
}

