//
//  Publisher.swift
//  Hyperconnectivity
//
//  Created by Ross Butler on 07/05/2020.
//

import Combine
import Foundation

/// Publishes a `ConnectivityResult` on a background queue every time the network
/// path changes. Never completes; cancel the subscription to stop monitoring.
nonisolated struct ConnectivityPublisher: Publisher {

    // MARK: - Type Definitions
    typealias Configuration = Hyperconnectivity.Configuration
    typealias Failure = Never
    typealias Output = ConnectivityResult

    // MARK: State
    private let configuration: Configuration

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    func receive<S>(subscriber: S) where S: Subscriber, Self.Failure == S.Failure, Self.Output == S.Input {
        let subscription = ConnectivitySubscription(configuration: configuration, subscriber: subscriber)
        subscriber.receive(subscription: subscription)
    }
}
