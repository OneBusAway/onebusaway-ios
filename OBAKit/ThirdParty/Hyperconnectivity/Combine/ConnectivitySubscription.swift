//
//  Subscription.swift
//  Hyperconnectivity
//
//  Created by Ross Butler on 07/05/2020.
//

import Foundation
import Combine

protocol Connectivity {
    var connectivityChanged: Hyperconnectivity.ConnectivityChanged? { get set }
    init(configuration: Hyperconnectivity.Configuration)
    func startNotifier()
    func stopNotifier()
}

extension Hyperconnectivity: Connectivity {}

class ConnectivitySubscription<S: Subscriber>: Subscription where S.Input == ConnectivityResult, S.Failure == Never {
    private let configuration: Hyperconnectivity.Configuration
    private var connectivity: Connectivity?
    private var subscriber: S?

    init(configuration: Hyperconnectivity.Configuration, connectivity: Connectivity? = nil, subscriber: S) {
        self.configuration = configuration
        self.connectivity = connectivity
        self.subscriber = subscriber
        startNotifier(with: subscriber)
    }

    func cancel() {
        stopNotifier()
    }

    func request(_: Subscribers.Demand) {}
}

private extension ConnectivitySubscription {
    
    private func startNotifier(with subscriber: S) {
        connectivity = connectivity ?? Hyperconnectivity(configuration: configuration)
        let connectivityChanged: (ConnectivityResult) -> Void = { connectivity in
            _ = subscriber.receive(connectivity)
        }
        connectivity?.connectivityChanged = connectivityChanged
        connectivity?.startNotifier()
    }
    
    private func stopNotifier() {
        connectivity?.stopNotifier()
        connectivity = nil
        subscriber?.receive(completion: Subscribers.Completion<Never>.finished)
        subscriber = nil
    }
}
