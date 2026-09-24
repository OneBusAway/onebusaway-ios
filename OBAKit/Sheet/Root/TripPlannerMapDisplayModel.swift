//
//  TripPlannerMapDisplayModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Combine
import CoreLocation
import MapKit
import OBAKitCore
import OTPKit
import SwiftUI

/// What the SwiftUI map should draw for the current trip plan.
///
/// OTPKit drives a map through `OTPMapProvider`, and ships one implementation —
/// `MKMapViewAdapter` — that mutates an `MKMapView` directly, taking its delegate and
/// installing its own gesture recognizer. The UIKit map surface hands it a whole second
/// map view for exactly that reason (`MapViewController.tripPlannerMapView`), swapping
/// the two by alpha when a trip starts.
///
/// The panel has no `MKMapView` to hand over, so it implements the protocol a second way:
/// calls land in published state and `MapPanelRootView` renders it declaratively. This is
/// the same move `MapSearchDisplayModel` makes for search results, and it is why nothing
/// here needs to fork OTPKit — the protocol is the seam, and `MKMapViewAdapter` is only
/// one implementation of it.
@MainActor
final class TripPlannerMapDisplayModel: ObservableObject, OTPMapProvider {

    // MARK: - Drawn content

    /// A polyline OTPKit asked for, carrying the styling it chose.
    ///
    /// `identifier` is OTPKit's own opaque key (`"leg_0"`, `"halo_leg_0"`). We never
    /// interpret it — it exists so `removeRoute(identifier:)` can find this again.
    struct Route: Identifiable, Equatable {
        let identifier: String
        let coordinates: [CLLocationCoordinate2D]
        let color: Color
        let lineWidth: CGFloat
        let dashPattern: [NSNumber]?

        var id: String { identifier }

        static func == (lhs: Route, rhs: Route) -> Bool {
            lhs.identifier == rhs.identifier
                && lhs.lineWidth == rhs.lineWidth
                && lhs.color == rhs.color
                && lhs.coordinates.count == rhs.coordinates.count
        }
    }

    /// An annotation OTPKit asked for.
    struct Annotation: Identifiable, Equatable {
        let identifier: String
        let coordinate: CLLocationCoordinate2D
        let title: String
        let subtitle: String?
        let type: OTPAnnotationType
        let routeName: String?
        let routeBackgroundColor: UIColor?
        let routeTextColor: UIColor?

        var id: String { identifier }

        static func == (lhs: Annotation, rhs: Annotation) -> Bool {
            lhs.identifier == rhs.identifier
                && lhs.title == rhs.title
                && lhs.subtitle == rhs.subtitle
                && lhs.type == rhs.type
                && lhs.routeName == rhs.routeName
                && lhs.coordinate.latitude == rhs.coordinate.latitude
                && lhs.coordinate.longitude == rhs.coordinate.longitude
        }
    }

    /// Insertion-ordered on purpose: OTPKit draws a white halo under each leg and then
    /// the coloured line on top, so the order it adds them in *is* the z-order. A
    /// dictionary would lose that and the halos would paint over the routes.
    ///
    /// Deliberately not `@Published` — see `scheduleChangeNotification()`.
    private(set) var routes: [Route] = []

    /// Insertion-ordered for the same reason. Not `@Published`, same reason.
    private(set) var annotations: [Annotation] = []

    /// Whether OTPKit currently wants the user's location shown. The panel already shows
    /// it unconditionally, so this is recorded rather than acted on — see `setMapType`
    /// below for the general rule.
    private(set) var wantsUserLocation = false

    /// True once anything is drawn. Lets the view suppress the ambient stop layer while a
    /// trip is on the map, the way `MapSearchDisplayModel.suppressesAmbientStops` does
    /// for a searched route.
    var isShowingTrip: Bool { !routes.isEmpty || !annotations.isEmpty }

    // MARK: - Camera

    /// Where OTPKit wants the camera next. One-shot: the view applies it and calls
    /// `consumeCameraTarget()`.
    ///
    /// Modelled on `MapSearchDisplayModel.CameraTarget` for the reason documented there —
    /// `body` re-runs on unrelated state changes, including every frame of a sheet drag,
    /// and a target that stayed set would re-move the map out from under the rider.
    enum CameraTarget: Equatable {
        case region(MKCoordinateRegion, animated: Bool)
        case rect(MKMapRect, edgePadding: UIEdgeInsets, animated: Bool)
        case userLocation(animated: Bool)

