//
//  DepartureFilterMenuTests.swift
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

/// Selection in the Departure Type menu has to ride on `UIAction.state`. A
/// checkmark image renders identically, which is why this regressed once already
/// — but VoiceOver only announces the former, so the image version leaves the
/// menu unreadable to anyone not looking at it.
@MainActor
@Suite(.serialized)
final class DepartureFilterMenuTests: OBATestCase {

    private var queue: OperationQueue!
    private var application: Application!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        userDefaults.set(true, forKey: FeatureFlags.useNewStopPageKey)
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    // MARK: - Helpers

    /// Walks the pushed presentation's bar-button menus to the Departure Type
    /// submenu. Identified by the filter titles it contains rather than by
    /// position, so reordering the bar items doesn't quietly void these tests.
    private func departureTypeMenu() throws -> UIMenu {
        let stop = try #require(Fixtures.loadSomeStops().first)
        let controller = StopPageViewController(application: application, stop: stop)
        controller.loadViewIfNeeded()

        let barItems = try #require(controller.navigationItem.rightBarButtonItems)
        let submenus = barItems.compactMap(\.menu).flatMap { $0.children.compactMap { $0 as? UIMenu } }

        return try #require(submenus.first { submenu in
            submenu.children.contains { $0.title == ArrivalDepartureFilter.all.displayTitle }
        })
    }

    private func selectedTitles(in menu: UIMenu) -> [String] {
        menu.children.compactMap { $0 as? UIAction }.filter { $0.state == .on }.map(\.title)
    }

    // MARK: - Selection state

    @Test func `Active filter is the only one marked selected`() throws {
        application.setArrivalDepartureFilter(.estimatedOnly)

        let menu = try departureTypeMenu()

        #expect(selectedTitles(in: menu) == [ArrivalDepartureFilter.estimatedOnly.displayTitle])
    }

    @Test func `Selecting a different filter moves the selection`() throws {
        application.setArrivalDepartureFilter(.scheduledOnly)

        let menu = try departureTypeMenu()

        #expect(selectedTitles(in: menu) == [ArrivalDepartureFilter.scheduledOnly.displayTitle])
    }

    /// An unset preference resolves to the configured default, so the menu still
    /// marks a row rather than reading as "nothing is applied".
    @Test func `Default filter is selected when nothing is saved`() throws {
        #expect(application.effectiveArrivalDepartureFilter == .all)

        let menu = try departureTypeMenu()

        #expect(selectedTitles(in: menu) == [ArrivalDepartureFilter.all.displayTitle])
    }

    /// Every filter has a row, so none of them can become unreachable.
    @Test func `Menu offers every filter`() throws {
        let menu = try departureTypeMenu()

        let titles = menu.children.compactMap { $0 as? UIAction }.map(\.title)
        #expect(titles == ArrivalDepartureFilter.allCases.map(\.displayTitle))
    }
}
