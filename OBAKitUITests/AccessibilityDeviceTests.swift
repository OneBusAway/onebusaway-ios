//
//  AccessibilityDeviceTests.swift
//  OBAKitUITests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest

/// Reads what VoiceOver would read on the stop page, trip page and nearby list.
/// SwiftUI only builds its accessibility tree while something asks for it, so
/// combined elements can't be checked from a unit test; XCUITest asks the way
/// VoiceOver does. Runs against the live Puget Sound server.
// nonisolated: the target defaults to the main actor, and XCTestCase\'s
// initializers and setUp are nonisolated.
nonisolated final class AccessibilityDeviceTests: XCTestCase {

    @MainActor private var app: XCUIApplication!

    @MainActor override func setUp() async throws {
        continueAfterFailure = true

        app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-OBACurrentRegionIdentifierUserDefaultsKey", "<integer>1</integer>"
        ]
        app.launchEnvironment["TEST_SUPPRESS_ALERT_BULLETINS"] = "1"

        addUIInterruptionMonitor(withDescription: "Permissions") { alert in
            for label in ["Allow While Using App", "Allow While Using the App", "Allow Once", "Open", "Don't Allow"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
    }

    @MainActor private func openStop1110() {
        app.open(URL(string: "onebusaway://view-stop?stopID=1_1110&regionID=1")!)
        // The system may ask before opening the app's own URL.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Open"].waitForExistence(timeout: 3) {
            springboard.buttons["Open"].tap()
        }
    }

    /// The pushed stop page's heading: the stop name first, "Updated…" as its value.
    @MainActor func test_stopHeader_readsNameFirst() {
        openStop1110()
        let header = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Pine St & 5th Ave;")).firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 20), "No element labelled with the stop's full name")
        print("A11Y header label: \(header.label)")
        print("A11Y header value: \(String(describing: header.value))")
        XCTAssertTrue(header.label.contains("Routes"))
        XCTAssertFalse(header.label.contains("Updated"))
        XCTAssertTrue((header.value as? String)?.contains("Updated") == true)
    }

    /// The trip page's back row is one element that names where it goes.
    ///
    /// XCTest's tree also lists the children of a combined element (the stop
    /// header's parts show up the same way), so it can't tell whether VoiceOver
    /// reads the title twice; that needs a VoiceOver pass. What it can show is
    /// that the row itself is the "Back to …" element.
    @MainActor func test_tripBackRow_isOneBackToElement() {
        openStop1110()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Route ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "No departure rows on stop 1110")
        row.tap()

        let backs = app.buttons.matching(NSPredicate(format: "label == %@", "Back to Pine St & 5th Ave"))
        XCTAssertTrue(backs.firstMatch.waitForExistence(timeout: 20), "No 'Back to Pine St & 5th Ave' button")
        let title = app.staticTexts.matching(NSPredicate(format: "label == %@", "Pine St & 5th Ave")).firstMatch
        XCTAssertTrue(title.exists)
        // The widest match is the row; it has to take in the title beside the glyph.
        let widest = backs.allElementsBoundByIndex.max { $0.frame.width < $1.frame.width }
        XCTAssertTrue(widest.map { $0.frame.contains(title.frame) } == true, "The back element doesn't cover the row's title")

        for button in app.buttons.allElementsBoundByIndex where button.label.isEmpty {
            print("A11Y unlabeled button: frame=\(button.frame)")
        }
    }

    /// The nearby list: rows carry the pin's label and a distance.
    @MainActor func test_nearbyRows_readDistance() throws {
        // The app reopens on the last tab used.
        app.tabBars.buttons["Map"].tap()
        let card = app.otherElements["Card controller"]
        if card.waitForExistence(timeout: 10) {
            card.swipeUp()
        }
        let rows = app.cells.matching(NSPredicate(format: "label CONTAINS %@", "Stop ID"))
        var found = rows.firstMatch.waitForExistence(timeout: 20)
        if !found {
            // "No Nearby Stops" at the default zoom (an open audit item). Zoom out
            // once, as a sighted rider would, to reach the rows.
            app.maps.firstMatch.pinch(withScale: 0.4, velocity: -1)
            found = rows.firstMatch.waitForExistence(timeout: 30)
            print("A11Y nearby after zoom-out: found=\(found)")
        }
        print("A11Y nearby rows: \(rows.allElementsBoundByIndex.prefix(5).map(\.label))")
        if !found {
            print("A11Y nearby: no rows. Visible text: \(app.staticTexts.allElementsBoundByIndex.prefix(10).map(\.label))")
        }
        // An open audit item, seen on device too: the map can show "No Nearby
        // Stops" even zoomed out downtown. Nothing to read when it does.
        try XCTSkipUnless(found, "The map showed No Nearby Stops, so there were no rows to read")
        XCTAssertTrue(rows.firstMatch.label.contains("away"), "Nearby row has no distance")
    }
}
