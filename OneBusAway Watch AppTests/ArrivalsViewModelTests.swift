//
//  ArrivalsViewModelTests.swift
//  OBAKit
//
//  Created by Prince Yadav on 06/03/25.
//


import XCTest
import Combine
@testable import OneBusAway_Watch

class ArrivalsViewModelTests: XCTestCase {
    var viewModel: ArrivalsViewModel!
    var mockAPIService: MockAPIService!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        mockAPIService = MockAPIService()
        viewModel = ArrivalsViewModel()
        viewModel.apiService = mockAPIService
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        viewModel = nil
        mockAPIService = nil
        cancellables = nil
        super.tearDown()
    }
    
    func testLoadArrivals() {
        // Given
        let expectation = XCTestExpectation(description: "Load arrivals")
        let mockArrival = Arrival.example
        mockAPIService.mockArrivals = [mockArrival]
        
        // When
        viewModel.loadArrivals(for: "1_10914")
        
        // Then
        viewModel.$arrivals
            .dropFirst()
            .sink { arrivals in
                XCTAssertEqual(arrivals.count, 1)
                XCTAssertEqual(arrivals.first?.id, "1_10914_43")
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 1.0)
        XCTAssertFalse(viewModel.isLoading)
    }
    
    func testLoadArrivalsError() {
        // Given
        let expectation = XCTestExpectation(description: "Load arrivals error")
        mockAPIService.shouldFail = true
        
        // When
        viewModel.loadArrivals(for: "1_10914")
        
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
    
    func testToggleFavorite() {
        // Given
        let stop = Stop.example
        
        // When
        viewModel.toggleFavorite(stop: stop)
        
        // Then
        XCTAssertTrue(viewModel.isFavorite)
        
        // When toggled again
        viewModel.toggleFavorite(stop: stop)
        
        // Then
        XCTAssertFalse(viewModel.isFavorite)
    }
}

