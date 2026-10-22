//
//  StopPageUserActivityTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

@testable import OBAKit
@testable import OBAKitCore
import Foundation
import Testing
import UIKit

/// UIKit clears the `userInfo` of an activity a responder owns before it calls
/// `updateUserActivityState(_:)`, so a stop page has to put its stop and region
/// back. Without them a Siri suggestion can route only through `webpageURL`,
/// which a region without a sidecar doesn't have.
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/1556
@MainActor
@Suite(.serialized)
final class StopPageUserActivityTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    // MARK: - Helpers

    /// A stop page that has published its activity. Appearing publishes it
    /// synchronously, and loads nothing: the page's arrivals load from a SwiftUI
    /// `.task`, which needs a window.
    private func publishedStopPage(application: Application) throws -> StopPageViewController {
        let page = StopPageViewController(application: application, stop: try #require(Fixtures.loadSomeStops().first))
        page.loadViewIfNeeded()
        page.beginAppearanceTransition(true, animated: false)
        page.endAppearanceTransition()
        return page
    }

    /// Does to `activity` what UIKit does before asking `responder` to update it.
    private func clearAndUpdate(_ activity: NSUserActivity, from responder: UIResponder) {
        activity.userInfo = [:]
        responder.updateUserActivityState(activity)
    }

    // MARK: - Stop page

    @Test func `A cleared stop activity gets its stop and region back`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let page = try publishedStopPage(application: application)
        let activity = try #require(page.userActivity)

        clearAndUpdate(activity, from: page)

        #expect(activity.userInfo?[UserActivityBuilder.UserInfoKeys.stopID] as? String == "1_10914")
        #expect(activity.userInfo?[UserActivityBuilder.UserInfoKeys.regionID] as? Int == 1)
    }

    /// The test region has a sidecar, so the activity also carries a
    /// `webpageURL`, which routes on its own. Dropping it leaves `userInfo` as
    /// the only way in, as in a region without a sidecar.
    @Test func `A cleared stop activity still routes with no webpage URL`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let page = try publishedStopPage(application: application)
        let activity = try #require(page.userActivity)
        #expect(activity.webpageURL != nil, "Premise: without dropping this URL, the activity would route on it alone")
        activity.webpageURL = nil

        clearAndUpdate(activity, from: page)
        let handled = application.application(UIApplication.shared, continue: activity, restorationHandler: { _ in })

        #expect(handled)
        #expect(application.pendingStopID == "1_10914")
        #expect(application.pendingStopRegionID == 1)
    }

    // MARK: - Legacy stop page

    /// The legacy page publishes only once arrivals have loaded, so this stubs
    /// every endpoint a load touches. `MockDataLoader` fatal-errors on anything
    /// unstubbed, which ends the whole run, not just this test.
    private func loadedLegacyStopPage() async -> StopViewController {
        let dataLoader = MockDataLoader(testName: name)

        dataLoader.mock(data: Fixtures.loadData(file: "arrivals_and_departures_for_stop_1_10020_no_realtime.json")) { request in
            request.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false
        }

        let emptySurveys = Data(#"{"surveys":[],"region":{"id":1,"name":"Puget Sound"}}"#.utf8)
        dataLoader.mock(data: emptySurveys) { request in
            request.url?.path.contains("/surveys.json") ?? false
        }

        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        let controller = StopViewController(application: buildApplication(queue: queue, dataLoader: dataLoader), stopID: "1_10020")
        controller.loadViewIfNeeded()
        await controller.viewModel.refresh()
        return controller
    }

    @Test func `The legacy stop page's cleared activity gets its stop and region back`() async throws {
        let page = await loadedLegacyStopPage()
        let activity = try #require(page.userActivity)

        clearAndUpdate(activity, from: page)

        #expect(activity.userInfo?[UserActivityBuilder.UserInfoKeys.stopID] as? String == "1_10020")
        #expect(activity.userInfo?[UserActivityBuilder.UserInfoKeys.regionID] as? Int == 1)
    }
}
