//
//  DonationsManagerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
@testable import OBAKit
@testable import OBAKitCore

/// A `Bundle` whose `OBAKitConfig` reports a configurable `Donations.Enabled`
/// value, so these tests don't depend on the host app's Info.plist. Each
/// instance is backed by a unique temporary directory because `Bundle` caches
/// instances by path and would otherwise return a previously-created fake.
private class DonationsConfigBundle: Bundle {
    var donationsEnabledValue = true

    override func object(forInfoDictionaryKey key: String) -> Any? {
        if key == "OBAKitConfig" {
            return ["Donations": ["Enabled": donationsEnabledValue]]
        }
        return super.object(forInfoDictionaryKey: key)
    }

    static func create(donationsEnabled: Bool) throws -> DonationsConfigBundle {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bundle = try XCTUnwrap(DonationsConfigBundle(path: dir.path))
        bundle.donationsEnabledValue = donationsEnabled
        return bundle
    }
}

class DonationsManagerTests: OBATestCase {

    private func buildManager(appLaunchCount: Int, donationsEnabled: Bool = true) throws -> DonationsManager {
        DonationsManager(
            bundle: try DonationsConfigBundle.create(donationsEnabled: donationsEnabled),
            userDefaults: userDefaults,
            obacoService: obacoService,
            analytics: nil,
            appLaunchCount: { appLaunchCount }
        )
    }

    // MARK: - Launch Count Gating

    func test_shouldRequestDonations_firstLaunch_isFalse() throws {
        let manager = try buildManager(appLaunchCount: 1)
        expect(manager.shouldRequestDonations) == false
    }

    func test_shouldRequestDonations_secondLaunch_isFalse() throws {
        let manager = try buildManager(appLaunchCount: 2)
        expect(manager.shouldRequestDonations) == false
    }

    func test_shouldRequestDonations_thirdLaunch_isTrue() throws {
        let manager = try buildManager(appLaunchCount: 3)
        expect(manager.shouldRequestDonations) == true
    }

    func test_shouldRequestDonations_laterLaunches_isTrue() throws {
        let manager = try buildManager(appLaunchCount: 100)
        expect(manager.shouldRequestDonations) == true
    }

    // MARK: - Composition with Other Gates

    func test_shouldRequestDonations_thirdLaunch_dismissed_isFalse() throws {
        let manager = try buildManager(appLaunchCount: 3)
        manager.dismissDonationsRequests()
        expect(manager.shouldRequestDonations) == false
    }

    func test_shouldRequestDonations_thirdLaunch_futureReminder_isFalse() throws {
        let manager = try buildManager(appLaunchCount: 3)
        manager.remindUserLater()
        expect(manager.shouldRequestDonations) == false
    }

    func test_shouldRequestDonations_thirdLaunch_pastReminder_isTrue() throws {
        let manager = try buildManager(appLaunchCount: 3)
        manager.donationRequestReminderDate = Date(timeIntervalSinceNow: -3600)
        expect(manager.shouldRequestDonations) == true
    }

    func test_shouldRequestDonations_donationsDisabled_isFalse() throws {
        let manager = try buildManager(appLaunchCount: 3, donationsEnabled: false)
        expect(manager.shouldRequestDonations) == false
    }
}
