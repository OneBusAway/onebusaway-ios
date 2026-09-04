//
//  StopVehicleAnnotationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import MapKit
import Testing
import UIKit
import OBAKitCore
@testable import OBAKit

@MainActor
@Suite(.serialized)
final class StopVehicleAnnotationTests {

    /// Build a real `TripStatus` from a fixture — the annotation requires one, and
    /// `TripStatus` only decodes from JSON. `VehicleStatus.tripStatus` is
    /// non-optional (unlike `TripDetails.status`, which this particular fixture
    /// set only ever populates as `nil` — see `TripDetailsModelOperationTests`),
    /// so `api_where_vehicle_1_4351.json` (already exercised by
    /// `VehicleStatusModelOperationTests`) is the fixture that actually carries
    /// one. `Fixtures.loadRESTAPIPayload` decodes the whole
    /// `RESTAPIResponse<VehicleStatus>`, which — because `VehicleStatus:
    /// HasReferences` — calls `loadReferences` for us, which in turn calls
    /// `tripStatus.loadReferences` (`VehicleStatus.swift:83`). That's the step
    /// that resolves `TripStatus.activeTrip` from `Trip!`; skipping it would
    /// crash the force-unwrap the moment `applyTripStatus` reads
    /// `activeTrip.route.routeType`.
    private func makeTripStatus() throws -> TripStatus {
        let payload = try Fixtures.loadRESTAPIPayload(
            type: VehicleStatus.self,
            fileName: "api_where_vehicle_1_4351.json"
        )
        return payload.tripStatus
    }

    @Test func `Assigning the annotation gives the view its bus icon`() throws {
        // The real risk: PulsingVehicleAnnotationView's `annotation` didSet
        // requires a NON-NIL tripStatus, and `applyTripStatus` is the only
        // thing that ever fires `routeType`'s didSet — the initializer assigns it
        // before super.init, where didSet does not fire. A nil tripStatus
        // therefore yields a bare dot with no icon and no arrow, silently.
        // `image` being non-nil is the observable proof that chain ran.
        let annotation = StopVehicleAnnotation(
            id: "6821", routeID: "H", routeColor: .systemRed, departureID: "dep1",
            tripStatus: try makeTripStatus(),
            coordinate: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)
        )
        let view = PulsingVehicleAnnotationView(annotation: nil, reuseIdentifier: "test")

        view.annotation = annotation

