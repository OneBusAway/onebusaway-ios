//
//  AppStoreScreenshotUITests.swift
//  OBAKitUITests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import XCTest

// nonisolated: the target defaults to the main actor, and XCTestCase's
// initializers and setUp are nonisolated.

/// Captures the App Store screenshot set. Each test walks to one slide's screen
/// and attaches a full-screen capture named after it, so a run of this class
/// leaves every raw screenshot in the result bundle. Run it through
/// `scripts/app_store_screenshots`, which also pins the status bar, then exports,
/// frames and composes the slides; see `docs/app-store/README.md`.
///
/// The data is live Puget Sound data (region 1), seen from Capitol Hill. The
/// app's DEBUG launch hooks (`Application+ScreenshotSupport.swift`) open the
/// stop sheet and seed the bookmarks. Tests assert only what they need to know
/// the screen has drawn.
nonisolated final class AppStoreScreenshotUITests: XCTestCase {

    /// Capitol Hill light rail station, southbound platform.
    private static let stopID = "40_99610"

    /// Just east of the station, so the location dot doesn't sit on its pin.
    private static let riderLocation = CLLocation(latitude: 47.6188, longitude: -122.3197)

    private static let bookmarks = """
    [
      {"group": "Work 🏢", "name": "10 to Downtown", "stopID": "1_11080", "routeID": "1_100002"},
      {"group": "Work 🏢", "name": "1 Line Light Rail", "stopID": "40_99610", "routeID": "40_100479"},
      {"group": "Work 🏢", "name": "Streetcar", "stopID": "1_41980", "routeID": "23_102638"},
      {"group": "Home", "name": "1 Line Light Rail", "stopID": "40_1121", "routeID": "40_100479"},
      {"group": "Home", "name": "10 back home", "stopID": "1_1180", "routeID": "1_100002"}
    ]
    """

    @MainActor override func setUp() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        XCUIDevice.shared.location = XCUILocation(location: Self.riderLocation)
    }

    // MARK: - Launch

    @MainActor private func launch(environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-OBACurrentRegionIdentifierUserDefaultsKey", "<integer>1</integer>",
            // Start on the Map tab whatever tab the simulator was last left on.
            "-UserDataStore.lastSelectedView", "<integer>0</integer>",
            // A popover tip would sit over the screen and swallow the first tap.
            "-com.apple.TipKit.HideAllTips", "1",
            // The inline "needs your help" donation card would cover arrivals.
            "-donationRequestDismissedDateKey", "<date>2026-01-01T00:00:00Z</date>"
        ]
        app.launchEnvironment["TEST_SUPPRESS_ALERT_BULLETINS"] = "1"
        // Every launch starts with no Live Activities: slide 2's would otherwise
        // show in the Dynamic Island over Safari, and repeated `--only` runs of
        // slide 2 would stack activities on the Lock Screen.
        app.launchEnvironment["TEST_SCREENSHOT_END_LIVE_ACTIVITIES"] = "1"
        app.launchEnvironment.merge(environment) { _, new in new }
        app.launch()
        return app
    }

    @MainActor private func launchOnStopSheet() -> XCUIApplication {
        let app = launch(environment: ["TEST_SCREENSHOT_STOP_ID": Self.stopID])
        XCTAssertTrue(firstDeparture(in: app).waitForExistence(timeout: 45), "Stop sheet never showed departures")
        return app
    }

    /// Full-screen capture (status bar included, as the App Store shows it),
    /// kept regardless of the test's outcome so the export script finds it.
    @MainActor private func capture(_ name: String, settle: UInt32 = 3) {
        // Sheets, map camera moves and countdowns animate in; a fixed settle
        // beats polling for "animation finished", which XCUITest can't see.
        sleep(settle)
        let attachment = XCTAttachment(screenshot: Self.screenshot())
        attachment.name = Self.duoPosture == "folded" ? "\(name)-folded" : name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The iPhone Duo's posture, `open` or `folded`, which
    /// `scripts/app_store_screenshots --duo` passes in. Nil on other devices,
    /// where the script passes the variable empty.
    private static let duoPosture = ProcessInfo.processInfo.environment["SCREENSHOT_POSTURE"]
        .flatMap { $0.isEmpty ? nil : $0 }

    /// iPhone Duo has two screens, and `XCUIScreen.main` is the cover one,
    /// which is dark when the Duo is open; then the inner, larger one is lit.
    @MainActor private static func screenshot() -> XCUIScreenshot {
        guard duoPosture == "open" else { return XCUIScreen.main.screenshot() }
        let area = { (shot: XCUIScreenshot) in shot.image.size.width * shot.image.size.height }
        return XCUIScreen.screens.map { $0.screenshot() }.max { area($0) < area($1) } ?? XCUIScreen.main.screenshot()
    }

    // MARK: - Departure rows

    /// Departure rows are buttons labelled "Route 1 Line to Federal Way Downtown,
    /// arrives in 13 minutes, ...".
    @MainActor private func departures(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Route ' AND label CONTAINS ' in '"))
    }

    @MainActor private func firstDeparture(in app: XCUIApplication) -> XCUIElement {
        departures(in: app).firstMatch
    }

    /// The first departure at least `minutes` away, scrolling the sheet up
    /// once if none is visible yet.
    @MainActor private func departure(atLeast minutes: Int, in app: XCUIApplication) -> XCUIElement? {
        for attempt in 0..<2 {
            for row in departures(in: app).allElementsBoundByIndex {
                if let away = Self.minutesAway(row.label), away >= minutes, row.isHittable {
                    return row
                }
            }
            if attempt == 0 {
                app.swipeUp()
            }
        }
        return nil
    }

    private static func minutesAway(_ label: String) -> Int? {
        guard let range = label.range(of: #" in (\d+) minutes"#, options: .regularExpression) else { return nil }
        return Int(label[range].filter(\.isNumber))
    }

    /// Waits for `element`, failing the test with `message` if it never shows, then taps it.
    @MainActor private func tap(_ element: XCUIElement, timeout: TimeInterval = 15, _ message: String = "") {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), message)
        element.tap()
    }

    @MainActor private func openTripPage(in app: XCUIApplication) {
        firstDeparture(in: app).tap()
        XCTAssertTrue(app.buttons["Track on Lock Screen"].waitForExistence(timeout: 30), "Trip page never loaded")
    }

    // MARK: - Slides

    /// 01 — The map with the Capitol Hill stop sheet and its live departures.
    @MainActor func test01StopArrivals() {
        _ = launchOnStopSheet()
        capture("01-stop-arrivals", settle: 4)
    }

    /// 02 — A Live Activity on the Lock Screen. Starts tracking from the trip
    /// page, then locks and wakes the device so the Lock Screen shows.
    @MainActor func test02LockScreen() throws {
        if Self.duoPosture != nil {
            throw XCTSkip("pressLockButton doesn't lock iPhone Duo.")
        }
        let app = launchOnStopSheet()
        openTripPage(in: app)
        app.buttons["Track on Lock Screen"].tap()
        sleep(3)

        // XCUIDevice has no public lock button; this is the private selector
        // UI test suites commonly use. Skip, rather than capture the app, if a
        // future Xcode removes it.
        let lock = NSSelectorFromString("pressLockButton")
        guard XCUIDevice.shared.responds(to: lock) else {
            throw XCTSkip("XCUIDevice can't press the lock button; capture the Lock Screen by hand.")
        }
        XCUIDevice.shared.perform(lock)
        sleep(2)
        XCUIDevice.shared.perform(lock)

        // On a fresh simulator the Lock Screen asks whether to keep allowing
        // the app's Live Activities: "Allow" the first time, "Always Allow"
        // the next, after which it stops asking.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Always Allow", "Allow"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 3) {
                button.tap()
                break
            }
        }
        capture("02-lock-screen", settle: 6)
    }

    /// 03 — The trip page: the vehicle on the map, the departure card below.
    @MainActor func test03TripVehicle() {
        let app = launchOnStopSheet()
        openTripPage(in: app)
        capture("03-trip-vehicle", settle: 4)
    }

    /// 04 — Trip planner results from the rider's location to UW's Allen Center.
    @MainActor func test04TripPlanner() {
        let app = launch()
        let search = app.searchFields["Where are you going?"]
        tap(search, timeout: 30, "Map search field missing")
        search.typeText("Paul G. Allen Center")

        let place = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'The Paul G. Allen Center'")).firstMatch
        tap(place, timeout: 20, "Search found no Allen Center")
        tap(app.buttons["Plan trip to this location"])
        tap(app.buttons["Find Routes"])

        let itinerary = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Depart:'")).firstMatch
        XCTAssertTrue(itinerary.waitForExistence(timeout: 45), "Trip planner returned no itineraries")
        capture("04-trip-planner")
    }

    /// 05 — The Add Reminder sheet, on a departure far enough out that the
    /// picker can offer 10 minutes.
    @MainActor func test05Alarm() throws {
        let app = launchOnStopSheet()
        guard let row = departure(atLeast: 12, in: app) else {
            throw XCTSkip("No departure 12 or more minutes away at Capitol Hill right now.")
        }
        let bell = row.images["bell"]
        XCTAssertTrue(bell.exists, "Departure has no alarm button; alarms need Obaco and push running")
        bell.tap()
        XCTAssertTrue(app.staticTexts["Add Reminder"].waitForExistence(timeout: 15), "Alarm sheet never appeared")
        capture("05-alarm")
    }

    /// 06 — The Bookmarks tab, seeded with two groups of trip bookmarks.
    @MainActor func test06Bookmarks() {
        let app = launch(environment: ["TEST_SCREENSHOT_BOOKMARKS": Self.bookmarks])
        // Not `app.tabBars`: iPhone Duo shows its tabs in a vertical bar.
        let tab = app.buttons["Bookmarks"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 30))

        // The seed fetches live arrivals for each bookmark, so it lands a few
        // seconds after launch; re-selecting the tab picks it up.
        let lastBookmark = app.staticTexts["10 back home"]
        for _ in 0..<6 where !lastBookmark.exists {
            tab.tap()
            _ = lastBookmark.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(lastBookmark.exists, "Seeded bookmarks never appeared")
        capture("06-bookmarks", settle: 5)
    }

    /// 07 — The Open Transit Software Foundation's site, in Safari.
    @MainActor func test07OpenSource() throws {
        // Launch once so the app ends slide 2's Live Activity, or it shows in
        // the Dynamic Island over Safari.
        let app = launch()
        XCTAssertTrue(app.buttons["Bookmarks"].firstMatch.waitForExistence(timeout: 30))
        sleep(2)
        app.terminate()

        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.open(try XCTUnwrap(URL(string: "https://opentransitsoftwarefoundation.org/")))
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 30))
        capture("07-open-source", settle: 8)
    }
}
