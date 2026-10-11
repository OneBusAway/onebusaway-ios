//
//  TripPlannerMapDisplayModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Combine
import CoreLocation
import Foundation
import MapKit
import SwiftUI
import Testing
import OTPKit
@testable import OBAKit

/// Tests for `TripPlannerMapDisplayModel`: the `OTPMapProvider` conformance that turns
/// OTPKit's imperative map calls into state the SwiftUI panel can render.
///
/// Everything here drives the model through the protocol, the way `MapCoordinator` will,
/// so the assertions describe the contract OTPKit actually depends on.
@Suite(.serialized)
@MainActor
struct TripPlannerMapDisplayModelTests {

    private let seattle = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
    private let bellevue = CLLocationCoordinate2D(latitude: 47.6101, longitude: -122.2015)

    private func makeModel() -> TripPlannerMapDisplayModel {
        TripPlannerMapDisplayModel()
    }

    private func addRoute(
        to model: TripPlannerMapDisplayModel,
        identifier: String,
        color: Color = .blue,
        lineWidth: CGFloat = 4
    ) {
        model.addRoute(
            coordinates: [seattle, bellevue],
            color: color,
            lineWidth: lineWidth,
            identifier: identifier,
            lineDashPattern: nil
        )
    }

    private func addAnnotation(
        to model: TripPlannerMapDisplayModel,
        identifier: String,
        type: OTPAnnotationType = .origin
    ) {
        model.addAnnotation(
            coordinate: seattle,
            title: identifier,
            subtitle: nil,
            identifier: identifier,
            type: type,
            routeName: nil,
            routeBackgroundColor: nil,
            routeTextColor: nil
        )
    }

    // MARK: - Draw order

    @Test("Routes keep insertion order, which is the z-order OTPKit relies on")
    func routesKeepInsertionOrder() {
        let model = makeModel()

        // The order MapCoordinator uses: a white halo first, then the coloured leg on
        // top. If this ever reordered, halos would paint over the routes.
        addRoute(to: model, identifier: "halo_leg_0")
        addRoute(to: model, identifier: "leg_0")
        addRoute(to: model, identifier: "halo_leg_1")
        addRoute(to: model, identifier: "leg_1")

        #expect(model.routes.map(\.identifier) == ["halo_leg_0", "leg_0", "halo_leg_1", "leg_1"])
    }

    @Test("Annotations keep insertion order")
    func annotationsKeepInsertionOrder() {
        let model = makeModel()

        addAnnotation(to: model, identifier: "origin")
        addAnnotation(to: model, identifier: "station_from_0")
        addAnnotation(to: model, identifier: "destination", type: .destination)

        #expect(model.annotations.map(\.identifier) == ["origin", "station_from_0", "destination"])
    }

    // MARK: - Identifier reuse

    @Test("Re-adding an identifier replaces in place rather than duplicating")
    func reAddingRouteReplacesInPlace() {
        let model = makeModel()

        addRoute(to: model, identifier: "halo_leg_0")
        addRoute(to: model, identifier: "leg_0", color: .blue)
        addRoute(to: model, identifier: "leg_0", color: .red, lineWidth: 8)

        // Still two routes, the updated one still second: OTPKit reuses identifiers
        // across re-renders, so appending would both leak and disturb the z-order.
        #expect(model.routes.count == 2)
        #expect(model.routes.map(\.identifier) == ["halo_leg_0", "leg_0"])
        #expect(model.routes[1].lineWidth == 8)
    }

    @Test("Re-adding an annotation identifier replaces in place")
    func reAddingAnnotationReplacesInPlace() {
        let model = makeModel()

        addAnnotation(to: model, identifier: "origin")
        addAnnotation(to: model, identifier: "destination", type: .destination)
        model.addAnnotation(
            coordinate: bellevue,
            title: "moved",
            subtitle: nil,
            identifier: "origin",
            type: .origin,
            routeName: nil,
            routeBackgroundColor: nil,
            routeTextColor: nil
        )

        #expect(model.annotations.count == 2)
        #expect(model.annotations[0].title == "moved")
        #expect(model.annotations[0].coordinate.latitude == bellevue.latitude)
    }

    // MARK: - Removal

