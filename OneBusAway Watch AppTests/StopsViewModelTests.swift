//
//  StopsViewModelTests.swift
//  OBAKit
//
//  Created by Prince Yadav on 06/03/25.
//


import XCTest
import CoreLocation
import Combine
@testable import OneBusAway_Watch

class StopsViewModelTests: XCTestCase {
    var viewModel: StopsViewModel!
    var mockAPIService: MockAPIService!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        mockAPIService = MockAPIService()
        viewModel = StopsViewModel()
        viewModel.apiService = mockAPIService
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        viewModel = nil
        mockAPIService = nil
        cancellables = nil
        super.tearDown()
    }
    
    func testLoadNearbyStops() {
        // Given
        let expectation = XCTestExpectation(description: "Load nearby stops")
        let mockStops = [Stop.example]
        mockAPIService.mockStops = mockStops
        
        // When
        viewModel.loadNearbyStops(latitude: 47.6062, longitude: -122.3321)
        
        // Then
        viewModel.$nearbyStops
            .dropFirst()
            .sink { stops in
                XCTAssertEqual(stops.count, 1)
                XCTAssertEqual(stops.first?.id, "1_10914")
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 1.0)
        XCTAssertFalse(viewModel.isLoading)
    }
    
    func testLoadNearbyStopsError() {
        // Given
        let expectation = XCTestExpectation(description: "Load nearby stops error")
        mockAPIService.shouldFail = true
        
        // When
        viewModel.loadNearbyStops(latitude: 47.6062, longitude: -122.3321)
        
        // Then
        viewModel.$errorMessage
            .dropFirst()
            .sink { errorMessage in
                XCTAssertNotNil(errorMessage)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 1.0)
        XCTAssertFalse(viewModel.isLoading)
    }
}

// Mock API Service for testing
class MockAPIService: APIServiceProtocol {
    var mockStops: [Stop] = []
    var mockArrivals: [Arrival] = []
    var shouldFail = false
    
    func fetchNearbyStops(latitude: Double, longitude: Double) -> AnyPublisher<[Stop], APIError> {
        if shouldFail {
            return Fail(error: APIError.networkError(NSError(domain: "test", code: 0, userInfo: nil)))
                .eraseToAnyPublisher()
        } else {
            return Just(mockStops)
                .setFailureType(to: APIError.self)
                .eraseToAnyPublisher()
        }
    }
    
    func fetchArrivals(for stopId: String) -> AnyPublisher<[Arrival], APIError> {
        if shouldFail {
            return Fail(error: APIError.networkError(NSError(domain: "test", code: 0, userInfo: nil)))
                .eraseToAnyPublisher()
        } else {
            return Just(mockArrivals)
                .setFailureType(to: APIError.self)
                .eraseToAnyPublisher()
        }
    }
}

