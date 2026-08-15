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

    // MARK: - Filtering

    /// A blank query is what `.searchable` supplies the moment the field is
    /// focused; it must not blank the list.
    @Test func `Blank query returns every recent stop`() throws {
        let stops = try Fixtures.loadSomeStops()

        #expect(RecentStopsSheetView.filter(stops: stops, query: nil).count == stops.count)
        #expect(RecentStopsSheetView.filter(stops: stops, query: "   ").count == stops.count)
    }

    /// Filtering preserves the store's most-recently-used ordering rather than
    /// re-sorting by relevance.
    @Test func `Filtering narrows results and preserves order`() throws {
        let stops = try Fixtures.loadSomeStops()
        let target = try #require(stops.first)

        let filtered = RecentStopsSheetView.filter(stops: stops, query: target.name)

        #expect(filtered.contains { $0.id == target.id })
        #expect(filtered.count < stops.count)
        let expectedOrder = stops.filter { stop in filtered.contains { $0.id == stop.id } }
        #expect(filtered.map(\.id) == expectedOrder.map(\.id))
    }

    /// No match yields nothing, which is what drives the view's empty state.
    @Test func `Query matching nothing returns no stops`() throws {
        let stops = try Fixtures.loadSomeStops()

        #expect(RecentStopsSheetView.filter(stops: stops, query: "zzzzz-no-such-stop").isEmpty)
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
