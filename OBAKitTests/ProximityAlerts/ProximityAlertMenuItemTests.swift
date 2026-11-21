//
//  ProximityAlertMenuItemTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
struct ProximityAlertMenuItemTests {

    private func englishBundle() -> Bundle? {
        guard let path = Bundle.obaKit.path(forResource: "en", ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    // MARK: - Title Switching

    @Test func `Title displays set copy when alert is inactive`() {
        let expected = Bundle.obaKit.localizedString(forKey: "stop_page.proximity_alert.menu.set", value: nil, table: nil)
        #expect(ProximityAlertMenuItem.title(isActive: false) == expected)
    }

    @Test func `Title displays cancel copy when alert is active`() {
        let expected = Bundle.obaKit.localizedString(forKey: "stop_page.proximity_alert.menu.cancel", value: nil, table: nil)
        #expect(ProximityAlertMenuItem.title(isActive: true) == expected)
    }

    @Test func `Active and inactive titles are distinct`() {
        #expect(ProximityAlertMenuItem.title(isActive: true) != ProximityAlertMenuItem.title(isActive: false))
    }

    // MARK: - Accessibility Semantics

    @Test func `Accessibility label matches item title for state`() {
        #expect(ProximityAlertMenuItem.accessibilityLabel(isActive: false) == ProximityAlertMenuItem.title(isActive: false))
        #expect(ProximityAlertMenuItem.accessibilityLabel(isActive: true) == ProximityAlertMenuItem.title(isActive: true))
        #expect(ProximityAlertMenuItem.accessibilityLabel == "Nearby alert")
    }

    @Test func `Accessibility value reflects active state`() {
        #expect(ProximityAlertMenuItem.accessibilityValue(isActive: true) == "active")
        #expect(ProximityAlertMenuItem.accessibilityValue(isActive: false) == "inactive")
    }

    @Test func `Accessibility hint explains action outcome`() {
        #expect(ProximityAlertMenuItem.accessibilityHint(isActive: false) == "Alerts you when approaching this stop.")
        #expect(ProximityAlertMenuItem.accessibilityHint(isActive: true) == "Cancels the nearby alert for this stop.")
    }

    @Test func `Presenter forwards proximity alert accessibility semantics`() {
        #expect(StopPageActionPresenter.proximityAlertAccessibilityLabel(isActive: false) == ProximityAlertMenuItem.accessibilityLabel(isActive: false))
        #expect(StopPageActionPresenter.proximityAlertAccessibilityLabel(isActive: true) == ProximityAlertMenuItem.accessibilityLabel(isActive: true))
        #expect(StopPageActionPresenter.proximityAlertAccessibilityValue(isActive: false) == "inactive")
        #expect(StopPageActionPresenter.proximityAlertAccessibilityValue(isActive: true) == "active")
        #expect(StopPageActionPresenter.proximityAlertAccessibilityHint(isActive: false) == "Alerts you when approaching this stop.")
        #expect(StopPageActionPresenter.proximityAlertAccessibilityHint(isActive: true) == "Cancels the nearby alert for this stop.")
    }

    // MARK: - String Catalog Integrity

    @Test func `Menu item localization keys exist in the English string bundle`() throws {
        let bundle = try #require(englishBundle())

        let keys = [
            "stop_page.proximity_alert.menu.set": "Alert Me When Nearby",
            "stop_page.proximity_alert.menu.cancel": "Cancel Nearby Alert",
            "stop_page.proximity_alert.a11y_label": "Nearby alert",
            "stop_page.proximity_alert.a11y_value_active": "active",
            "stop_page.proximity_alert.a11y_value_inactive": "inactive",
            "stop_page.proximity_alert.a11y_hint_set": "Alerts you when approaching this stop.",
            "stop_page.proximity_alert.a11y_hint_cancel": "Cancels the nearby alert for this stop."
        ]

        for (key, expectedValue) in keys {
            let localized = bundle.localizedString(forKey: key, value: "MISSING", table: nil)
            #expect(localized != "MISSING", "\(key) is missing from the English catalog")
            #expect(localized == expectedValue, "\(key) has unexpected translation in English catalog")
        }
    }
}
