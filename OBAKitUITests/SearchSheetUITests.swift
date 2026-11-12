//
//  SearchSheetUITests.swift
//  OBAKitUITests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest

// nonisolated: the target defaults to main-actor isolation, and XCTestCase's
// initializers and setUp are nonisolated.
nonisolated final class SearchSheetUITests: XCTestCase {

    @MainActor private var app: XCUIApplication!

    @MainActor override func setUp() async throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments += OnboardingBypass.launchArguments
        app.launchArguments += ["-OBAUseMapPanelExperience", "YES"]
        app.launchEnvironment["TEST_SUPPRESS_ALERT_BULLETINS"] = "1"

        addUIInterruptionMonitor(withDescription: "Location permission") { alert in
            for label in ["Allow Once", "Allow While Using App", "Allow While Using the App", "Don't Allow"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }

        app.launch()
    }

    @MainActor func test_searchSheet_nativeSearchableAndScopingTags() throws {
        let homeSearchButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Where are you going?")).firstMatch
        let fallbackSearchButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Search")).firstMatch

        if homeSearchButton.waitForExistence(timeout: 20) {
            homeSearchButton.tap()
        } else {
            XCTAssertTrue(fallbackSearchButton.waitForExistence(timeout: 10), "Home search trigger missing")
            fallbackSearchButton.tap()
        }

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Native search field missing")

        let closeButton = app.buttons["Close"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5), "Close toolbar button should stay visible while search is active")

        for scopeTitle in ["All", "Stops", "Routes", "Places"] {
            XCTAssertTrue(app.buttons[scopeTitle].waitForExistence(timeout: 5), "Missing scope tag '\(scopeTitle)'")
        }

        searchField.tap()
        searchField.typeText("10")

        let routeSuggestion = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Route: 10")).firstMatch
        let stopSuggestion = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Stop: 10")).firstMatch
        let addressSuggestion = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Address: 10")).firstMatch
        XCTAssertTrue(routeSuggestion.waitForExistence(timeout: 5))
        XCTAssertTrue(stopSuggestion.exists)
        XCTAssertTrue(addressSuggestion.exists)

        app.buttons["Stops"].tap()
        XCTAssertTrue(stopSuggestion.waitForExistence(timeout: 5))
        XCTAssertFalse(routeSuggestion.exists)
        XCTAssertFalse(addressSuggestion.exists)

        app.buttons["Routes"].tap()
        XCTAssertTrue(routeSuggestion.waitForExistence(timeout: 5))
        XCTAssertFalse(stopSuggestion.exists)
        XCTAssertFalse(addressSuggestion.exists)

        app.buttons["Places"].tap()
        XCTAssertTrue(addressSuggestion.waitForExistence(timeout: 5))
        XCTAssertFalse(routeSuggestion.exists)
        XCTAssertFalse(stopSuggestion.exists)
    }
}
