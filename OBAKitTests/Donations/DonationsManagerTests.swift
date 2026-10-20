//
//  DonationsManagerTests.swift
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

/// A `Bundle` whose `OBAKitConfig` reports a configurable `Donations.Enabled`
/// value, so these tests don't depend on the host app's Info.plist. Each
/// instance is backed by a unique temporary directory because `Bundle` caches
/// instances by path and would otherwise return a previously-created fake.
// `Bundle` is already `@unchecked Sendable`; a subclass has to restate it or the
// compiler warns. Mutated only from the test that owns the instance.
// `nonisolated`: overrides nonisolated Bundle members, which the
// target's main-actor default isolation would conflict with.
private nonisolated class DonationsConfigBundle: Bundle, @unchecked Sendable {
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
        let bundle = try #require(DonationsConfigBundle(path: dir.path))
        bundle.donationsEnabledValue = donationsEnabled
        return bundle
    }
}

@Suite(.serialized)
final class DonationsManagerTests: OBATestCase {

    /// `storefront` is the App Store country code the manager sees. The manager is
    /// returned after its storefront read has finished, so gating is settled.
    private func buildManager(
        appLaunchCount: Int,
        donationsEnabled: Bool = true,
        storefront: String? = "USA",
        notificationCenter: NotificationCenter = NotificationCenter()
    ) async throws -> DonationsManager {
        let manager = DonationsManager(
            bundle: try DonationsConfigBundle.create(donationsEnabled: donationsEnabled),
            userDefaults: userDefaults,
            obacoService: obacoService,
            analytics: nil,
            appLaunchCount: { appLaunchCount },
            notificationCenter: notificationCenter,
            storefrontCountryCode: { storefront }
        )
        await manager.refreshStorefront()
        return manager
    }

    // MARK: - Launch Count Gating

    @Test func `Should request donations first launch is false`() async throws {
        let manager = try await buildManager(appLaunchCount: 1)
        #expect(manager.shouldRequestDonations == false)
    }

    @Test func `Should request donations second launch is false`() async throws {
        let manager = try await buildManager(appLaunchCount: 2)
        #expect(manager.shouldRequestDonations == false)
    }

    @Test func `Should request donations third launch is true`() async throws {
        let manager = try await buildManager(appLaunchCount: 3)
        #expect(manager.shouldRequestDonations == true)
    }

    @Test func `Should request donations later launches is true`() async throws {
        let manager = try await buildManager(appLaunchCount: 100)
        #expect(manager.shouldRequestDonations == true)
    }

    // MARK: - Composition with Other Gates

    @Test func `Should request donations third launch dismissed is false`() async throws {
        let manager = try await buildManager(appLaunchCount: 3)
        manager.dismissDonationsRequests()
        #expect(manager.shouldRequestDonations == false)
    }

    @Test func `Should request donations third launch future reminder is false`() async throws {
        let manager = try await buildManager(appLaunchCount: 3)
        manager.remindUserLater()
        #expect(manager.shouldRequestDonations == false)
    }

    @Test func `Should request donations third launch past reminder is true`() async throws {
        let manager = try await buildManager(appLaunchCount: 3)
        manager.donationRequestReminderDate = Date(timeIntervalSinceNow: -3600)
        #expect(manager.shouldRequestDonations == true)
    }

    @Test func `Should request donations donations disabled is false`() async throws {
        let manager = try await buildManager(appLaunchCount: 3, donationsEnabled: false)
        #expect(manager.shouldRequestDonations == false)
    }

    // MARK: - Storefront Gating

    @Test func `Donations are hidden outside the US storefront`() async throws {
        let manager = try await buildManager(appLaunchCount: 3, storefront: "CAN")
        #expect(manager.donationsEnabled == false)
        #expect(manager.shouldRequestDonations == false)
    }

    @Test func `Donations are shown on the US storefront`() async throws {
        let manager = try await buildManager(appLaunchCount: 3, storefront: "USA")
        #expect(manager.storefrontAllowsDonations)
        #expect(manager.shouldRequestDonations)
    }

    @Test func `Donations stay hidden until the storefront is known`() async throws {
        let manager = try await buildManager(appLaunchCount: 3, storefront: nil)
        #expect(manager.shouldRequestDonations == false)
    }

    @Test func `An unknown storefront keeps the last known answer`() async throws {
        _ = try await buildManager(appLaunchCount: 3, storefront: "USA")
        let manager = try await buildManager(appLaunchCount: 3, storefront: nil)
        #expect(manager.shouldRequestDonations)
    }

    /// The More tab rebuilds on this, so a first-launch answer shows the donate section.
    @Test func `A changed storefront answer posts a notification`() async throws {
        let center = NotificationCenter()
        var posts = 0
        let token = center.addObserver(forName: .donationsEligibilityDidChange, object: nil, queue: nil) { _ in posts += 1 }
        defer { center.removeObserver(token) }

        _ = try await buildManager(appLaunchCount: 3, storefront: "USA", notificationCenter: center)
        #expect(posts == 1)
    }

    @Test func `An unchanged storefront answer posts nothing`() async throws {
        _ = try await buildManager(appLaunchCount: 3, storefront: "USA")

        let center = NotificationCenter()
        var posts = 0
        let token = center.addObserver(forName: .donationsEligibilityDidChange, object: nil, queue: nil) { _ in posts += 1 }
        defer { center.removeObserver(token) }

        _ = try await buildManager(appLaunchCount: 3, storefront: "USA", notificationCenter: center)
        #expect(posts == 0)
    }
}
