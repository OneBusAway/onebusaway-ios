//
//  StopVehicleAnnotation.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import MapKit
import OBAKitCore
import UIKit

/// A live vehicle arriving at the selected stop.
///
/// **The `tripStatus` is mandatory, and that is the whole point of this type.**
/// `PulsingVehicleAnnotationView`'s `annotation` observer requires BOTH
/// `as? VehicleAnnotation` AND a non-nil `tripStatus` before it runs
/// `applyTripStatus`. And `applyTripStatus` is the only thing that ever sets
/// `routeType` and `isRealTime` in a way that fires their `didSet`s — the
/// view's own initializer assigns them *before* calling `super.init()`, where
/// `didSet` does not fire. So an annotation with a nil `tripStatus` renders as
/// a bare pulsing dot: **no bus icon, no heading arrow, no realtime state**,
/// and no error anywhere to explain it.
///
/// Every vehicle in `StopRouteFocusModel` is derived from a `tripStatus`
/// coordinate, so a non-nil status is always available at construction.
final class StopVehicleAnnotation: VehicleAnnotation {
    let id: String
    let routeID: RouteID
    var routeColor: UIColor
    /// The `ArrivalDeparture` this vehicle is serving, so the callout can read
    /// headsign, countdown, and adherence without another lookup.
    let departureID: String

    // Under this target's MainActor-default isolation, the compiler synthesizes
    // an implicit override of `VehicleAnnotation`'s `nonisolated override init()`
    // for this subclass's vtable slot and infers it MainActor — which conflicts
    // with the nonisolated superclass declaration ("has different actor
    // isolation from nonisolated overridden declaration"). Declaring it
    // explicitly, `nonisolated`, matches the superclass and resolves it; it's
    // unreachable because this type has no meaningful zero-argument state.
    nonisolated override init() {
        fatalError("StopVehicleAnnotation requires a tripStatus; use init(id:routeID:routeColor:departureID:tripStatus:coordinate:).")
    }

    init(
        id: String,
        routeID: RouteID,
        routeColor: UIColor,
        departureID: String,
        tripStatus: TripStatus,
        coordinate: CLLocationCoordinate2D
    ) {
        self.id = id
        self.routeID = routeID
        self.routeColor = routeColor
        self.departureID = departureID
        super.init(tripStatus: tripStatus)
        // AFTER super.init: `VehicleAnnotation.init(tripStatus:)` calls
        // `updateAnnotation()` (`VehicleAnnotation.swift:21`), which sets
        // `coordinate` from `lastKnownLocation` — falling back to a literal
        // (0, 0). Assigning here overrides that with the `position`-preferred,
        // null-island-rejecting coordinate the model already resolved.
        self.coordinate = coordinate
    }

    /// Suppresses MapKit's own callout title row.
    ///
    /// `VehicleAnnotation` sets `title` from `TripStatus.title` — "Vehicle ID:
    /// 1_4359" — which the callout drew above `detailCalloutAccessoryView`,
    /// duplicating the "Vehicle 1_4359" line inside it and pushing the whole card
    /// off the design. The setter is swallowed rather than left alone because the
    /// superclass rewrites `title` from every `tripStatus` assignment.
    ///
    /// A nil title does NOT suppress the callout itself: verified on iOS 26.3 that
    /// a view with `canShowCallout` and a `detailCalloutAccessoryView` still
    /// presents one, with the accessory reaching a window.
    /// `nonisolated` for the same reason as `init()` above: under this target's
    /// MainActor-default isolation the override would otherwise be inferred
    /// MainActor and clash with `MKPointAnnotation`'s nonisolated declaration.
    nonisolated override var title: String? {
        get { nil }
        set { }
    }

    /// Mutates this annotation in place for a refresh, preserving MapKit
    /// identity so an open callout survives an arrivals refresh instead of
    /// being dismissed by a remove/re-add cycle.
    func update(tripStatus: TripStatus, coordinate: CLLocationCoordinate2D, routeColor: UIColor) {
        // Assign tripStatus first: its `didSet` (inherited from
        // `VehicleAnnotation`) re-derives `coordinate` from `lastKnownLocation`,
        // same as the initializer's `super.init(tripStatus:)` — so the
        // position-preferred coordinate must be assigned AFTER, or it gets
        // clobbered exactly as the initializer's comment describes.
        self.tripStatus = tripStatus
        self.coordinate = coordinate
        self.routeColor = routeColor
    }
}
