//
//  RecentStopsSheetViewTests.swift
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

@Suite(.serialized)
final class RecentStopsSheetViewTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    /// Seeds recents the way production does, with the region identifier that
    /// `RESTAPIResponse.loadReferences` would otherwise have assigned.
    @MainActor
    private func seedRecents(count: Int, application: Application) throws -> [Stop] {
        let stops = try Fixtures.loadSomeStops()
        let seeded = Array(stops.prefix(count))
        for stop in seeded {
            stop.regionIdentifier = Fixtures.pugetSoundRegion.regionIdentifier
            application.userDataStore.addRecentStop(stop, region: Fixtures.pugetSoundRegion)
        }
        return seeded
    }

    // MARK: - Rows

    /// The stop code and routes share one line, where the map's callout
    /// subtitle splits them over two.
    @Test func `A stop row's subtitle is one line`() throws {
        let stop = try #require(try Fixtures.loadSomeStops().first)

        let subtitle = stop.subtitle(separator: " · ")

        #expect(!subtitle.contains("\n"))
        #expect(subtitle.hasPrefix("#\(stop.code)"))
        if let routes = Formatters.formattedRoutes(stop.routes) {
            #expect(subtitle == "#\(stop.code) · \(routes)")
        }
    }

    // MARK: - Returning from a stacked sheet

    /// Viewing a stop from this list calls `addRecentStop`, so the store is
    /// rewritten by the act of navigating away. The index sits on the stacked
    /// layer and is never removed from the hierarchy while the stop sheet covers
    /// it, so the reload has to be driven by the stack shrinking.
    @Test func `Closing a sheet stacked above triggers a reload`() {
        // Stop details closes over the recents index: depth 2 → 1.
        #expect(StackedSheetReturn.wasUncovered(previousDepth: 2, depth: 1))
    }

    /// Opening one must not: the index is being covered, not uncovered, and
    /// reloading here would rebuild the list underneath the sheet the user just
    /// opened.
    @Test func `Opening a sheet on top does not trigger a reload`() {
        #expect(!StackedSheetReturn.wasUncovered(previousDepth: 1, depth: 2))
        #expect(!StackedSheetReturn.wasUncovered(previousDepth: 0, depth: 1))
    }

    /// The regression this guards: watching for the stack to *empty* — which is
    /// what `HomeSheetView` correctly does from below the stacked layer — never
    /// fires for a screen that is itself stacked, because its own entry keeps the
    /// count at 1 or more the entire time it's on screen.
    @Test func `Uncovering is detected without the stack ever emptying`() {
        #expect(StackedSheetReturn.wasUncovered(previousDepth: 3, depth: 2))
        #expect(StackedSheetReturn.wasUncovered(previousDepth: 2, depth: 1))
        // No change is not a return.
        #expect(!StackedSheetReturn.wasUncovered(previousDepth: 1, depth: 1))
    }

    // MARK: - Deletion

    /// Swipe-to-delete removes exactly the swiped stop and leaves the rest.
    @Test @MainActor func `Deleting one recent stop leaves the others`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let seeded = try seedRecents(count: 3, application: application)

        let viewModel = RecentStopsViewModel(application: application)
        viewModel.loadData()
        try #require(viewModel.recentStops.count == 3)

        let doomed = try #require(seeded.first)
        viewModel.delete(recentStop: doomed)

        #expect(viewModel.recentStops.count == 2)
        #expect(!viewModel.recentStops.contains { $0.id == doomed.id })
    }

    /// Delete All empties both the view model and the store behind it.
    @Test @MainActor func `Deleting all recent stops empties the list`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        _ = try seedRecents(count: 3, application: application)

        let viewModel = RecentStopsViewModel(application: application)
        viewModel.loadData()
        try #require(!viewModel.recentStops.isEmpty)

        viewModel.deleteAllRecentStops()

        #expect(viewModel.recentStops.isEmpty)
        #expect(application.userDataStore.recentStops(in: application.currentRegion).isEmpty)
    }
}
