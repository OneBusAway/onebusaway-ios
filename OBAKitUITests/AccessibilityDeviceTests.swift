//
//  AccessibilityDeviceTests.swift
//  OBAKitUITests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest

// nonisolated: the target defaults to the main actor, and XCTestCase's
// initializers and setUp are nonisolated.
/// Reads what VoiceOver would read on the stop page, trip page and nearby list.
/// SwiftUI only builds its accessibility tree while something asks for it, so
/// combined elements can't be checked from a unit test; XCUITest asks the way
/// VoiceOver does. Runs against the live Puget Sound server.
nonisolated final class AccessibilityDeviceTests: XCTestCase {

    @MainActor private var app: XCUIApplication!

    @MainActor override func setUp() async throws {
        continueAfterFailure = true

        app = XCUIApplication()
        app.launchArguments += OnboardingBypass.launchArguments
        // Enforce chronological (time-sorted) departures layout so departure_row is always present.
        app.launchArguments += ["-OBALastUsedStopSort", "time"]
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
        app.tabBars.buttons["tab_map"].tap()
        let card = app.otherElements["sheet_grabber"]
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

    // MARK: - Accessibility Smoke Path

    /// Asserts that an interactive UI element exists and provides a meaningful, non-empty accessibility label.
    @MainActor private func assertAccessible(
        _ element: XCUIElement,
        component: String,
        timeout: TimeInterval = 20,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            "Accessibility Failure: Expected UI component '\(component)' was not found within \(timeout)s",
            file: file,
            line: line
        )

        let label = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let placeholder = (element.placeholderValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let accessibilityText = !label.isEmpty ? label : placeholder

        XCTAssertFalse(
            accessibilityText.isEmpty,
            "Accessibility Failure: UI component '\(component)' is missing a non-empty accessibility label",
            file: file,
            line: line
        )
    }

    /// End-to-end accessibility smoke path:
    /// - Launches app with onboarding bypass
    /// - Asserts non-empty accessibility labels and expected titles on tab bar buttons
    /// - Opens Bookmarks and asserts accessible navigation bar elements (Edit button, title) and empty-state content
    /// - Opens Home/Map and asserts accessible search field
    /// - Opens stop details via deep link and asserts accessible stop header, navigation bar actions, and departure row
    @MainActor func test_accessibilitySmokePath() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30), "Tab bar should appear after onboarding bypass")

        let expectedTabs = ["Map", "Recent", "Bookmarks", "More"]
        let tabButtons = tabBar.buttons
        XCTAssertGreaterThanOrEqual(tabButtons.count, expectedTabs.count, "Tab bar should contain at least \(expectedTabs.count) buttons")

        for (index, tabName) in expectedTabs.enumerated() {
            let button = tabButtons.element(boundBy: index)
            assertAccessible(button, component: "Tab '\(tabName)'")
            XCTAssertEqual(button.label, tabName, "Tab button at index \(index) should have label '\(tabName)'")
        }

        verifyBookmarksAccessibility(tabBar: tabBar)
        verifyMapAndSearchAccessibility(tabBar: tabBar)
        verifyStopDetailsAccessibility()
    }

    @MainActor private func verifyBookmarksAccessibility(tabBar: XCUIElement) {
        tabBar.buttons["tab_bookmarks"].tap()
        let bookmarksNavBar = app.navigationBars["Bookmarks"]
        XCTAssertTrue(bookmarksNavBar.waitForExistence(timeout: 10), "Bookmarks navigation bar should exist")

        let bookmarksTitle = bookmarksNavBar.staticTexts.firstMatch
        assertAccessible(bookmarksTitle, component: "Bookmarks navigation bar title")
        XCTAssertEqual(bookmarksTitle.label, "Bookmarks")

        let editButton = bookmarksNavBar.buttons.firstMatch
        assertAccessible(editButton, component: "Bookmarks Edit button")
        XCTAssertEqual(editButton.label, "Edit")

        let emptyStateTitle = app.staticTexts["empty_state_title"]
        if emptyStateTitle.waitForExistence(timeout: 3) {
            assertAccessible(emptyStateTitle, component: "Bookmarks empty state title")
            XCTAssertEqual(emptyStateTitle.label, "No Bookmarks")
        } else {
            // Scope query to the list collection view to avoid matching tab buttons or nav bar titles.
            let bookmarksList = app.collectionViews.firstMatch
            XCTAssertTrue(bookmarksList.waitForExistence(timeout: 5), "Bookmarks list collection view should exist")

            let bookmarkRowById = bookmarksList.descendants(matching: .any)["bookmark_row"].firstMatch
            let firstBookmark = bookmarkRowById.exists ? bookmarkRowById : bookmarksList.cells.firstMatch
            assertAccessible(firstBookmark, component: "First bookmark row", timeout: 5)

            // Formatters.accessibilityLabel(for:) produces one of these three prefixes:
            let validPrefixes = [
                "Stop Bookmark,",
                "Route Bookmark,",
                "Favorite Route Bookmark,"
            ]
            let label = firstBookmark.label
            let hasValidPrefix = validPrefixes.contains { label.hasPrefix($0) }
            XCTAssertTrue(
                hasValidPrefix,
                "Bookmark row label should start with 'Stop Bookmark,', 'Route Bookmark,', or 'Favorite Route Bookmark,', got: '\(label)'"
            )
        }
    }

    @MainActor private func verifyMapAndSearchAccessibility(tabBar: XCUIElement) {
        tabBar.buttons["tab_map"].tap()
        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 15), "Map element should exist on Map tab")

        let searchField = app.searchFields.firstMatch
        assertAccessible(searchField, component: "Search bar")
    }

    @MainActor private func verifyStopDetailsAccessibility() {
        openStop1110()

        let stopCollectionView = app.collectionViews.firstMatch
        XCTAssertTrue(stopCollectionView.waitForExistence(timeout: 20), "Stop page collection view should appear")

        let stopHeader = stopCollectionView.descendants(matching: .any)["stop_page_header"].firstMatch
        assertAccessible(stopHeader, component: "Stop details header (Pine St & 5th Ave)", timeout: 20)
        XCTAssertTrue(stopHeader.label.contains("Pine St & 5th Ave"), "Stop header should contain stop name")
        XCTAssertTrue(
            stopHeader.label.contains("Routes") || stopHeader.label.contains("bound"),
            "Stop header should contain route or direction context"
        )

        let stopNavBar = app.navigationBars.firstMatch
        XCTAssertTrue(stopNavBar.waitForExistence(timeout: 10), "Stop page navigation bar should exist")

        let moreButton = stopNavBar.buttons["stop_page_more_button"].firstMatch
        assertAccessible(moreButton, component: "Stop details More menu button")
        XCTAssertEqual(moreButton.label, "More")

        // Note: departure_row is rendered in chronological (time-sorted) layout,
        // enforced via "-OBALastUsedStopSort time" in launchArguments.
        let departureRow = stopCollectionView.buttons["departure_row"].firstMatch
        assertAccessible(departureRow, component: "Stop details departure row", timeout: 20)
        XCTAssertTrue(departureRow.label.contains("Route"), "Departure row label should contain route context, got: \(departureRow.label)")
        XCTAssertTrue(
            departureRow.label.contains("minute") || departureRow.label.contains("ago") || departureRow.label.contains("now"),
            "Departure row label should contain time/countdown context, got: \(departureRow.label)"
        )
    }
}
