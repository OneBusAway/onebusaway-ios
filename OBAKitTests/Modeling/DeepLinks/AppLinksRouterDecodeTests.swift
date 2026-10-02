//
//  AppLinksRouterDecodeTests.swift
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

/// The receiving end of a shared trip link. `AppLinksRouterDeepLinkFormatTests`
/// covers the URL shape without an `Application`; this covers the decode that
/// turns a real shared link back into the model the trip screen is opened with.
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/449
@MainActor
@Suite(.serialized)
final class AppLinksRouterDecodeTests: OBATestCase {

    private func makeRouter() throws -> AppLinksRouter {
        let queue = OperationQueue()
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        return try #require(AppLinksRouter(application: application))
    }

    /// The URL is one the app actually produced, so a change to the share format
    /// that drops the parameter fails here rather than in someone's Messages.
    @Test func `A shared link carries its destination stop into the deep link`() throws {
        let url = try #require(URL(string: "https://onebusaway.co/regions/1/stops/1_660/trips?trip_id=1_694514730&service_date=1774854000.0&stop_sequence=19&destination_stop_id=1_1040"))

        let link = try #require(makeRouter().decode(url: url))

        #expect(link.destinationStopID == "1_1040")
        #expect(link.stopID == "1_660")
        #expect(link.stopSequence == 19)
        #expect(link.regionID == 1)
    }

    /// Sharing without choosing a destination is still supported, and must not
    /// invent one.
    @Test func `A link with no destination decodes without one`() throws {
        let url = try #require(URL(string: "https://onebusaway.co/regions/1/stops/1_660/trips?trip_id=1_694514730&service_date=1774854000.0&stop_sequence=19"))

        let link = try #require(makeRouter().decode(url: url))

        #expect(link.destinationStopID == nil)
        #expect(link.stopID == "1_660")
    }
}
