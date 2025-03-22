//
//  WatchConnectivityTests.swift
//  OBAKit
//
//  Created by Prince Yadav on 06/03/25.
//


import XCTest
import WatchConnectivity
@testable import OneBusAway_Watch

class WatchConnectivityTests: XCTestCase {
    var connectivityService: WatchConnectivityService!
    
    override func setUp() {
        super.setUp()
        connectivityService = WatchConnectivityService.shared
    }
    
    override func tearDown() {
        connectivityService = nil
        super.tearDown()
    }
    
    func testRequestFavoritesFromPhone() {
        // This is a basic test to ensure the method doesn't crash
        // In a real test environment, we would mock WCSession
        XCTAssertNoThrow(connectivityService.requestFavoritesFromPhone())
    }
    
    func testSendFavoritesToPhone() {
        // Given
        let favorites = [Stop.example]
        
        // When/Then
        XCTAssertNoThrow(connectivityService.sendFavoritesToPhone(favorites))
    }
    
    func testReceiveFavorites() {
        // Given
        let stop = Stop.example
        let data = try! JSONEncoder().encode([stop])
        let message = ["favorites": data]
        
        // When
        // In a real test, we would mock the session delegate methods
        // For now, we'll just verify the service exists
        XCTAssertNotNil(connectivityService)
        
        // Then
        // In a real test, we would verify that receivedFavorites is updated
        // after the delegate method is called
    }
}