        static func == (lhs: CameraTarget, rhs: CameraTarget) -> Bool {
            switch (lhs, rhs) {
            case (.region(let l, let la), .region(let r, let ra)):
                return l.center.latitude == r.center.latitude
                    && l.center.longitude == r.center.longitude
                    && l.span.latitudeDelta == r.span.latitudeDelta
                    && l.span.longitudeDelta == r.span.longitudeDelta
                    && la == ra
            case (.rect(let l, let lp, let la), .rect(let r, let rp, let ra)):
                return l.origin.x == r.origin.x && l.origin.y == r.origin.y
                    && l.size.width == r.size.width && l.size.height == r.size.height
                    && lp == rp && la == ra
            case (.userLocation(let la), .userLocation(let ra)):
                return la == ra
            default:
                return false
            }
        }
    }

    private(set) var cameraTarget: CameraTarget?

    /// The map's current visible region, pushed in by the view on every camera settle.
    ///
    /// `getCurrentRegion()` is a synchronous read in OTPKit's protocol, and a SwiftUI
    /// `Map` has no equivalent to ask. Recording what the view last reported is the only
    /// way to answer it honestly.
    private var visibleRegion: MKCoordinateRegion?

    // MARK: - Interaction

    private var mapTapHandler: ((CLLocationCoordinate2D) -> Void)?
    private var annotationSelectionHandler: ((String) -> Void)?

    // MARK: - Change notification

    /// True while a notification is already queued for this turn.
    private var changeNotificationScheduled = false

