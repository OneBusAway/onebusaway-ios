//
//  TripUserActivityRoutingTests.swift
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

/// A trip activity used to route only through its `webpageURL`, which is nil in
/// a region without a sidecar. Its `userInfo` names the trip in every region.
///
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/1625
@MainActor
@Suite(.serialized)
struct TripUserActivityRoutingTests {

    private typealias Keys = UserActivityBuilder.UserInfoKeys

    private let serviceDate = Date(timeIntervalSince1970: 1_710_273_600)

    private func userInfo(regionID: Any = 1, stopSequence: Any = 12) -> [AnyHashable: Any] {
        [
            Keys.regionID: regionID,
            Keys.stopID: "1_75403",
            Keys.tripID: "1_545_trip",
            Keys.serviceDate: serviceDate,
            Keys.stopSequence: stopSequence,
            Keys.vehicleID: "1_4361"
        ]
    }

    @Test func `Trip deep link reads every key from userInfo`() throws {
        let deepLink = try #require(AppLinksRouter.tripDeepLink(userInfo: userInfo(), title: "545 - Redmond"))

        #expect(deepLink.title == "545 - Redmond")
        #expect(deepLink.regionID == 1)
        #expect(deepLink.stopID == "1_75403")
        #expect(deepLink.tripID == "1_545_trip")
        #expect(deepLink.serviceDate == serviceDate)
        #expect(deepLink.stopSequence == 12)
        #expect(deepLink.vehicleID == "1_4361")
    }

    @Test func `Trip deep link reads NSNumbers restored from a plist`() throws {
        let deepLink = try #require(AppLinksRouter.tripDeepLink(
            userInfo: userInfo(regionID: NSNumber(value: 1), stopSequence: NSNumber(value: 12)),
            title: nil
        ))

        #expect(deepLink.regionID == 1)
        #expect(deepLink.stopSequence == 12)
    }

    @Test func `Trip deep link reads a region ID restored as a string`() throws {
        let deepLink = try #require(AppLinksRouter.tripDeepLink(userInfo: userInfo(regionID: "1"), title: nil))
        #expect(deepLink.regionID == 1)
    }

    @Test func `Trip deep link does not need a vehicle`() throws {
        var info = userInfo()
        info[Keys.vehicleID] = nil

        let deepLink = try #require(AppLinksRouter.tripDeepLink(userInfo: info, title: nil))
        #expect(deepLink.vehicleID == nil)
    }

    @Test func `Trip deep link is nil when a required key is missing`() {
        for key in [Keys.regionID, Keys.stopID, Keys.tripID, Keys.serviceDate, Keys.stopSequence] {
            var info = userInfo()
            info[key] = nil
            #expect(AppLinksRouter.tripDeepLink(userInfo: info, title: nil) == nil, "Missing \(key)")
        }
        #expect(AppLinksRouter.tripDeepLink(userInfo: nil, title: nil) == nil)
    }
}