    @Test("Removing by identifier leaves the rest untouched")
    func removalIsScopedToIdentifier() {
        let model = makeModel()

        addRoute(to: model, identifier: "halo_leg_0")
        addRoute(to: model, identifier: "leg_0")
        addAnnotation(to: model, identifier: "origin")
        addAnnotation(to: model, identifier: "destination", type: .destination)

        model.removeRoute(identifier: "halo_leg_0")
        model.removeAnnotation(identifier: "origin")

        #expect(model.routes.map(\.identifier) == ["leg_0"])
        #expect(model.annotations.map(\.identifier) == ["destination"])
    }

    @Test("clearAllRoutes leaves annotations alone, and vice versa")
    func clearAllIsScopedToItsCollection() {
        let model = makeModel()

        addRoute(to: model, identifier: "leg_0")
        addAnnotation(to: model, identifier: "origin")

        model.clearAllRoutes()
        #expect(model.routes.isEmpty)
        #expect(model.annotations.count == 1)

        addRoute(to: model, identifier: "leg_0")
        model.clearAllAnnotations()
        #expect(model.annotations.isEmpty)
        #expect(model.routes.count == 1)
    }

    // MARK: - Trip presence

    @Test("isShowingTrip tracks whether anything is drawn")
    func isShowingTripTracksContent() {
        let model = makeModel()
        #expect(model.isShowingTrip == false)

        addRoute(to: model, identifier: "leg_0")
        #expect(model.isShowingTrip)

        model.clearAllRoutes()
        #expect(model.isShowingTrip == false)

        // An annotation alone still counts — a planner that has set only an origin pin
        // is showing something the ambient stop layer should not fight with.
        addAnnotation(to: model, identifier: "origin")
        #expect(model.isShowingTrip)
    }

    // MARK: - Camera

    @Test("Camera targets are one-shot")
    func cameraTargetIsOneShot() {
        let model = makeModel()
        #expect(model.cameraTarget == nil)

        let rect = MKMapRect(x: 100, y: 200, width: 300, height: 400)
        model.setVisibleMapRect(rect, edgePadding: .zero, animated: true)
        #expect(model.cameraTarget == .rect(rect, edgePadding: .zero, animated: true))

        // Without consumption the view would re-apply this on every unrelated body pass,
        // yanking the map back while the rider is panning.
        model.consumeCameraTarget()
        #expect(model.cameraTarget == nil)
    }

    @Test("centerOnUserLocation is expressed as a camera target, not a direct move")
    func centerOnUserLocationBecomesTarget() {
        let model = makeModel()

        model.centerOnUserLocation(animated: false)

        #expect(model.cameraTarget == .userLocation(animated: false))
    }

    @Test("getCurrentRegion reports what the view last recorded")
    func currentRegionReflectsRecordedViewport() {
        let model = makeModel()

        let region = MKCoordinateRegion(
            center: seattle,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        model.updateVisibleRegion(region)

        let read = model.getCurrentRegion()
        #expect(read.center.latitude == seattle.latitude)
        #expect(read.span.latitudeDelta == 0.05)
    }

    @Test("getCurrentRegion falls back to the world before the first camera settle")
    func currentRegionFallsBackToWorld() {
        let model = makeModel()

        // A zero-span region would read as a specific — and wrong — place. Reporting the
        // world is the honest answer when the map has not said where it is looking.
        #expect(model.getCurrentRegion().span.latitudeDelta > 100)
    }

    // MARK: - Interaction

    @Test("Map taps reach the handler OTPKit registered")
    func mapTapReachesHandler() {
        let model = makeModel()

        var tapped: CLLocationCoordinate2D?
        model.onMapTap { tapped = $0 }
        model.handleMapTap(at: bellevue)

        #expect(tapped?.latitude == bellevue.latitude)
    }

    @Test("Annotation selection forwards OTPKit's own identifier verbatim")
    func annotationSelectionForwardsIdentifier() {
        let model = makeModel()

        var selected: String?
        model.onAnnotationSelected { selected = $0 }
        model.handleAnnotationSelection(identifier: "station_from_0")

        // The panel never interprets these — they are opaque keys OTPKit assigns and
        // expects back unchanged.
        #expect(selected == "station_from_0")
    }

    @Test("Interaction handlers are safe to invoke before OTPKit registers any")
    func interactionIsSafeWithoutHandlers() {
        let model = makeModel()

        model.handleMapTap(at: seattle)
        model.handleAnnotationSelection(identifier: "leg_0")

        #expect(model.isShowingTrip == false)
    }

    // MARK: - Panel-owned settings

    @Test("Map configuration calls do not disturb panel-wide state")
    func mapConfigurationCallsAreIgnored() {
        let model = makeModel()

        addRoute(to: model, identifier: "leg_0")

        // Basemap style is the rider's own choice, persisted through MapViewModel. OTPKit
        // may reconfigure its private map view on the UIKit surface, but here it is a
        // guest on the panel's shared map.
        model.setMapType(.satellite)
        model.setUserInteractionEnabled(false)
        model.setControlsVisible(false)

        #expect(model.routes.count == 1)
        #expect(model.cameraTarget == nil)
    }

    @Test("showUserLocation is recorded rather than acted on")
    func userLocationPreferenceIsRecorded() {
        let model = makeModel()
        #expect(model.wantsUserLocation == false)

        model.showUserLocation(true)
        #expect(model.wantsUserLocation)
    }

    // MARK: - Teardown

    @Test("clear drops everything the trip drew")
    func clearDropsEverything() {
        let model = makeModel()

        addRoute(to: model, identifier: "leg_0")
        addAnnotation(to: model, identifier: "origin")
        model.showUserLocation(true)
        model.setRegion(
            MKCoordinateRegion(center: seattle, span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)),
            animated: true
        )

        model.clear()

        #expect(model.routes.isEmpty)
        #expect(model.annotations.isEmpty)
        #expect(model.cameraTarget == nil)
        #expect(model.wantsUserLocation == false)
        #expect(model.isShowingTrip == false)
    }

