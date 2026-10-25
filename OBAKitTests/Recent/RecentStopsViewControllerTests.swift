//
//  RecentStopsViewControllerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class RecentStopsViewControllerTests: OBATestCase {

    var queue: OperationQueue!
    var app: Application!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1

        let dataLoader = MockDataLoader(testName: name)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        app = buildApplication(queue: queue, dataLoader: dataLoader)
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    // MARK: - Controller Initialization & Lifecycle

    @Test func testInitializationAndDefaultProperties() {
        let controller = RecentStopsViewController(application: app)

        let expectedTitle = OBAKit.OBALoc("recent_stops_controller.title", value: "Recent", comment: "The title of the Recent Stops controller.")
        #expect(controller.title == expectedTitle)
        #expect(controller.tabBarItem.image == Icons.recentTabIcon)
        #expect(controller.tabBarItem.selectedImage == Icons.recentSelectedTabIcon)

        controller.loadViewIfNeeded()

        let expectedDeleteAllTitle = OBAKit.OBALoc("recent_stops.delete_all", value: "Delete All", comment: "A button that deletes all of the recent stops in the app.")
        #expect(controller.navigationItem.rightBarButtonItem?.title == expectedDeleteAllTitle)
        #expect(controller.navigationItem.rightBarButtonItem?.action == #selector(RecentStopsViewController.deleteAll))
        #expect(controller.view.backgroundColor == ThemeColors.shared.systemBackground)
    }

    // MARK: - Empty Data

    @Test func testEmptyDataConfiguration() {
        let controller = RecentStopsViewController(application: app)
        let dummyListView = OBAListView()
        let emptyData = controller.emptyData(for: dummyListView)

        guard case .standard(let viewModel) = emptyData else {
            Issue.record("Expected standard empty data view model")
            return
        }

        let expectedTitle = OBAKit.OBALoc("recent_stops.empty_set.title", value: "No Recent Stops", comment: "Title for the empty set indicator on the Recent Stops controller.")
        let expectedSubtitle = OBAKit.OBALoc("recent_stops.empty_set.body", value: "Transit stops that you view in the app will appear here.", comment: "Body for the empty set indicator on the Recent Stops controller.")
        let expectedButtonText = OBAKit.OBALoc("recent_stops.empty_set.button", value: "Find Stops on Maps", comment: "The button title for taking the user to the map view to find stops.")

        #expect(viewModel.title == expectedTitle)
        #expect(viewModel.body == expectedSubtitle)
        #expect(viewModel.buttonConfig?.text == expectedButtonText)
        #expect(viewModel.buttonConfig?.largeContentImage == Icons.mapTabIcon)
        #expect(viewModel.buttonConfig?.showsActivityIndicatorOnTap == false)

        // Verify button action executes without crashing
        viewModel.buttonConfig?.action()
    }

    // MARK: - Section Generation

    @Test func testItemsSectionsWhenEmpty() {
        let controller = RecentStopsViewController(application: app)
        let dummyListView = OBAListView()
        let sections = controller.items(for: dummyListView)

        #expect(sections.isEmpty)
    }

    @Test func testItemsSectionsWithStopsOnly() throws {
        let stops = try Fixtures.loadSomeStops()
        let stop = stops.first!
        stop.regionIdentifier = Fixtures.pugetSoundRegion.regionIdentifier
        app.userDataStore.addRecentStop(stop, region: Fixtures.pugetSoundRegion)

        let controller = RecentStopsViewController(application: app)
        controller.viewWillAppear(false)

        let dummyListView = OBAListView()
        let sections = controller.items(for: dummyListView)

        #expect(sections.count == 1)
        #expect(sections[0].id == "recent_stops")
        // When there are no alarms, the stops section title is nil
        #expect(sections[0].title == nil)
        #expect(sections[0].contents.count == 1)
        #expect(sections[0].contents.first?.as(StopRowItem.self)?.stopID == stop.id)
    }

    @Test func testItemsSectionsWithAlarmsAndStops() throws {
        let alarm = try Fixtures.loadAlarm()
        alarm.set(tripDate: Date(timeIntervalSinceNow: 300), alarmOffset: 2)
        alarm.deepLink = ArrivalDepartureDeepLink(
            title: "Alarm Title",
            regionID: 1,
            stopID: "1_75403",
            tripID: "trip_1",
            serviceDate: Date(timeIntervalSinceReferenceDate: 0),
            stopSequence: 1,
            vehicleID: nil
        )
        app.userDataStore.add(alarm: alarm)

        let stops = try Fixtures.loadSomeStops()
        let stop = stops.first!
        stop.regionIdentifier = Fixtures.pugetSoundRegion.regionIdentifier
        app.userDataStore.addRecentStop(stop, region: Fixtures.pugetSoundRegion)

        let controller = RecentStopsViewController(application: app)
        controller.viewWillAppear(false)

        let dummyListView = OBAListView()
        let sections = controller.items(for: dummyListView)

        #expect(sections.count == 2)

        // Alarms section
        #expect(sections[0].id == "alarms")
        let expectedAlarmsTitle = OBAKit.OBALoc("recent_stops_controller.alarms_section.title", value: "Alarms", comment: "Title of the Alarms section of the Recents controller")
        #expect(sections[0].title == expectedAlarmsTitle)
        #expect(sections[0].contents.count == 1)

        // Stops section title changes to Strings.recentStops when alarms exist
        #expect(sections[1].id == "recent_stops")
        #expect(sections[1].title == Strings.recentStops)
        #expect(sections[1].contents.count == 1)
    }

    // MARK: - Context Menu

    @Test func testContextMenuReturnsPreviewProviderForStopRowItem() throws {
        let controller = RecentStopsViewController(application: app)
        let stop = try Fixtures.loadSomeStops().first!
        let rowItem = StopRowItem(withStop: stop, onSelect: nil, onDelete: nil)

        let menuActions = controller.contextMenu(OBAListView(), for: rowItem.typeErased)
        let actions = try #require(menuActions)

        let previewController = actions.previewProvider?()
        #expect(previewController != nil)

        actions.performPreviewAction?()
    }

    @Test func testContextMenuReturnsNilForUnrecognizedItem() {
        let controller = RecentStopsViewController(application: app)
        let genericItem = OBAListRowView.DefaultViewModel(title: "Generic Item").typeErased

        let menuActions = controller.contextMenu(OBAListView(), for: genericItem)
        #expect(menuActions == nil)
    }
}
