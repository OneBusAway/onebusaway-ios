//
//  StopPreferencesViewTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import SwiftUI
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast

private final class PreferencesRecorder: StopPreferencesViewDelegate {
    private(set) var updates: [(stopID: StopID, preferences: StopPreferences)] = []

    func stopPreferences(stopID: StopID, updated stopPreferences: StopPreferences) {
        updates.append((stopID, stopPreferences))
    }
}

/// The route filter both stop pages open through `StopPreferencesWrappedView`.
///
/// The sheet has no Save or Cancel: it reports the current selection to its
/// delegate whenever its body is evaluated, starting with the first render, and
/// Done only dismisses it. Toggling a row can't be driven from a test, since the
/// selection lives in the hosted `List`'s own state.
@Suite(.serialized)
final class StopPreferencesViewTests: OBATestCase {

    private var queue: OperationQueue!
    private var window: UIWindow?

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        window?.isHidden = true
        window?.rootViewController = nil
        queue.cancelAllOperations()
    }

    // MARK: - Fixtures

    /// Stop 1_29247 serves 43, 48, 167, 197, 271, 277, 540, 541, 542 and 556.
    /// Only 540, 542 and 556 have long names. `routeIdsReversed` lists them
    /// backwards in the payload, so the order a test sees comes from the sort.
    private func stop(routeIdsReversed: Bool = false) throws -> Stop {
        var json = try JSONSerialization.jsonObject(with: Fixtures.loadData(file: "stops_for_location_seattle.json")) as! [String: Any]
        var data = json["data"] as! [String: Any]
        let stops = (data["list"] as! [[String: Any]]).filter { $0["id"] as? String == "1_29247" }
        data["list"] = stops.map { stop in
            var stop = stop
            if routeIdsReversed {
                stop["routeIds"] = Array((stop["routeIds"] as! [String]).reversed())
            }
            return stop
        }
        json["data"] = data
        let payload = try JSONSerialization.data(withJSONObject: json)
        let list = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<[Stop]>.self, from: payload).list
        return try #require(list.first)
    }

    private let allRouteIDs: Set<RouteID> = [
        "1_100223", "1_100228", "1_100059", "1_100088", "1_100162", "1_100168",
        "40_100235", "40_102640", "40_100511", "40_100451"
    ]

    // MARK: - View model

    @Test func `Every route at the stop starts selected, in route number order`() throws {
        let viewModel = StopPreferencesViewModel(try stop(routeIdsReversed: true))

        #expect(viewModel.stopID == "1_29247")
        #expect(viewModel.availableRoutes.map(\.id) == [
            "1_100223", "1_100228", "1_100059", "1_100088", "1_100162", "1_100168",
            "40_100235", "40_102640", "40_100511", "40_100451"
        ])
        #expect(viewModel.selectedRoutes == allRouteIDs)
        #expect(viewModel.hiddenRoutes.isEmpty)
    }

    @Test func `A route row shows its long name when it has one, otherwise its number, and its agency`() throws {
        let rows = Dictionary(uniqueKeysWithValues: StopPreferencesViewModel(try stop()).availableRoutes.map { ($0.id, $0) })

        let kirkland = try #require(rows["40_100235"])
        #expect(kirkland.displayName == "Kirkland - University District")
        #expect(kirkland.agencyName == "Sound Transit")

        let route48 = try #require(rows["1_100228"])
        #expect(route48.displayName == "48")
        #expect(route48.agencyName == "Metro Transit")
    }

    @Test func `Hiding routes deselects exactly those routes`() throws {
        var viewModel = StopPreferencesViewModel(try stop())

        viewModel.hiddenRoutes = ["1_100228", "40_100511"]

        #expect(viewModel.selectedRoutes == allRouteIDs.subtracting(["1_100228", "40_100511"]))
        #expect(viewModel.hiddenRoutes == ["1_100228", "40_100511"])

        viewModel.selectedRoutes.remove("1_100059")
        #expect(viewModel.hiddenRoutes == ["1_100228", "40_100511", "1_100059"])
    }

    // MARK: - Hosted sheet

    private func host(_ view: StopPreferencesWrappedView, application: CoreApplication) throws {
        let host = UIHostingController(rootView: view.environment(\.coreApplication, application))
        let window = UIWindow(windowScene: try testWindowScene())
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = host
        window.isHidden = false
        self.window = window
        host.view.layoutIfNeeded()
    }

    @Test func `Opening the filter reports the hidden routes with the stop's saved sort order`() throws {
        let loader = MockDataLoader(testName: name)
        Fixtures.stubAllAgencyAlerts(dataLoader: loader)
        let application = buildApplication(queue: queue, dataLoader: loader)
        let region = try #require(application.currentRegion)
        let stop = try stop()
        application.stopPreferencesDataStore.set(
            stopPreferences: StopPreferences(sortType: .route, hiddenRoutes: []),
            stop: stop,
            region: region
        )

        let recorder = PreferencesRecorder()
        try host(
            StopPreferencesWrappedView(stop, initialHiddenRoutes: ["1_100228", "1_999999"], delegate: recorder),
            application: application
        )

        let update = try #require(recorder.updates.last)
        #expect(update.stopID == "1_29247")
        #expect(update.preferences.sortType == .route)
        // 1_999999 isn't served by this stop, so it drops out.
        #expect(update.preferences.hiddenRoutes == ["1_100228"])
    }

    @Test func `Without a current region the filter reports nothing`() throws {
        let loader = MockDataLoader(testName: name)
        stubRegions(dataLoader: loader)
        Fixtures.stubAllAgencyAlerts(dataLoader: loader)
        let config = AppConfig(
            regionsBaseURL: regionsURL,
            apiKey: apiKey,
            appVersion: appVersion,
            userDefaults: userDefaults,
            analytics: AnalyticsMock(),
            queue: queue,
            locationService: LocationService(userDefaults: userDefaults, locationManager: LocationManagerMock()),
            bundledRegionsFilePath: bundledRegionsPath,
            regionsAPIPath: regionsAPIPath,
            dataLoader: loader
        )
        let application = Application(config: config)
        #expect(application.currentRegion == nil)

        let recorder = PreferencesRecorder()
        try host(
            StopPreferencesWrappedView(try stop(), initialHiddenRoutes: ["1_100228"], delegate: recorder),
            application: application
        )

        #expect(recorder.updates.isEmpty)
    }
}

// swiftlint:enable force_cast
