//
//  StopUserActivityRoutingTests.swift
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

/// Donated stop shortcuts (`NSUserActivity`) used to launch the app and then
/// do nothing: `routeStop` required a live `apiService` and matching
/// `currentRegion` before it would accept the activity, and it ignored the
/// stop `webpageURL` when Shortcuts stripped `userInfo`.
///
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/1221
@MainActor
@Suite(.serialized)
struct StopUserActivityRoutingTests {

    private let stopKey = UserActivityBuilder.UserInfoKeys.stopID
    private let regionKey = UserActivityBuilder.UserInfoKeys.regionID
    private let stopURL = URL(string: "https://onebusaway.co/regions/1/stops/1_75403")!
    private let tripURL = URL(string: "https://onebusaway.co/regions/1/stops/1_75403/trips?trip_id=1_545_trip&service_date=1710273600.0&stop_sequence=12")!

    @Test func `Stop destination reads a Swift Int region ID`() {
        let destination = AppLinksRouter.stopDestination(
            userInfo: [stopKey: "1_75403", regionKey: 1],
            webpageURL: nil
        )

        #expect(destination?.stopID == "1_75403")
        #expect(destination?.regionID == 1)
    }

    @Test func `Stop destination reads an NSNumber region ID restored by Shortcuts`() {
        let destination = AppLinksRouter.stopDestination(
            userInfo: [stopKey: "1_75403", regionKey: NSNumber(value: 1)],
            webpageURL: nil
        )

        #expect(destination?.stopID == "1_75403")
        #expect(destination?.regionID == 1)
    }

    @Test func `Stop destination reads a region ID restored as a string`() {
        let destination = AppLinksRouter.stopDestination(
            userInfo: [stopKey: "1_75403", regionKey: "1"],
            webpageURL: nil
        )

        #expect(destination?.stopID == "1_75403")
        #expect(destination?.regionID == 1)
    }

    @Test func `Stop destination uses the stop webpage URL when userInfo is missing the keys`() {
        let destination = AppLinksRouter.stopDestination(userInfo: [:], webpageURL: stopURL)

        #expect(destination?.stopID == "1_75403")
        #expect(destination?.regionID == 1)
    }

    @Test func `Stop destination prefers userInfo over the webpage URL`() {
        let destination = AppLinksRouter.stopDestination(
            userInfo: [stopKey: "1_999", regionKey: 2],
            webpageURL: stopURL
        )

        #expect(destination?.stopID == "1_999")
        #expect(destination?.regionID == 2)
    }

    @Test func `Stop destination ignores a trip deep link URL`() {
        let destination = AppLinksRouter.stopDestination(userInfo: nil, webpageURL: tripURL)
        #expect(destination == nil)
    }

    @Test func `Stop destination is nil when both userInfo and webpage URL are missing`() {
        #expect(AppLinksRouter.stopDestination(userInfo: nil, webpageURL: nil) == nil)
        #expect(AppLinksRouter.stopDestination(userInfo: [:], webpageURL: nil) == nil)
    }
}
