//
//  DonationLearnMoreViewTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class DonationLearnMoreViewTests: OBATestCase {

    /// Analytics counts how often riders open the explanation, against how often
    /// they then donate or close it.
    @Test func `Opening Learn More reports that it was shown`() throws {
        let analytics = AnalyticsMock()
        let manager = DonationsManager(
            bundle: .main,
            userDefaults: userDefaults,
            obacoService: obacoService,
            analytics: analytics,
            appLaunchCount: { 10 },
            storefrontCountryCode: { "USA" }
        )
        let model = DonationModel(obacoService: obacoService, donationsManager: manager, analytics: analytics, donationPushNotificationID: nil)
        let view = DonationLearnMoreView()
            .environmentObject(model)
            .environmentObject(AnalyticsModel(analytics))
        #expect(analytics.reportedEvents.isEmpty)

        let host = UIHostingController(rootView: view)
        let window = UIWindow(windowScene: try testWindowScene())
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = host
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        host.view.layoutIfNeeded()
        // One run-loop pass so the first-appearance callback runs.
        RunLoop.main.run(until: Date())

        #expect(analytics.reportedEvents.map(\.label) == [AnalyticsLabels.donationLearnMoreShown])
        #expect(analytics.reportedEvents.first?.pageURL == "app://localhost/donations")
    }
}
