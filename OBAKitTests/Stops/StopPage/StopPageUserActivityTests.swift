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

    private func reappear(_ page: UIViewController) {
        page.beginAppearanceTransition(false, animated: false)
        page.endAppearanceTransition()
        page.beginAppearanceTransition(true, animated: false)
        page.endAppearanceTransition()
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

    /// An application that can load stop 1_10020. This stubs every endpoint a load
    /// touches: `MockDataLoader` fatal-errors on anything unstubbed, which ends the
    /// whole run, not just this test.
    private func applicationLoadingStops(intentDonor: any IntentDonor) -> Application {
        let dataLoader = MockDataLoader(testName: name)

        dataLoader.mock(data: Fixtures.loadData(file: "arrivals_and_departures_for_stop_1_10020_no_realtime.json")) { request in
            request.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false
        }

        let emptySurveys = Data(#"{"surveys":[],"region":{"id":1,"name":"Puget Sound"}}"#.utf8)
        dataLoader.mock(data: emptySurveys) { request in
            request.url?.path.contains("/surveys.json") ?? false
        }

        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        application.intentDonor = intentDonor
        return application
    }

    /// The legacy page publishes only once arrivals have loaded.
    private func loadedLegacyStopPage(intentDonor: any IntentDonor = FakeIntentDonor()) async -> StopViewController {
        let application = applicationLoadingStops(intentDonor: intentDonor)
        let controller = StopViewController(application: application, stopID: "1_10020")
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

    // MARK: - Open Stop donation

    // Opening a stop donates `OpenStopIntent`, which replaces the activity's own
    // prediction. Both pages publish their activity far more often than a rider
    // opens a stop, so each has to donate only once.

    @Test func `Opening a stop page donates Open Stop for that stop`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let donor = FakeIntentDonor()
        application.intentDonor = donor

        _ = try publishedStopPage(application: application)

        #expect(donor.openedStops == ["region_1_stop_1_10914"])
    }

    /// Coming back from a pushed page, such as a trip, isn't a new open.
    @Test func `A stop page that appears again doesn't donate again`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let donor = FakeIntentDonor()
        application.intentDonor = donor
        let page = try publishedStopPage(application: application)

        reappear(page)

        #expect(donor.openedStops == ["region_1_stop_1_10914"])
    }

    /// The legacy page republishes its activity on every arrivals refresh.
    @Test func `The legacy stop page donates once, not on every refresh`() async {
        let donor = FakeIntentDonor()
        let page = await loadedLegacyStopPage(intentDonor: donor)

        await page.viewModel.refresh()

        #expect(donor.openedStops == ["region_1_stop_1_10020"])
    }

    /// The rule both pages share: the same stop's activity again isn't an open,
    /// another stop's is.
    @Test func `Only an activity for a different stop donates again`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let donor = FakeIntentDonor()
        application.intentDonor = donor
        let builder = try #require(application.userActivityBuilder)
        let region = try #require(application.regionsService.currentRegion)
        let stops = try Fixtures.loadSomeStops()
        try #require(stops.count >= 2)
        let first = builder.userActivity(for: stops[0], region: region)

        application.donateOpenStop(stops[0], publishing: first, replacing: nil)
        application.donateOpenStop(stops[0], publishing: builder.userActivity(for: stops[0], region: region), replacing: first)
        application.donateOpenStop(stops[1], publishing: builder.userActivity(for: stops[1], region: region), replacing: first)

        #expect(donor.openedStops == [
            StopEntityMapping.identifier(regionID: region.regionIdentifier, stopID: stops[0].id),
            StopEntityMapping.identifier(regionID: region.regionIdentifier, stopID: stops[1].id)
        ])
    }

    // MARK: - Peeks

    /// A peek appears and publishes like an open page, but the rider only glanced
    /// at it. The last check is what the identifier comparison is for: landing on
    /// screen after the commit publishes again.
    @Test func `A peeked stop page donates only when the peek is committed`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let donor = FakeIntentDonor()
        application.intentDonor = donor
        let page = StopPageViewController(application: application, stop: try #require(Fixtures.loadSomeStops().first))

        page.enterPreviewMode()
        page.loadViewIfNeeded()
        page.beginAppearanceTransition(true, animated: false)
        page.endAppearanceTransition()
        #expect(page.userActivity != nil, "Premise: a peek still publishes its activity")
        #expect(donor.openedStops.isEmpty)

        page.exitPreviewMode()
        #expect(donor.openedStops == ["region_1_stop_1_10914"])

        reappear(page)
        #expect(donor.openedStops == ["region_1_stop_1_10914"])
    }

    @Test func `A peeked legacy stop page donates only when the peek is committed`() async {
        let donor = FakeIntentDonor()
        let page = StopViewController(application: applicationLoadingStops(intentDonor: donor), stopID: "1_10020")

        page.enterPreviewMode()
        page.loadViewIfNeeded()
        await page.viewModel.refresh()
        #expect(page.userActivity != nil, "Premise: a peek still publishes its activity")
        #expect(donor.openedStops.isEmpty)

        page.exitPreviewMode()
        #expect(donor.openedStops == ["region_1_stop_1_10020"])

        await page.viewModel.refresh()
        #expect(donor.openedStops == ["region_1_stop_1_10020"])
    }

    /// Committed before anything loaded, there's no activity to donate for yet.
    @Test func `A peek committed before its stop loads donates when it loads`() async {
        let donor = FakeIntentDonor()
        let page = StopViewController(application: applicationLoadingStops(intentDonor: donor), stopID: "1_10020")

        page.enterPreviewMode()
        page.loadViewIfNeeded()
        page.exitPreviewMode()
        #expect(donor.openedStops.isEmpty)

        await page.viewModel.refresh()
        #expect(donor.openedStops == ["region_1_stop_1_10020"])
    }

    /// The one peek that used to skip preview mode. SwiftUI's preview can't be
    /// committed, so it never donates.
    @Test func `A Bookmarks peek doesn't donate`() async throws {
        let donor = FakeIntentDonor()
        let application = applicationLoadingStops(intentDonor: donor)
        let preview = StopViewControllerPreview(stopID: "1_10020", application: application)
        let page = try #require(preview.makeController() as? StopPageViewController)

        page.loadViewIfNeeded()
        await page.viewModel.refresh()
        page.beginAppearanceTransition(true, animated: false)
        page.endAppearanceTransition()

        #expect(page.userActivity != nil, "Premise: the stop loaded and its activity was published")
        #expect(donor.openedStops.isEmpty)
    }

    // MARK: - Stops the intent opened

    /// The system already records intents it runs. Only that open is skipped: the
    /// rider opening the same stop by hand afterward still counts.
    @Test func `A stop opened by Open Stop isn't donated again`() async throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let donor = FakeIntentDonor()
        application.intentDonor = donor

        OpenStopRequest.post(AppLinksRouter.StopDestination(stopID: "1_10914", regionID: 1))
        await poll(until: { application.stopOpenedByIntent != nil }, "Open Stop request was never handled")

        let opened = try publishedStopPage(application: application)
        #expect(opened.userActivity != nil, "Premise: the page published its activity")
        #expect(donor.openedStops.isEmpty)

        _ = try publishedStopPage(application: application)
        #expect(donor.openedStops == ["region_1_stop_1_10914"])
    }

    /// A request for another region is dropped, so no page will ever take it. If
    /// it stayed set, the rider opening that stop there later wouldn't be donated.
    @Test func `A dropped Open Stop request isn't remembered`() {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let destination = AppLinksRouter.StopDestination(stopID: "1_10914", regionID: 999)
        application.stopOpenedByIntent = destination

        application.queueOrOpenStop(destination)

        #expect(application.stopOpenedByIntent == nil)
    }

    @Test func `Another stop still donates while an Open Stop request is waiting`() async throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let donor = FakeIntentDonor()
        application.intentDonor = donor

        OpenStopRequest.post(AppLinksRouter.StopDestination(stopID: "1_75403", regionID: 1))
        await poll(until: { application.stopOpenedByIntent != nil }, "Open Stop request was never handled")

        _ = try publishedStopPage(application: application)

        #expect(donor.openedStops == ["region_1_stop_1_10914"])
    }

    // MARK: - Map panel stop sheet

    /// The sheet clears its activity when it disappears and publishes again when
    /// it comes back, which isn't a new open. A new sheet is.
    @Test func `The map panel's stop sheet donates once per sheet`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let donor = FakeIntentDonor()
        application.intentDonor = donor
        let stop = try #require(Fixtures.loadSomeStops().first)

        let sheet = StopPageActionPresenter(application: application, presentingController: { nil })
        _ = sheet.makeSheetUserActivity(stop: stop)
        _ = sheet.makeSheetUserActivity(stop: stop)
        #expect(donor.openedStops == ["region_1_stop_1_10914"])

        let newSheet = StopPageActionPresenter(application: application, presentingController: { nil })
        _ = newSheet.makeSheetUserActivity(stop: stop)
        #expect(donor.openedStops == ["region_1_stop_1_10914", "region_1_stop_1_10914"])
    }
}
