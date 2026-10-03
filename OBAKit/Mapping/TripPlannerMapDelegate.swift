//
//  TripPlannerMapDelegate.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OBAKitCore

/// The trip planner map's delegate, standing in front of OTPKit's
/// `MKMapViewAdapter` so route mode draws the same heading-cone user location
/// view as the main map. The adapter returns `nil` for `MKUserLocation`, and it
/// can't be subclassed outside OTPKit.
///
/// Everything else goes to the adapter. `MKMapView` only calls the optional
/// delegate methods its delegate responds to, so each one the adapter
/// implements needs a forwarder here; `TripPlannerMapDelegateTests` fails when
/// OTPKit adds one that isn't forwarded.
final class TripPlannerMapDelegate: NSObject, MKMapViewDelegate, LocationServiceDelegate {

    /// Weak: `TripPlanner` owns the adapter, and this object must not keep a
    /// dismissed planner's adapter alive.
    private weak var adapter: MKMapViewDelegate?
    private let locationService: LocationService
    private let showsHeading: Bool
    private weak var userLocationView: PulsingAnnotationView?

    init(forwardingTo adapter: MKMapViewDelegate, locationService: LocationService, showsHeading: Bool) {
        self.adapter = adapter
        self.locationService = locationService
        self.showsHeading = showsHeading
        super.init()
        locationService.addDelegate(self)
    }

    /// Call after creating the adapter, which claims `mapView.delegate` in its initializer.
    func attach(to mapView: MKMapView) {
        mapView.registerAnnotationView(PulsingAnnotationView.self)
        mapView.delegate = self

        // The map outlives each planner session, and MapKit doesn't ask again
        // for a user location view it already has.
        if let existing = mapView.view(for: mapView.userLocation) as? PulsingAnnotationView {
            existing.headingImageView.isHidden = !showsHeading
            userLocationView = existing
            updateUserHeading()
        }
    }

    // MARK: - MKMapViewDelegate

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard annotation is MKUserLocation else {
            return adapter?.mapView?(mapView, viewFor: annotation)
        }

        // Same rule as `MapRegionManager`: the system view draws the
        // imprecise-area circle under reduced accuracy; the pulsing dot can't.
        guard locationService.accuracyAuthorization != .reducedAccuracy else {
            return nil
        }

        let view = mapView.dequeueReusableAnnotationView(
            withIdentifier: MKMapView.reuseIdentifier(for: PulsingAnnotationView.self),
            for: annotation
        ) as? PulsingAnnotationView
        view?.headingImageView.isHidden = !showsHeading
        view?.canShowCallout = true
        userLocationView = view
        updateUserHeading()
        return view
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        adapter?.mapView?(mapView, rendererFor: overlay) ?? MKOverlayRenderer(overlay: overlay)
    }

    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        adapter?.mapView?(mapView, didSelect: view)
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        adapter?.mapView?(mapView, regionDidChangeAnimated: animated)
    }

    // MARK: - LocationServiceDelegate

    func locationService(_ service: LocationService, headingChanged heading: CLHeading?) {
        updateUserHeading()
    }

    private func updateUserHeading() {
        guard let heading = locationService.currentHeading, let userLocationView else {
            return
        }

        userLocationView.showUserHeading(heading)
    }
}