    // MARK: - Map rect padding (view points to map points conversion)

    @Test("Padded rect expands by scaled edge insets")
    func paddedRectExpansion() {
        // A realistic viewport: ~5km = ~33,492 map points wide
        let mapRect = MKMapRect(x: 0, y: 0, width: 33492, height: 33492)
        // Map display: 400x400 view points
        let mapSize = CGSize(width: 400, height: 400)
        // 50pt bottom padding (to clear the sheet) should expand height by a visible fraction
        let padding = UIEdgeInsets(top: 0, left: 0, bottom: 50, right: 0)

        let paddedRect = paddedMapRect(mapRect, edgePadding: padding, mapSize: mapSize)

        // Scale factor: 33492 / 400 = 83.73 map points per view point
        // 50pt padding * 83.73 = 4,186.5 map points expansion
        // That is 12.5% of the 33,492 viewport height — clearly visible, not negligible
        let heightExpansion = paddedRect.size.height - mapRect.size.height
        let heightFraction = heightExpansion / mapRect.size.height
        #expect(heightFraction > 0.1) // At least 10%, not the near-zero we'd get from dividing by a constant
    }

    @Test("Padded rect preserves asymmetric padding (bottom > top)")
    func paddedRectAsymmetry() {
        let mapRect = MKMapRect(x: 0, y: 0, width: 1000, height: 1000)
        let mapSize = CGSize(width: 100, height: 100)
        // 20pt top, 40pt bottom — bottom should move the origin up more
        let padding = UIEdgeInsets(top: 20, left: 0, bottom: 40, right: 0)

        let paddedRect = paddedMapRect(mapRect, edgePadding: padding, mapSize: mapSize)

        // Scale: 1000 / 100 = 10 map points per view point
        // Top: origin.y -= 20 * 10 = 200 map points upward
        // Bottom: size.height += (20 + 40) * 10 = 600 map points downward
        // Total height expansion: 800 map points (80% of viewport)
        let heightExpansion = paddedRect.size.height - mapRect.size.height
        #expect(heightExpansion == 600) // 20 + 40 = 60, times scale 10 = 600

        // Top inset pulls origin up: origin.y should decrease
        #expect(paddedRect.origin.y < mapRect.origin.y)
    }

    @Test("Padded rect with zero map size uses fallback fraction")
    func paddedRectZeroMapSize() {
        let mapRect = MKMapRect(x: 100, y: 200, width: 1000, height: 1000)
        let mapSize = CGSize.zero // Before first geometry report
        let padding = UIEdgeInsets(top: 20, left: 20, bottom: 40, right: 40)

        let paddedRect = paddedMapRect(mapRect, edgePadding: padding, mapSize: mapSize)

        // Falls back to insetBy with fractions: insetBy applies symmetrically
        // so -0.15 * width on each side = 0.30 total, -0.30 * height on each side = 0.60 total
        let widthFraction = (paddedRect.size.width - mapRect.size.width) / mapRect.size.width
        let heightFraction = (paddedRect.size.height - mapRect.size.height) / mapRect.size.height
        #expect(widthFraction == 0.30)  // Symmetric expansion: 0.15 each side
        #expect(heightFraction == 0.60) // Symmetric expansion: 0.30 each side

        // Does not trap on zero size
    }

