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
        guard let path = Bundle(for: DonationCell.self).path(forResource: "en", ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    // MARK: - Title Switching

    @Test func `Title displays set copy when alert is inactive`() {
        let expected = Bundle(for: DonationCell.self).localizedString(forKey: "stop_page.proximity_alert.menu.set", value: nil, table: nil)
        #expect(ProximityAlertMenuItem.title(isActive: false) == expected)
    }

    @Test func `Title displays cancel copy when alert is active`() {
        let expected = Bundle(for: DonationCell.self).localizedString(forKey: "stop_page.proximity_alert.menu.cancel", value: nil, table: nil)
        #expect(ProximityAlertMenuItem.title(isActive: true) == expected)
    }

    @Test func `Active and inactive titles are distinct`() {
        #expect(ProximityAlertMenuItem.title(isActive: true) != ProximityAlertMenuItem.title(isActive: false))
    }

    // MARK: - String Catalog Integrity

    @Test func `Menu item localization keys exist in the English string bundle`() throws {
        let bundle = try #require(englishBundle())

        let keys = [
            "stop_page.proximity_alert.menu.set": "Alert Me When Nearby",
            "stop_page.proximity_alert.menu.cancel": "Cancel Nearby Alert"
        ]

        for (key, expectedValue) in keys {
            let localized = bundle.localizedString(forKey: key, value: "MISSING", table: nil)
            #expect(localized != "MISSING", "\(key) is missing from the English catalog")
            #expect(localized == expectedValue, "\(key) has unexpected translation in English catalog")
        }
    }
}
