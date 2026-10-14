//
//  ProximityAlertSettingsReasonTests.swift
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
struct ProximityAlertSettingsReasonTests {

    private func englishBundle() -> Bundle? {
        guard let path = Bundle(for: DonationCell.self).path(forResource: "en", ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    // MARK: - Alert Titles

    @Test func `Alert title is wired to expected catalog key across all reasons`() {
        let expectations: [(reason: ProximityAlertSettingsReason, key: String)] = [
            (.locationWhenInUse, "stop_page.proximity_alert.location_when_in_use.title"),
            (.locationDenied, "stop_page.proximity_alert.location_denied.title"),
            (.locationRestricted, "stop_page.proximity_alert.location_restricted.title"),
            (.notifications, "stop_page.proximity_alert.notifications_denied.title")
        ]

        for item in expectations {
            let expected = Bundle(for: DonationCell.self).localizedString(forKey: item.key, value: nil, table: nil)
            #expect(item.reason.alertTitle == expected)
        }
    }

    @Test func `Alert titles are unique across all reasons`() {
        let reasons: [ProximityAlertSettingsReason] = [
            .locationWhenInUse,
            .locationDenied,
            .locationRestricted,
            .notifications
        ]

        let titles = reasons.map(\.alertTitle)
        #expect(Set(titles).count == reasons.count)
    }

    // MARK: - Alert Messages

    @Test func `Alert message is wired to expected catalog key and formats app name`() {
        let appName = Bundle.main.appName

        let templateKeys: [(reason: ProximityAlertSettingsReason, key: String)] = [
            (.locationWhenInUse, "stop_page.proximity_alert.location_when_in_use.message_fmt"),
            (.locationDenied, "stop_page.proximity_alert.location_denied.message_fmt"),
            (.notifications, "stop_page.proximity_alert.notifications_denied.message_fmt")
        ]

        for item in templateKeys {
            let template = Bundle(for: DonationCell.self).localizedString(forKey: item.key, value: nil, table: nil)
            let expected = String(format: template, appName)
            #expect(item.reason.alertMessage == expected)
            #expect(item.reason.alertMessage.contains(appName))
            #expect(!item.reason.alertMessage.contains("%"))
        }

        let restrictedKey = "stop_page.proximity_alert.location_restricted.message"
        let expectedRestricted = Bundle(for: DonationCell.self).localizedString(forKey: restrictedKey, value: nil, table: nil)
        #expect(ProximityAlertSettingsReason.locationRestricted.alertMessage == expectedRestricted)
        #expect(!ProximityAlertSettingsReason.locationRestricted.alertMessage.contains("%"))
    }

    @Test func `Alert messages are unique across all reasons`() {
        let reasons: [ProximityAlertSettingsReason] = [
            .locationWhenInUse,
            .locationDenied,
            .locationRestricted,
            .notifications
        ]

        let messages = reasons.map(\.alertMessage)
        #expect(Set(messages).count == reasons.count)
    }

    // MARK: - String Catalog Integrity

    @Test func `Settings reason title keys exist in English catalog with expected copy`() throws {
        let bundle = try #require(englishBundle())

        let keys = [
            "stop_page.proximity_alert.location_when_in_use.title": "Allow Location Always",
            "stop_page.proximity_alert.location_denied.title": "Location Is Off",
            "stop_page.proximity_alert.location_restricted.title": "Location Isn't Available",
            "stop_page.proximity_alert.notifications_denied.title": "Notifications Are Off"
        ]

        for (key, expectedValue) in keys {
            let localized = bundle.localizedString(forKey: key, value: "MISSING", table: nil)
            #expect(localized != "MISSING", "\(key) is missing from the English catalog")
            #expect(localized == expectedValue, "\(key) has unexpected translation in English catalog")
        }
    }

    @Test func `Settings reason message keys exist in English catalog with expected format templates`() throws {
        let bundle = try #require(englishBundle())

        let keys = [
            "stop_page.proximity_alert.location_when_in_use.message_fmt": "%@ has location access only while it's open. Nearby alerts need it in the background too, so they can work with your phone in your pocket.",
            "stop_page.proximity_alert.location_denied.message_fmt": "To get nearby alerts, allow location for %@ in Settings.",
            "stop_page.proximity_alert.location_restricted.message": "Nearby alerts need location access, which may be limited by a setting on this device.",
            "stop_page.proximity_alert.notifications_denied.message_fmt": "Nearby alerts arrive as notifications. Allow them for %@ in Settings."
        ]

        for (key, expectedValue) in keys {
            let localized = bundle.localizedString(forKey: key, value: "MISSING", table: nil)
            #expect(localized != "MISSING", "\(key) is missing from the English catalog")
            #expect(localized == expectedValue, "\(key) has unexpected translation in English catalog")
        }
    }
}
