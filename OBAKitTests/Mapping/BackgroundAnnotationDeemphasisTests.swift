//
//  BackgroundAnnotationDeemphasisTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OTPKit
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

/// While a stop sheet owns the map, everything that isn't part of the selection
/// collapses to a subtle gray dot that ignores taps. These tests pin the dispatch
/// decision — which annotation gets which view — because it is the whole feature,
/// and because the alternative (the dot's appearance) can only be judged on screen.
@MainActor
@Suite(.serialized)
final class BackgroundAnnotationDeemphasisTests: OBATestCase {

    /// The coordinator's initializer requires a service; nothing here awaits a fetch.
    private struct StubVehicleRentalService: VehicleRentalService {
        func fetchVehicleRentals(
            in boundingBox: VehicleRentalBoundingBox,
            formFactors: Set<VehicleFormFactor>?
        ) async throws -> VehicleRentalFetchResult {
            VehicleRentalFetchResult(rentals: [])
        }
    }

    /// Stands in for a layer that owns annotations of its own. `recedes` is what
    /// the manager consults; `annotationView` is what it must *not* build when the
    /// answer is yes.
    private final class StubLayer: NSObject, MapLayer {
        let id = "stub"
        let title = "Stub"
        let iconName = "circle"
        let tintColor = UIColor.systemPink
        let group = MapLayerGroup.otherModes
        let isEnabledByDefault = true
        let availability = MapLayerAvailability.available
        let zoomWindow = MapLayerZoomWindow(maxVisibleHeight: .greatestFiniteMagnitude)
        let densityBudget = 10
        let isClusterable = false
        let refreshPolicy = MapLayerRefreshPolicy.static
        let staleAfter: Duration? = nil

        let recedes: Bool
        private(set) var annotationViewCallCount = 0

        init(recedes: Bool) {
            self.recedes = recedes
        }

        func annotationView(for annotation: MKAnnotation, in mapView: MKMapView) -> MKAnnotationView? {
            annotationViewCallCount += 1
            return MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: nil)
        }

        func recedesBehindStopSheet(_ annotation: MKAnnotation) -> Bool { recedes }