        #expect(view.image != nil)
    }

    @Test func `The model's coordinate survives the superclass overwriting it`() throws {
        // VehicleAnnotation.init(tripStatus:) calls updateAnnotation(), which sets
        // coordinate from lastKnownLocation and falls back to (0, 0). The subclass
        // must assign afterwards or the marker lands on null island.
        let annotation = StopVehicleAnnotation(
            id: "6821", routeID: "H", routeColor: .systemRed, departureID: "dep1",
            tripStatus: try makeTripStatus(),
            coordinate: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)
        )
        #expect(annotation.coordinate.latitude == 47.6)
        #expect(annotation.coordinate.longitude == -122.3)
    }

    @Test func `Route color applies when set after the annotation`() throws {
        // Regression for the late-apply bug: isRealTime's didSet is the only writer
        // of annotationColor, and it runs when the annotation is assigned — so a
        // caller setting the color afterwards used to be ignored until the next
        // status apply, on a recycled view still carrying the previous route color.
        let view = PulsingVehicleAnnotationView(annotation: nil, reuseIdentifier: "test")
        view.annotation = StopVehicleAnnotation(
            id: "6821", routeID: "H", routeColor: .systemRed, departureID: "dep1",
            tripStatus: try makeTripStatus(),
            coordinate: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)
        )

        view.realTimeAnnotationColor = .systemGreen

        #expect(view.annotationColor == .systemGreen)
    }

    @Test func `update(tripStatus:coordinate:routeColor:) preserves identity and applies the new coordinate`() throws {
        // Regression for the refresh-mutates-in-place fix: `tripStatus`'s didSet
        // (inherited from VehicleAnnotation) re-derives `coordinate` from
        // `lastKnownLocation`, same as the initializer — so the position-preferred
        // coordinate passed to `update` must win, not get clobbered by that didSet.
        let annotation = StopVehicleAnnotation(
            id: "6821", routeID: "H", routeColor: .systemRed, departureID: "dep1",
            tripStatus: try makeTripStatus(),
            coordinate: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)
        )

        annotation.update(
            tripStatus: try makeTripStatus(),
            coordinate: CLLocationCoordinate2D(latitude: 48.1, longitude: -121.9),
            routeColor: .systemGreen
        )

        #expect(annotation.coordinate.latitude == 48.1)
        #expect(annotation.coordinate.longitude == -121.9)
        #expect(annotation.routeColor == .systemGreen)
    }

    /// #1341 item 3. The test above jumps (47.6, -122.3) → (48.1, -121.9) — about
    /// 60 km, or 120× `snapBeyondMeters` — so it only ever reaches `.snap`. The
    /// other two branches of `VehicleCoordinateUpdate.decision`, and the
    /// restore-then-apply ordering they depend on, had no coverage at all.
    ///
    /// This is the branch that proves the ordering. Below `ignoreBelowMeters`
    /// `apply` is a no-op, so whatever sits in `coordinate` when it runs is what
    /// the rider keeps. `tripStatus`'s `didSet` has just overwritten that with the
    /// fixture's `lastKnownLocation`; without `update`'s `self.coordinate = from`
    /// restore, every poll too small to matter would teleport the pin there.
    @Test func `A sub-threshold jitter leaves the coordinate where it was`() throws {
        let origin = CLLocationCoordinate2D(latitude: 47.6100, longitude: -122.3300)
        let annotation = StopVehicleAnnotation(
            id: "6821", routeID: "H", routeColor: .systemRed, departureID: "dep1",
            tripStatus: try makeTripStatus(),
            coordinate: origin
        )

        // ~1.1 m. Asserted rather than assumed so the test can't go vacuous if
        // the threshold is ever retuned.
        let jitter = CLLocationCoordinate2D(latitude: 47.610010, longitude: -122.3300)
        #expect(origin.distance(from: jitter) < VehicleCoordinateUpdate.ignoreBelowMeters)

        annotation.update(
            tripStatus: try makeTripStatus(),
            coordinate: jitter,
            routeColor: .systemGreen
        )

        #expect(annotation.coordinate.latitude == origin.latitude)
        #expect(annotation.coordinate.longitude == origin.longitude)

        // The value the didSet wrote, and the one the restore has to defeat.
        let fixtureLocation = try #require(makeTripStatus().lastKnownLocation?.coordinate)
        #expect(annotation.coordinate.latitude != fixtureLocation.latitude)
    }

    /// The middle branch, which the 60 km fixture skips. `apply` performs the
    /// assignment inside `UIView.animate`, so the coordinate arrives
    /// synchronously here — what this pins is that a city-block hop is *routed*
    /// through the animated branch instead of being discarded as jitter.
    @Test func `A city-block hop moves the annotation to the new coordinate`() throws {
        let origin = CLLocationCoordinate2D(latitude: 47.6100, longitude: -122.3300)
        let annotation = StopVehicleAnnotation(
            id: "6821", routeID: "H", routeColor: .systemRed, departureID: "dep1",
            tripStatus: try makeTripStatus(),
            coordinate: origin
        )

        // ~100 m: above `ignoreBelowMeters`, well below `snapBeyondMeters`.
        let hop = CLLocationCoordinate2D(latitude: 47.610900, longitude: -122.3300)
        let meters = origin.distance(from: hop)
        #expect(meters > VehicleCoordinateUpdate.ignoreBelowMeters)
        #expect(meters < VehicleCoordinateUpdate.snapBeyondMeters)

        annotation.update(
            tripStatus: try makeTripStatus(),
            coordinate: hop,
            routeColor: .systemGreen
        )

        #expect(annotation.coordinate.latitude == hop.latitude)
        #expect(annotation.coordinate.longitude == hop.longitude)
    }

    @Test func `Markers are not selectable by default, preserving the trip screen`() {
        let view = PulsingVehicleAnnotationView(annotation: nil, reuseIdentifier: "test")
        #expect(view.isUserInteractionEnabled == false)
    }

    @Test func `Selectable markers accept touches so the map can select them`() {
        let view = PulsingVehicleAnnotationView(annotation: nil, reuseIdentifier: "test")
        view.isSelectable = true
        #expect(view.isUserInteractionEnabled == true)
    }
}
