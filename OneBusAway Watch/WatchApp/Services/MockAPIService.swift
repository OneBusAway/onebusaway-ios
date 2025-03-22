//
//  MockAPIService.swift
//  OBAKit
//
//  Created by Prince Yadav on 09/03/25.
//


import Foundation
import Combine

class MockAPIService: APIServiceProtocol {
    func fetchNearbyStops(latitude: Double, longitude: Double) -> AnyPublisher<[Stop], APIError> {
        return MockDataProvider.shared.fetchNearbyStops()
    }
    
    func fetchArrivals(for stopId: String) -> AnyPublisher<[Arrival], APIError> {
        return MockDataProvider.shared.fetchArrivals(for: stopId)
    }
}

