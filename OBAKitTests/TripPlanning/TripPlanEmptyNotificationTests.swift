//
//  TripPlanEmptyNotificationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OTPKit
import Testing

/// Pins the OTPKit branch dependency: the planner fallback observes a
/// notification that exists only on `drt-trip-plan-empty`.
@MainActor
@Suite(.serialized)
final class TripPlanEmptyNotificationTests {

    @Test func `OTPKit publishes the tripPlanEmpty notification and its userInfo keys`() {
        #expect(Notifications.tripPlanEmpty.rawValue == "org.onebusaway.otpkit.tripPlanEmpty")
        #expect(Notifications.tripPlanEmptyReasonKey == "reason")
        #expect(Notifications.tripPlanEmptyOriginLatitudeKey == "originLatitude")
        #expect(Notifications.tripPlanEmptyOriginLongitudeKey == "originLongitude")
        #expect(Notifications.tripPlanEmptyDestinationLatitudeKey == "destinationLatitude")
        #expect(Notifications.tripPlanEmptyDestinationLongitudeKey == "destinationLongitude")
    }
}
