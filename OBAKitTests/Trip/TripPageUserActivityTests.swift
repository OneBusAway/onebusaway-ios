//
//  TripPageUserActivityTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import UIKit
import OBAKitCore
@testable import OBAKit

/// `TripViewController` has always published a Handoff activity for its trip.
/// The trip page that replaced it published none.
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/1556
@MainActor
@Suite(.serialized)
final class TripPageUserActivityTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    /// Calls `beginUserActivity()` rather than letting the page appear, which
    /// would start the trip's network loads. `makeOnScreenPage`, not `makePage`:
    /// the activity's title reads the departure's route and headsign, which
    /// `makePage`'s departure doesn't carry, and reading them there traps.
    @Test func `The trip page publishes a Handoff-only activity`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let page = try TripPageFixture.makeOnScreenPage(application: application)

        page.beginUserActivity()

        let activity = try #require(page.userActivity)
        #expect(activity.persistentIdentifier == "region_1_trip_1_40984902")
        #expect(activity.isEligibleForHandoff)
        #expect(!activity.isEligibleForPrediction)
    }

    // MARK: - userInfo

    /// UIKit clears the `userInfo` of an activity a responder owns before it
    /// calls `updateUserActivityState(_:)`, so the page has to put its trip and
    /// region back. The builder also never assigned them in the first place.
    /// See: https://github.com/OneBusAway/onebusaway-ios/issues/1625
    @Test func `A cleared trip activity gets its trip and region back`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let page = try TripPageFixture.makeOnScreenPage(application: application)
        page.beginUserActivity()
        let activity = try #require(page.userActivity)

        clearAndUpdate(activity, from: page)

        #expect(activity.userInfo?[UserActivityBuilder.UserInfoKeys.tripID] as? String == "1_40984902")
        #expect(activity.userInfo?[UserActivityBuilder.UserInfoKeys.regionID] as? Int == 1)
    }

    /// The test region has a sidecar, so the activity also carries a
    /// `webpageURL`, which routes on its own. Dropping it leaves `userInfo` as
    /// the only way in, as in a region without a sidecar.
    @Test func `A cleared trip activity still routes with no webpage URL`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let page = try TripPageFixture.makeOnScreenPage(application: application)
        page.beginUserActivity()
        let activity = try #require(page.userActivity)
        #expect(activity.webpageURL != nil, "Premise: without dropping this URL, the activity would route on it alone")
        activity.webpageURL = nil

        clearAndUpdate(activity, from: page)
        let handled = application.application(UIApplication.shared, continue: activity, restorationHandler: { _ in })

        #expect(handled)
        #expect(application.pendingTripDeepLink?.tripID == "1_40984902")
        #expect(application.pendingTripDeepLink?.regionID == 1)
    }

    /// Does to `activity` what UIKit does before asking `responder` to update it.
    private func clearAndUpdate(_ activity: NSUserActivity, from responder: UIResponder) {
        activity.userInfo = [:]
        responder.updateUserActivityState(activity)
    }
}