    /// Tells observers to re-read, one runloop turn later.
    ///
    /// OTPKit drives this model from inside SwiftUI's own update pass: `DirectionsSheetView`
    /// calls `MapCoordinator.showItinerary` / `focusOnLeg` from `onAppear` and from
    /// `onChange(of:)` on the detent, the focused leg and the trip phase, and every one of
    /// those lands here as a mutation. Publishing synchronously from those call sites is
    /// what SwiftUI reports as "Publishing changes from within view updates is not allowed"
    /// — on *every* interaction with the directions sheet, because every interaction moves
    /// the map.
    ///
    /// This is specific to a state-backed `OTPMapProvider`. `MKMapViewAdapter` writes to an
    /// `MKMapView`, which no SwiftUI view observes, so the same calls are invisible there.
    /// The seam is ours, so the deferral belongs here rather than in OTPKit.
    ///
    /// The properties stay plain stored values so reads remain synchronous and truthful in
    /// the same turn as the write — `isShowingTrip` gates the ambient stop layer, and
    /// `getCurrentRegion()` answers OTPKit synchronously. Only the *notification* moves.
    /// Coalesced because OTPKit draws a halo and a line per leg plus an annotation per
    /// stop: one itinerary is dozens of calls, and they deserve one re-render.
    private func scheduleChangeNotification() {
        guard !changeNotificationScheduled else { return }
        changeNotificationScheduled = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.changeNotificationScheduled = false
            self.objectWillChange.send()
        }
    }

    // MARK: - Host-facing API

    /// Records the region the map is currently showing. Call on every camera settle.
    func updateVisibleRegion(_ region: MKCoordinateRegion) {
        visibleRegion = region
    }

    /// Applies-and-forgets the pending camera move.
    ///
    /// No change notification: the view calls this from its own `onChange` handler, having
    /// just applied the target, so nothing needs to re-read on account of the clear — and
    /// notifying from there would be the very mid-update publish this model exists to avoid.
    func consumeCameraTarget() {
        cameraTarget = nil
    }

    /// Forwards a map tap to OTPKit, if it asked for them.
    func handleMapTap(at coordinate: CLLocationCoordinate2D) {
        mapTapHandler?(coordinate)
    }

    /// Forwards an annotation selection to OTPKit, keyed by the identifier OTPKit gave us.
    func handleAnnotationSelection(identifier: String) {
        annotationSelectionHandler?(identifier)
    }

    /// Drops everything drawn for the trip. The host calls this alongside
    /// `TripPlanner.reset()` when the planner leaves the sheet stack.
    func clear() {
        routes.removeAll()
        annotations.removeAll()
        cameraTarget = nil
        wantsUserLocation = false
        scheduleChangeNotification()
    }

    // MARK: - OTPMapProvider: routes

    func addRoute(
        coordinates: [CLLocationCoordinate2D],
        color: Color,
        lineWidth: CGFloat,
        identifier: String,
        lineDashPattern: [NSNumber]?
    ) {
        let route = Route(
            identifier: identifier,
            coordinates: coordinates,
            color: color,
            lineWidth: lineWidth,
            dashPattern: lineDashPattern
        )

        // Replace in place rather than appending a duplicate: OTPKit reuses identifiers
        // across re-renders of the same leg, and appending would both leak and reorder.
        if let index = routes.firstIndex(where: { $0.identifier == identifier }) {
            routes[index] = route
        } else {
            routes.append(route)
        }
        scheduleChangeNotification()
    }

    func removeRoute(identifier: String) {
        routes.removeAll { $0.identifier == identifier }
        scheduleChangeNotification()
    }

    func clearAllRoutes() {
        routes.removeAll()
        scheduleChangeNotification()
    }

    // MARK: - OTPMapProvider: annotations

    func addAnnotation(
        coordinate: CLLocationCoordinate2D,
        title: String,
        subtitle: String?,
        identifier: String,
        type: OTPAnnotationType,
        routeName: String?,
        routeBackgroundColor: UIColor?,
        routeTextColor: UIColor?
    ) {
        let annotation = Annotation(
            identifier: identifier,
            coordinate: coordinate,
            title: title,
            subtitle: subtitle,
            type: type,
            routeName: routeName,
            routeBackgroundColor: routeBackgroundColor,
            routeTextColor: routeTextColor
        )

        if let index = annotations.firstIndex(where: { $0.identifier == identifier }) {
            annotations[index] = annotation
        } else {
            annotations.append(annotation)
        }
        scheduleChangeNotification()
    }

    func removeAnnotation(identifier: String) {
        annotations.removeAll { $0.identifier == identifier }
        scheduleChangeNotification()
    }

    func clearAllAnnotations() {
        annotations.removeAll()
        scheduleChangeNotification()
    }

    // MARK: - OTPMapProvider: camera

    func setRegion(_ region: MKCoordinateRegion, animated: Bool) {
        cameraTarget = .region(region, animated: animated)
        scheduleChangeNotification()
    }

    func setVisibleMapRect(
        _ mapRect: MKMapRect,
        edgePadding: UIEdgeInsets,
        animated: Bool
    ) {
        cameraTarget = .rect(mapRect, edgePadding: edgePadding, animated: animated)
        scheduleChangeNotification()
    }

    func getCurrentRegion() -> MKCoordinateRegion {
        // Before the first camera settle there is nothing truthful to return. OTPKit uses
        // this to frame results, and a zero-span region reads as "the whole world" rather
        // than as a wrong place, which is the safer of the two lies available here.
        visibleRegion ?? MKCoordinateRegion(.world)
    }

    // MARK: - OTPMapProvider: interaction

    func onMapTap(_ handler: @escaping (CLLocationCoordinate2D) -> Void) {
        mapTapHandler = handler
    }

    func onAnnotationSelected(_ handler: @escaping (String) -> Void) {
        annotationSelectionHandler = handler
    }

    // MARK: - OTPMapProvider: user location

    func showUserLocation(_ show: Bool) {
        wantsUserLocation = show
        scheduleChangeNotification()
    }

    func centerOnUserLocation(animated: Bool) {
        cameraTarget = .userLocation(animated: animated)
        scheduleChangeNotification()
    }

    // MARK: - OTPMapProvider: map configuration

    // The three below are deliberately no-ops.
    //
    // On the UIKit surface OTPKit owns a private map view and may reconfigure it freely.
    // Here it is a guest on the panel's one shared map, alongside stops, bookmarks and
    // rentals — and basemap style is the rider's own choice, persisted through
    // `MapViewModel` and the Map settings sheet. Letting a trip plan silently reset it
    // would be a bug, not a feature.

    func setMapType(_ mapType: MKMapType) {}

    func setUserInteractionEnabled(_ enabled: Bool) {}

    func setControlsVisible(_ visible: Bool) {}
}
