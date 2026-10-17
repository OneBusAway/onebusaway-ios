//
//  PageTitleAccessibilityTests.swift
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

/// The stop and trip pages had no title, so the back button on any page pushed
/// after them said only "Back", and the trip page's own back control said "Back"
/// too: a VoiceOver rider couldn't tell where it went.
@MainActor
@Suite(.serialized)
final class PageTitleAccessibilityTests: OBATestCase {

    private var queue: OperationQueue!
    private var application: Application!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    /// The pushed stop page has no title in its bar (the header card carries the
    /// stop), so it names itself on the next page's back button instead.
    @Test func `The stop page names the stop on the next page's back button`() async throws {
        let stop = try #require(Fixtures.loadSomeStops().first)
        let controller = StopPageViewController(application: application, stop: stop)
        controller.loadViewIfNeeded()
        // The chrome is rebuilt from the stop on the main queue.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }

        #expect(controller.navigationItem.backButtonTitle == stop.name)
    }

    @Test func `The trip page is titled with its route and headsign`() throws {
        let page = try TripPageFixture.makeOnScreenPage(application: application)
        let departure = try #require(page.viewModel.tripConvertible.arrivalDeparture)

        let title = try #require(page.title)
        #expect(title.contains(departure.routeShortName))
        #expect(title.contains(try #require(departure.tripHeadsign)))
    }
}
