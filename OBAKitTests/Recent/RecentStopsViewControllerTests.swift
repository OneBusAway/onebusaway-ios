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
import SwiftUI
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class RecentStopsViewControllerTests: OBATestCase {

    var queue: OperationQueue!
    var dataLoader: MockDataLoader!
    var app: Application!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1

        dataLoader = MockDataLoader(testName: name)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        app = buildApplication(queue: queue, dataLoader: dataLoader)
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    private func makeValidAlarm(id: String = "alarm_1") throws -> Alarm {
        let alarm = try Fixtures.loadAlarm(id: id)
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
        return alarm
    }

    private func seedRecentStop() throws -> Stop {
        let stops = try Fixtures.loadSomeStops()
        let stop = try #require(stops.first)
        stop.regionIdentifier = Fixtures.pugetSoundRegion.regionIdentifier
        app.userDataStore.addRecentStop(stop, region: Fixtures.pugetSoundRegion)
        return stop
    }

    // MARK: - Controller Initialization & Lifecycle

    @Test func testInitializationAndDefaultProperties() throws {
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

        let hostingController = try #require(controller.hostingController)
        #expect(controller.children.contains(hostingController))
        #expect(hostingController.view.superview === controller.view)
    }

    @Test func testDeleteAllButtonEnabledStateReflectsRecentStops() throws {
        let controller = RecentStopsViewController(application: app)
        controller.loadViewIfNeeded()
        #expect(controller.navigationItem.rightBarButtonItem?.isEnabled == false)

        // Alarms alone do not enable Delete All (Delete All only clears recent stops).
        let alarm = try makeValidAlarm()
        app.userDataStore.add(alarm: alarm)
        controller.viewWillAppear(false)
        #expect(controller.navigationItem.rightBarButtonItem?.isEnabled == false)

        // Adding a recent stop enables Delete All.
        _ = try seedRecentStop()
        controller.viewWillAppear(false)
        #expect(controller.navigationItem.rightBarButtonItem?.isEnabled == true)

        // Deleting all recent stops disables Delete All again.
        controller.viewModel.deleteAllRecentStops()
        #expect(controller.navigationItem.rightBarButtonItem?.isEnabled == false)
    }

    @Test func testDeleteAllPresentsConfirmationAlert() throws {
        _ = try seedRecentStop()
        let controller = RecentStopsViewController(application: app)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()

        controller.viewWillAppear(false)
        controller.deleteAll()

        let alert = try #require(controller.presentedViewController as? UIAlertController)
        let expectedTitle = OBAKit.OBALoc(
            "recent_stops.confirmation_alert.title",
            value: "Are you sure you want to delete all of your recent stops?",
            comment: "Title for a confirmation alert displayed before the user deletes all of their recent stops."
        )
        #expect(alert.title == expectedTitle)
        #expect(alert.actions.count == 2)
        #expect(alert.actions.contains(where: { $0.style == .destructive && $0.title == Strings.delete }))
        #expect(alert.actions.contains(where: { $0.style == .cancel }))
    }

    // MARK: - Empty State & Explore Map

    @Test func testExploreMapNavigationSwitchesToMapTab() throws {
        let root = ClassicApplicationRootController(application: app)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = root

        let controller = root.recentStopsController
        controller.loadViewIfNeeded()

        root.selectedIndex = ClassicApplicationRootController.Page.recentStops.rawValue
        #expect(root.selectedIndex != ClassicApplicationRootController.Page.map.rawValue)

        let listView = try #require(controller.hostingController?.rootView)
        #expect(listView.isShowingEmptyState)

        listView.navigation.exploreMap()
        #expect(root.selectedIndex == ClassicApplicationRootController.Page.map.rawValue)
    }

    // MARK: - Section & Row State

    @Test func testListViewSectionsWhenEmpty() throws {
        let controller = RecentStopsViewController(application: app)
        controller.loadViewIfNeeded()
        controller.viewWillAppear(false)

        let listView = try #require(controller.hostingController?.rootView)
        #expect(listView.isShowingEmptyState)
        #expect(listView.alarmRows.isEmpty)
        #expect(controller.viewModel.recentStops.isEmpty)
        #expect(listView.stopsSectionTitle == nil)
    }

    @Test func testListViewSectionsWithStopsOnly() throws {
        let stop = try seedRecentStop()

        let controller = RecentStopsViewController(application: app)
        controller.loadViewIfNeeded()
        controller.viewWillAppear(false)

        let listView = try #require(controller.hostingController?.rootView)
        #expect(!listView.isShowingEmptyState)
        #expect(listView.alarmRows.isEmpty)
        #expect(controller.viewModel.recentStops.map(\.id) == [stop.id])
        // When there are no alarms, the stops section title is nil.
        #expect(listView.stopsSectionTitle == nil)
    }

    @Test func testListViewSectionsWithAlarmsAndStops() throws {
        let alarm = try makeValidAlarm()
        app.userDataStore.add(alarm: alarm)
        let stop = try seedRecentStop()

        let controller = RecentStopsViewController(application: app)
        controller.loadViewIfNeeded()
        controller.viewWillAppear(false)

        let listView = try #require(controller.hostingController?.rootView)
        #expect(!listView.isShowingEmptyState)
        #expect(listView.alarmRows.count == 1)
        #expect(listView.alarmRows.first?.id == alarm.url)
        #expect(controller.viewModel.recentStops.map(\.id) == [stop.id])
        // Stops section title changes to Strings.recentStops when alarms exist.
        #expect(listView.stopsSectionTitle == Strings.recentStops)
    }

    @Test func testListViewOmitsAlarmsWithoutDeepLink() throws {
        let alarm = try Fixtures.loadAlarm()
        alarm.set(tripDate: Date(timeIntervalSinceNow: 300), alarmOffset: 2)
        alarm.deepLink = nil
        app.userDataStore.add(alarm: alarm)

        let controller = RecentStopsViewController(application: app)
        controller.loadViewIfNeeded()
        controller.viewWillAppear(false)

        let listView = try #require(controller.hostingController?.rootView)
        #expect(listView.alarmRows.isEmpty)
        #expect(listView.isShowingEmptyState)
    }

    // MARK: - Actions & Navigation

    @Test func testSelectStopNavigatesToStopController() throws {
        let stop = try seedRecentStop()
        let controller = RecentStopsViewController(application: app)
        let nav = UINavigationController(rootViewController: controller)
        controller.loadViewIfNeeded()
        controller.viewWillAppear(false)

        #expect(nav.viewControllers.count == 1)
        let listView = try #require(controller.hostingController?.rootView)
        listView.navigation.selectStop(stop)

        #expect(nav.viewControllers.count == 2)
        let topVC = nav.topViewController
        let pushedStopID = (topVC as? StopPageViewController)?.viewModel.stopID ?? (topVC as? StopViewController)?.stopID
        #expect(pushedStopID == stop.id)
    }

    @Test func testDeleteAlarmActionRemovesAlarm() throws {
        dataLoader.mock(data: Data()) { req in
            req.url?.path.contains("/alarms/") ?? false
        }

        let alarm = try makeValidAlarm()
        app.userDataStore.add(alarm: alarm)

        let controller = RecentStopsViewController(application: app)
        controller.loadViewIfNeeded()
        controller.viewWillAppear(false)

        let listView = try #require(controller.hostingController?.rootView)
        let alarmRow = try #require(listView.alarmRows.first)

        listView.navigation.deleteAlarm(alarmRow)

        #expect(controller.viewModel.alarms.isEmpty)
        #expect(!app.userDataStore.alarms.map(\.url).contains(alarm.url))
    }

    @Test func testShowDeepLinkNavigatesToTrip() async throws {
        let arrivalData = Fixtures.loadData(file: "arrival-and-departure-for-stop-1_11420.json")
        dataLoader.mock(data: arrivalData) { request in
            request.url?.path.contains("/api/where/arrival-and-departure-for-stop/") ?? false
        }

        let controller = RecentStopsViewController(application: app)
        let nav = UINavigationController(rootViewController: controller)
        controller.loadViewIfNeeded()

        let deepLink = ArrivalDepartureDeepLink(
            title: "Route 10",
            regionID: Fixtures.pugetSoundRegion.regionIdentifier,
            stopID: "1_11420",
            tripID: "1_12345",
            serviceDate: Date(timeIntervalSince1970: 1558076400),
            stopSequence: 5,
            vehicleID: nil
        )

        await controller.showDeepLink(deepLink: deepLink)

        #expect(nav.viewControllers.count == 2)
    }
}
