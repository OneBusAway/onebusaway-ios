//
//  OnboardingUITests.swift
//  OBAKitUITests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest

/// Exercises the first-launch onboarding flow end to end: location authorization
/// page → region picker → main UI.
///
/// `TEST_ONBOARDING=1` (a DEBUG-only environment variable the app already supports)
/// forces the onboarding flow regardless of stored state and appends two debug pages
/// after the region picker.
final class OnboardingUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_onboarding_fromLocationPageToMainUI() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TEST_ONBOARDING"] = "1"
        app.launchArguments += ["-AppleLanguages", "(en)"]
        app.launch()

        // Page 1: location authorization.
        XCTAssertTrue(
            app.staticTexts["Welcome!"].waitForExistence(timeout: 30),
            "Location authorization page should appear")

        // The only way forward is the CoreLocationUI LocationButton, which grants
        // one-time authorization without a standard permission alert. It does not
        // reliably appear in `app.buttons`, so search all descendants by label.
        let locationButton = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] 'location'")
        ).firstMatch
        XCTAssertTrue(
            locationButton.waitForExistence(timeout: 10),
            "LocationButton should exist. Hierarchy: \(app.debugDescription)")
        locationButton.tap()

        // Defensive: dismiss a location permission alert if the system shows one anyway.
        allowLocationAlertIfPresent()

        // Page 2: region picker.
        XCTAssertTrue(
            app.staticTexts["Choose Region"].waitForExistence(timeout: 30),
            "Region picker should appear after the location page")

        // Manual selection requires the auto-select toggle to be off. (Tapping the
        // LocationButton on the previous page forces it on.) The screen has exactly
        // one switch; SwiftUI toggle labels are not reliably queryable.
        let autoSelectToggle = app.switches.firstMatch
        XCTAssertTrue(autoSelectToggle.waitForExistence(timeout: 10), "Auto-select toggle should exist")
        if isToggleOn(autoSelectToggle) {
            // SwiftUI list toggles often don't react to taps on the element's center
            // (the label area); tap the switch knob on the trailing edge instead.
            autoSelectToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }
        if isToggleOn(autoSelectToggle) {
            autoSelectToggle.tap()
        }
        waitUntil(timeout: 10, "auto-select toggle should turn off; switches=\(app.switches.count) value=\(String(describing: autoSelectToggle.value))") {
            !self.isToggleOn(autoSelectToggle)
        }

        let pugetSound = app.staticTexts["Puget Sound"].firstMatch
        XCTAssertTrue(pugetSound.waitForExistence(timeout: 10), "Bundled regions should be listed")
        pugetSound.tap()

        let continueButton = app.buttons["Continue"].firstMatch
        XCTAssertTrue(continueButton.waitForExistence(timeout: 10))
        waitUntil(timeout: 10, "Continue should be enabled once a region is selected") {
            continueButton.isEnabled
        }
        continueButton.tap()

        // TEST_ONBOARDING appends two debug confirmation pages.
        let debugA = app.buttons["Debug A"].firstMatch
        XCTAssertTrue(debugA.waitForExistence(timeout: 30), "Debug page A should follow the region picker")
        debugA.tap()

        let debugB = app.buttons["Debug B"].firstMatch
        XCTAssertTrue(debugB.waitForExistence(timeout: 10))
        debugB.tap()

        // Main UI.
        XCTAssertTrue(
            app.tabBars.firstMatch.waitForExistence(timeout: 30),
            "Main tab bar should appear after onboarding completes")
    }

    // MARK: - Helpers

    private func isToggleOn(_ element: XCUIElement) -> Bool {
        (element.value as? String) == "1"
    }

    /// Polls `condition` until it is true or the timeout elapses, then asserts.
    private func waitUntil(
        timeout: TimeInterval,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: @escaping () -> Bool
    ) {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if condition() { return }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
        }
        XCTAssertTrue(condition(), message, file: file, line: line)
    }

    private func allowLocationAlertIfPresent() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow Once", "Allow While Using App", "Allow While Using the App"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 3) {
                button.tap()
                return
            }
        }
    }
}