    // MARK: - MapPinSelection round trip

    /// The panel tags every trip pin with OTPKit's own opaque identifier and hands
    /// it straight back on tap. This asserts the round trip end to end — the tag
    /// the overlay builds is the identifier OTPKit gets back, unmodified.
    @Test("Tapping a trip pin returns OTPKit's identifier verbatim")
    func tripPinSelectionRoundTrip() {
        let model = TripPlannerMapDisplayModel()
        var selected: String?
        model.onAnnotationSelected { selected = $0 }

        model.addAnnotation(
            coordinate: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3),
            title: "Westlake",
            subtitle: nil,
            identifier: "station_from_0",
            type: .origin,
            routeName: nil,
            routeBackgroundColor: nil,
            routeTextColor: nil
        )

        guard let annotation = model.annotations.first else {
            Issue.record("Expected the annotation to be recorded")
            return
        }
        let tag = MapPinSelection.tripPlannerAnnotation(annotation.identifier)

        guard case .tripPlannerAnnotation(let identifier) = tag else {
            Issue.record("Expected .tripPlannerAnnotation")
            return
        }
        model.handleAnnotationSelection(identifier: identifier)

        #expect(selected == "station_from_0")
    }

    // MARK: - Deferred change notification

    /// OTPKit drives this model from inside SwiftUI's update pass — `DirectionsSheetView`
    /// calls into `MapCoordinator` from `onAppear` and from three `onChange` handlers — so
    /// a synchronous publish here is "Publishing changes from within view updates is not
    /// allowed" on every interaction with the directions sheet. The notification has to
    /// land after the pass, and only the notification: reads stay synchronous.
    @Test("Drawing does not notify observers synchronously")
    func drawingDefersChangeNotification() {
        let model = TripPlannerMapDisplayModel()
        var notifications = 0
        let cancellable = model.objectWillChange.sink { _ in notifications += 1 }
        defer { cancellable.cancel() }

        model.addRoute(
            coordinates: [CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)],
            color: .blue,
            lineWidth: 4,
            identifier: "leg_0",
            lineDashPattern: nil
        )

        #expect(notifications == 0)
        // The write itself is not deferred — the ambient-stop gate reads this in the same
        // turn OTPKit draws.
        #expect(model.routes.count == 1)
        #expect(model.isShowingTrip)
    }

    /// One itinerary is dozens of provider calls — a halo and a line per leg, an annotation
    /// per stop. They deserve one re-render between them, not one each.
    @Test("A burst of drawing calls coalesces into a single notification")
    func drawingBurstCoalescesIntoOneNotification() async {
        let model = TripPlannerMapDisplayModel()
        var notifications = 0
        let cancellable = model.objectWillChange.sink { _ in notifications += 1 }
        defer { cancellable.cancel() }

        for index in 0..<10 {
            model.addRoute(
                coordinates: [CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)],
                color: .blue,
                lineWidth: 4,
                identifier: "leg_\(index)",
                lineDashPattern: nil
            )
        }
        model.setRegion(
            MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3),
                               latitudinalMeters: 1000,
                               longitudinalMeters: 1000),
            animated: true
        )

        #expect(notifications == 0)

        // Let the scheduled hop run.
        await Task.yield()

        #expect(notifications == 1)
        #expect(model.routes.count == 10)
    }

    /// Clearing has to reach the map too, or a dismissed trip stays drawn.
    @Test("Clearing notifies observers on the next turn")
    func clearNotifiesAfterTheUpdatePass() async {
        let model = TripPlannerMapDisplayModel()
        model.addAnnotation(
            coordinate: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3),
            title: "Westlake",
            subtitle: nil,
            identifier: "station_from_0",
            type: .origin,
            routeName: nil,
            routeBackgroundColor: nil,
            routeTextColor: nil
        )
        await Task.yield()

        var notifications = 0
        let cancellable = model.objectWillChange.sink { _ in notifications += 1 }
        defer { cancellable.cancel() }

        model.clear()
        #expect(notifications == 0)
        #expect(model.isShowingTrip == false)

        await Task.yield()
        #expect(notifications == 1)
    }
}
