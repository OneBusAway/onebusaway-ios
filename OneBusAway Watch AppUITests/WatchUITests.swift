//
//  WatchUITests.swift
//  OBAKit
//
//  Created by Prince Yadav on 06/03/25.
//


import XCTest

class WatchUITests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    func testHomeScreenLoads() {
        // Verify the home screen loads with nearby stops
        let nearbyStopsText = app.staticTexts["Nearby Stops"]
        XCTAssertTrue(nearbyStopsText.exists, "Home screen should show 'Nearby Stops' title")
        
        // Wait for loading to complete
        let timeout = 5.0
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true"),
            object: app.tables.firstMatch
        )
        
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "Table should appear after loading")
    }
    
    func testNavigationToArrivalsScreen() {
        // Wait for stops to load
        sleep(3)
        
        // Tap on the first stop if available
        if app.tables.cells.count > 0 {
            app.tables.cells.element(boundBy: 0).tap()
            
            // Verify we navigated to the arrivals screen
            let arrivalsTitle = app.staticTexts["Arrivals"]
            XCTAssertTrue(arrivalsTitle.exists, "Should navigate to arrivals screen")
            
            // Verify upcoming arrivals section exists
            let upcomingArrivalsText = app.staticTexts["Upcoming Arrivals"]
            XCTAssertTrue(upcomingArrivalsText.exists, "Arrivals screen should show 'Upcoming Arrivals' section")
        }
    }
    
    func testFavoritesTab() {
        // Tap on the Favorites tab
        app.buttons["Favorites"].tap()
        
        // Verify we navigated to the favorites screen
        let favoritesTitle = app.staticTexts["Favorites"]
        XCTAssertTrue(favoritesTitle.exists, "Should navigate to favorites screen")
    }
    
    func testSettingsTab() {
        // Tap on the Settings tab
        app.buttons["Settings"].tap()
        
        // Verify we navigated to the settings screen
        let settingsTitle = app.staticTexts["Settings"]
        XCTAssertTrue(settingsTitle.exists, "Should navigate to settings screen")
        
        // Verify settings options exist
        let refreshIntervalText = app.staticTexts["Refresh Interval"]
        XCTAssertTrue(refreshIntervalText.exists, "Settings screen should show refresh interval option")
        
        let notificationsText = app.staticTexts["Notifications"]
        XCTAssertTrue(notificationsText.exists, "Settings screen should show notifications section")
    }
}

