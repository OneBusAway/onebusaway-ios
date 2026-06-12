//
//  MainFlowUITests.swift
//  OBAKitUITests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest

/// Smoke tests for the main app UI with a region already selected.
///
/// The current region is injected through the UserDefaults argument domain
/// (`-OBACurrentRegionIdentifierUserDefaultsKey <integer>1</integer>` = Puget Sound,
/// which is bundled in regions.json), so onboarding is skipped without any
/// stored state on the simulator.
final class MainFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-OBACurrentRegionIdentifierUserDefaultsKey", "<integer>1</integer>"
        ]

        // The map requests location authorization on first appearance; dismiss the
        // system alert so it can't block tab interactions.
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

    func test_appLaunches_withTabBar_andOnboardingIsSkipped() throws {
        XCTAssertTrue(
            app.tabBars.firstMatch.waitForExistence(timeout: 30),
            "Tab bar should appear on launch when a region is already selected")
        XCTAssertFalse(
            app.staticTexts["Choose Region"].exists,
            "Onboarding must not appear when a region is already selected")
    }

    func test_allTabs_openWithoutCrashing() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30))

        for tabName in ["Recent", "Bookmarks", "More", "Map"] {
            let tab = tabBar.buttons[tabName]
            XCTAssertTrue(tab.waitForExistence(timeout: 10), "Tab '\(tabName)' should exist")
            tab.tap()
            // Re-tap the (already selected) tab: a harmless interaction that gives the
            // interruption monitor a chance to dismiss any permission alert. A blind
            // center-screen tap could hit a row and navigate away.
            tab.tap()
            XCTAssertTrue(tabBar.exists, "App should still be running after opening '\(tabName)'")
        }
    }

    func test_tripPlannerTip_rendersContent() throws {
        // Relaunch with all tips forced visible (DEBUG-only hook) so the test
        // doesn't depend on TipKit's display-frequency or invalidation state.
        app.launchEnvironment["TEST_SHOW_ALL_TIPS"] = "1"
        app.launch()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))

        // On iOS 26, TipUIPopoverViewController rendered the tip as an empty
        // bubble: its content view was never resized to the popover and the
        // text was clipped out of view. TipHostingViewController fixes this;
        // assert the tip's actual content is visible.
        XCTAssertTrue(
            app.staticTexts["Plan Your Trip"].waitForExistence(timeout: 15),
            "Trip planner tip popover should display its title")
        XCTAssertTrue(
            app.staticTexts["Tap here to search for places and plan your journey with transit directions."].exists,
            "Trip planner tip popover should display its message")
    }

    func test_moreTab_showsSettingsContent() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30))

        let moreTab = tabBar.buttons["More"]
        moreTab.tap()
        // Re-tap to trigger the interruption monitor without touching screen content.
        moreTab.tap()

        let moreNavBar = app.navigationBars["More"]
        XCTAssertTrue(moreNavBar.waitForExistence(timeout: 10), "More tab should display its navigation bar")
        XCTAssertTrue(
            moreNavBar.buttons["Settings"].waitForExistence(timeout: 10),
            "More tab should have a Settings button in its navigation bar")
    }
}
