//
//  Publisher.swift
//  Hyperconnectivity
//
//  Created by Ross Butler on 07/05/2020.
//

import Combine
import Foundation

public struct ConnectivityPublisher: Publisher {
    
    // MARK: - Type Definitions
    public typealias Configuration = Hyperconnectivity.Configuration
    public typealias Failure = Never
    public typealias Output = ConnectivityResult
    
    // MARK: State
    private let configuration: Configuration
    
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }
    
    public func receive<S>(subscriber: S) where S : Subscriber, Self.Failure == S.Failure, Self.Output == S.Input {
        let subscription = ConnectivitySubscription(configuration: configuration, subscriber: subscriber)
        subscriber.receive(subscription: subscription)
    }
}