        func detailViewController(for annotation: MKAnnotation) -> UIViewController? { nil }
        func activate() { }
        func deactivate() { }
        func viewportDidChange(_ mapRect: MKMapRect?) { }
        func mapAnnotationsWereCleared() { }
    }

    private func makeManager() -> MapRegionManager {
        MapRegionManager(
            application: buildApplication(queue: OperationQueue(), dataLoader: MockDataLoader(testName: #function))
        )
    }

    /// Two distinct stops from the same fixture: one to select, one to push into
    /// the background.
    private func twoStops() throws -> (selected: Stop, other: Stop) {
        let stops = try Fixtures.loadSomeStops()
        let selected = try #require(stops.first)
        let other = try #require(stops.first { $0.id != selected.id })
        return (selected, other)
    }

    // MARK: - Stops

    @Test func `A stop keeps its full pin when no stop sheet is up`() throws {
        let manager = makeManager()
        let view = manager.mapView(manager.mapView, viewFor: try twoStops().other)

        #expect(view is StopAnnotationView)
    }

    @Test func `Another stop collapses to a background dot while a stop sheet is up`() throws {
        let manager = makeManager()
        let stops = try twoStops()
        manager.stopSheetSelection = stops.selected.id

        let view = manager.mapView(manager.mapView, viewFor: stops.other)

        #expect(view is BackgroundDotAnnotationView)
    }

    /// The rider tapped this stop to open the sheet; dotting it out would erase
    /// the anchor the sheet, the route lines, and the vehicles all describe.
    @Test func `The sheet's own stop keeps its pin`() throws {
        let manager = makeManager()
        let stops = try twoStops()
        manager.stopSheetSelection = stops.selected.id

        let view = manager.mapView(manager.mapView, viewFor: stops.selected)

        #expect(view is StopAnnotationView)
    }

    /// The dot is the map's backdrop, not a target. A tap on one has to fall
    /// through instead of swapping the sheet out from under the rider.
    @Test func `The background dot refuses selection and callouts`() {
        let dot = BackgroundDotAnnotationView(annotation: nil, reuseIdentifier: nil)

        #expect(dot.isEnabled == false)
        #expect(dot.canShowCallout == false)
    }

    // MARK: - Layer-owned annotations

    @Test func `A receding layer's annotation gets the dot, and the layer is never asked to build a view`() throws {
        let manager = makeManager()
        let layer = StubLayer(recedes: true)
        manager.registerMapLayer(layer)
        manager.stopSheetSelection = try twoStops().selected.id

        let view = manager.mapView(manager.mapView, viewFor: MKPointAnnotation())

        #expect(view is BackgroundDotAnnotationView)
        // Dequeuing two views for one annotation in a single `viewFor` call is
        // exactly what the `recedesBehindStopSheet` requirement exists to avoid.
        #expect(layer.annotationViewCallCount == 0)
    }

    @Test func `A layer that declines to recede keeps its own view`() throws {
        let manager = makeManager()
        manager.registerMapLayer(StubLayer(recedes: false))
        manager.stopSheetSelection = try twoStops().selected.id

        let view = manager.mapView(manager.mapView, viewFor: MKPointAnnotation())

        #expect(view is MKMarkerAnnotationView)
        #expect(view is BackgroundDotAnnotationView == false)
    }

    /// The route-focus layer's vehicles are the selection the sheet came up to
    /// show. If they ever receded, the feature would erase its own content.
    @Test func `The route focus layer never recedes`() {
        let layer = StopRouteFocusMapLayer(
            mapView: MKMapView(),
            shapeCache: ShapeCache { _ in "" },
            formatters: Formatters(
                locale: Locale(identifier: "en_US"),
                calendar: Calendar(identifier: .gregorian),
                themeColors: ThemeColors.shared
            )
        )

        #expect(layer.recedesBehindStopSheet(MKPointAnnotation()) == false)
    }

    // MARK: - Rentals

    @Test func `Rental vehicles and their clusters recede`() throws {
        let mapView = MKMapView()
        let layer = RentalMapLayer.bikesLayer(
            coordinator: RentalLayerCoordinator(service: StubVehicleRentalService(), mapView: mapView)
        )
        let rental = RentalAnnotation(rental: try RentalFixtures.vehicle())
        let cluster = MKClusterAnnotation(memberAnnotations: [rental])

        #expect(layer.recedesBehindStopSheet(rental))
        #expect(layer.recedesBehindStopSheet(cluster))
        // A cluster of something else belongs to whichever layer drew it.
        #expect(layer.recedesBehindStopSheet(MKClusterAnnotation(memberAnnotations: [MKPointAnnotation()])) == false)
    }

    // MARK: - Toggling

    /// Changing the selection has to force MapKit to re-ask `viewFor` for
    /// annotations already on the map, which means removing and re-adding them —
    /// a refresh that loses one would silently empty the map behind the sheet.
    @Test func `Changing the selection preserves the annotations already on the map`() throws {
        let manager = makeManager()
        let stops = try twoStops()
        let untouched = MKPointAnnotation()
        manager.mapView.addAnnotations([stops.selected, stops.other, untouched])

        for selection in [stops.selected.id, stops.other.id, nil] {
            manager.stopSheetSelection = selection
            #expect(manager.mapView.annotations.contains { $0 === stops.selected })
            #expect(manager.mapView.annotations.contains { $0 === stops.other })
            #expect(manager.mapView.annotations.contains { $0 === untouched })
        }
    }

    /// A stop-to-stop swap must repaint the stop that *stopped* being selected,
    /// not just the one that started. The refresh pass is deliberately blind to
    /// the selection for exactly this case.
    @Test func `Swapping the selection re-dots the stop that lost it`() throws {
        let manager = makeManager()
        let stops = try twoStops()
        manager.stopSheetSelection = stops.selected.id
        manager.stopSheetSelection = stops.other.id

        #expect(manager.mapView(manager.mapView, viewFor: stops.selected) is BackgroundDotAnnotationView)
        #expect(manager.mapView(manager.mapView, viewFor: stops.other) is StopAnnotationView)
    }

    /// A stop-to-stop swap changes how exactly two markers draw. Refreshing the
    /// rest — up to 500 rental annotations plus every stop on screen — hands each
    /// one back the view it already had, on the main thread, during the sheet
    /// transition. Asserted on the affected set rather than on `MKMapView`, which
    /// gives a test no way to see a remove/re-add that lands on the same object.
    @Test func `Swapping the selection refreshes only the two stops involved`() throws {
        let manager = makeManager()
        let stops = try twoStops()
        let bystanders = (0..<5).map { _ in MKPointAnnotation() }
        manager.registerMapLayer(StubLayer(recedes: true))
        manager.mapView.addAnnotations([stops.selected, stops.other] + bystanders)

        let affected = manager.annotationsNeedingEmphasisRefresh(from: stops.selected.id, to: stops.other.id)

        #expect(affected.count == 2)
        #expect(affected.contains { $0 === stops.selected })
        #expect(affected.contains { $0 === stops.other })
    }

    /// The other side of the same coin: opening a sheet genuinely does flip
    /// everything but the selected stop, and all of it has to be refreshed.
    @Test func `Opening a sheet refreshes every participating annotation but the selected stop`() throws {
        let manager = makeManager()
        let stops = try twoStops()
        let receding = MKPointAnnotation()
        manager.registerMapLayer(StubLayer(recedes: true))
        manager.mapView.addAnnotations([stops.selected, stops.other, receding])

        let affected = manager.annotationsNeedingEmphasisRefresh(from: nil, to: stops.selected.id)

        #expect(affected.count == 2)
        #expect(affected.contains { $0 === stops.other })
        #expect(affected.contains { $0 === receding })
        #expect(affected.contains { $0 === stops.selected } == false)
    }

    /// An annotation no layer claims — a search pin, the user location — never
    /// recedes under any selection, so it must never be churned.
    @Test func `An annotation nothing claims is never refreshed`() throws {
        let manager = makeManager()
        let stops = try twoStops()
        let unclaimed = MKPointAnnotation()
        manager.mapView.addAnnotations([stops.selected, unclaimed])

        let affected = manager.annotationsNeedingEmphasisRefresh(from: nil, to: stops.selected.id)

        #expect(affected.contains { $0 === unclaimed } == false)
    }
}
