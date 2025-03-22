//
//  MockDataProvider.swift
//  OBAKit
//
//  Created by Prince Yadav on 09/03/25.
//


import Foundation
import Combine

class MockDataProvider {
    static let shared = MockDataProvider()
    
    private init() {}
    
    func provideMockStops() -> [Stop] {
        return Stop.examples
    }
    
    func provideMockArrivals() -> [Arrival] {
        return Arrival.examples
    }
    
    func fetchNearbyStops() -> AnyPublisher<[Stop], APIError> {
        return Just(Stop.examples)
            .setFailureType(to: APIError.self)
            .delay(for: .seconds(1), scheduler: RunLoop.main)
            .eraseToAnyPublisher()
    }
    
    func fetchArrivals(for stopId: String) -> AnyPublisher<[Arrival], APIError> {
        return Just(Arrival.examples)
            .setFailureType(to: APIError.self)
            .delay(for: .seconds(1), scheduler: RunLoop.main)
            .eraseToAnyPublisher()
    }
}

