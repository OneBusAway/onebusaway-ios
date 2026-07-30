//
//  MapRegionManagerRentalFilterTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

/// A minimal `.otherModes` layer stand-in. `RentalMapLayer`'s initializer is
/// private to its file, and these tests only need something that makes
/// `mapLayers.contains(where: { $0.group == .otherModes })` true — not a
/// working rental pipeline.
@MainActor
private final class FakeOtherModesMapLayer: NSObject, MapLayer {
    let id = "fake.other-modes"
    let title = "Fake"
    let iconName = "bicycle"
    let tintColor: UIColor = .systemPurple
    let group: MapLayerGroup = .otherModes
    let isEnabledByDefault = true
    let availability: MapLayerAvailability = .available
    let zoomWindow = MapLayerZoomWindow(maxVisibleHeight: .greatestFiniteMagnitude)
    let densityBudget = 100
    let isClusterable = false
    let refreshPolicy: MapLayerRefreshPolicy = .static
    let staleAfter: Duration? = nil

    func annotationView(for annotation: MKAnnotation, in mapView: MKMapView) -> MKAnnotationView? { nil }
    func detailViewController(for annotation: MKAnnotation) -> UIViewController? { nil }
    func activate() {}
    func deactivate() {}
    func viewportDidChange(_ mapRect: MKMapRect?) {}
    func mapAnnotationsWereCleared() {}
}

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
        await confirmation("filter change posts a notification") { posted in
            let token = NotificationCenter.default.addObserver(
                forName: .rentalRangeFilterDidChange, object: nil, queue: nil
            ) { _ in posted() }
            defer { NotificationCenter.default.removeObserver(token) }

            manager.rentalRangeFilter = RentalRangeFilter(minimumRangeMeters: 8047)
        }
    }

    /// A redundant write must not post — the coordinator would refilter for nothing.
    @Test func doesNotPostWhenUnchanged() async {
        manager.rentalRangeFilter = RentalRangeFilter(minimumRangeMeters: 8047)

        await confirmation("redundant write posts nothing", expectedCount: 0) { posted in
            let token = NotificationCenter.default.addObserver(
                forName: .rentalRangeFilterDidChange, object: nil, queue: nil
            ) { _ in posted() }
            defer { NotificationCenter.default.removeObserver(token) }

            manager.rentalRangeFilter = RentalRangeFilter(minimumRangeMeters: 8047)
        }
    }

    /// An active filter is a difference from defaults, so Reset must be offered
    /// even when every layer toggle is untouched — but only where the filter row
    /// is actually visible, i.e. a `.otherModes` layer is registered.
    @Test func activeFilterCountsAsDifferingFromDefaults() {
        manager.registerMapLayer(FakeOtherModesMapLayer())

        #expect(manager.mapLayersDifferFromDefaults == false)
        manager.rentalRangeFilter = RentalRangeFilter(minimumRangeMeters: 8047)
        #expect(manager.mapLayersDifferFromDefaults)
    }

    /// The inverse of the above: in a region with no rental layer registered, the
    /// filter row never renders, so a leftover non-default filter value must not
    /// make Reset appear — that would be a button that changes nothing visible.
    @Test func activeFilterWithoutARentalLayerDoesNotCountAsDiffering() {
        manager.rentalRangeFilter = RentalRangeFilter(minimumRangeMeters: 8047)
        #expect(manager.mapLayersDifferFromDefaults == false)
    }

    @Test func resetClearsTheFilter() {
        manager.rentalRangeFilter = RentalRangeFilter(minimumRangeMeters: 8047)
        manager.resetMapLayersToDefaults()
        #expect(manager.rentalRangeFilter == .any)
    }
}
