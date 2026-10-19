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
}
