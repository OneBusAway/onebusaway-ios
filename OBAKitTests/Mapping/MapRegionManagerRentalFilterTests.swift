//
//  MapRegionManagerRentalFilterTests.swift
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

/// Persistence for the shared rental minimum-range threshold. It lives on
/// `MapRegionManager` beside the per-layer enablement so the Map sheet's Reset
/// affordance covers it without new machinery.
///
/// Inherits `OBATestCase` for its per-instance `UserDefaults` domain: Swift Testing
/// runs suites concurrently within one process, so isolation has to come from the
/// fixture rather than from the schedule.
@MainActor
@Suite(.serialized)
final class MapRegionManagerRentalFilterTests: OBATestCase {

    private var manager: MapRegionManager!

    override init() async throws {
        try await super.init()
        let queue = OperationQueue()
        let dataLoader = MockDataLoader(testName: name)
        manager = MapRegionManager(application: buildApplication(queue: queue, dataLoader: dataLoader))
    }

    @Test func defaultsToAny() {
        #expect(manager.rentalRangeFilter == .any)
        #expect(manager.rentalRangeFilter.isActive == false)
    }

    @Test func persistsTheThreshold() {
        manager.rentalRangeFilter = RentalRangeFilter(minimumRangeMeters: 8047)
        #expect(manager.rentalRangeFilter.minimumRangeMeters == 8047)
    }

    /// Asserts the write lands in the suite's scratch domain. This depends on
    /// `buildApplication` configuring the app with `OBATestCase.userDefaults` —
    /// check `OBATestCase.buildApplication(queue:dataLoader:)` if it fails, and
    /// read through `manager.rentalRangeFilter` instead if the app owns a
    /// different domain.
    @Test func writesThroughToUserDefaults() {
        manager.rentalRangeFilter = RentalRangeFilter(minimumRangeMeters: 8047)
        let stored = userDefaults.integer(forKey: MapRegionManager.rentalMinimumRangeDefaultsKey)
        #expect(stored == 8047)
    }

    @Test func postsOnChange() async {
        var posted = false
        let token = NotificationCenter.default.addObserver(
            forName: .rentalRangeFilterDidChange, object: nil, queue: nil
        ) { _ in posted = true }
        defer { NotificationCenter.default.removeObserver(token) }

        manager.rentalRangeFilter = RentalRangeFilter(minimumRangeMeters: 8047)
        #expect(posted)
    }

    /// A redundant write must not post — the coordinator would refilter for nothing.
    @Test func doesNotPostWhenUnchanged() {
        manager.rentalRangeFilter = RentalRangeFilter(minimumRangeMeters: 8047)

        var posted = false
        let token = NotificationCenter.default.addObserver(
            forName: .rentalRangeFilterDidChange, object: nil, queue: nil
        ) { _ in posted = true }
        defer { NotificationCenter.default.removeObserver(token) }

        manager.rentalRangeFilter = RentalRangeFilter(minimumRangeMeters: 8047)
        #expect(posted == false)
    }

    /// An active filter is a difference from defaults, so Reset must be offered
    /// even when every layer toggle is untouched.
    @Test func activeFilterCountsAsDifferingFromDefaults() {
        #expect(manager.mapLayersDifferFromDefaults == false)
        manager.rentalRangeFilter = RentalRangeFilter(minimumRangeMeters: 8047)
        #expect(manager.mapLayersDifferFromDefaults)
    }

    @Test func resetClearsTheFilter() {
        manager.rentalRangeFilter = RentalRangeFilter(minimumRangeMeters: 8047)
        manager.resetMapLayersToDefaults()
        #expect(manager.rentalRangeFilter == .any)
    }
}
