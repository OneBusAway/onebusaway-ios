//
//  ReachabilityPublisher.swift
//  Hyperconnectivity
//
//  Created by Ross Butler on 08/05/2020.
//

import Combine
import Foundation

public struct ReachabilityPublisher: Publisher {
    
    // MARK: - Type Definitions
    public typealias Configuration = Hyperconnectivity.Configuration
    public typealias Failure = Never
    public typealias Output = ReachabilityResult
    
    // MARK: State
    private let configuration: Configuration
    
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration.cloneForReachability()
    }
    
    public func receive<S>(subscriber: S) where S : Subscriber, Self.Failure == S.Failure, Self.Output == S.Input {
        let subscription = ReachabilitySubscription(configuration: configuration, subscriber: subscriber)
        subscriber.receive(subscription: subscription)
    }
}
