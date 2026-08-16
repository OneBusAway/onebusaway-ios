//
//  RentalMapItem.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import OTPKit

/// One thing drawn on the SwiftUI panel map for the rental layers: either a
/// vehicle on its own, or a group of them that would otherwise overlap.
///
/// The UIKit map gets this split from MapKit, which hands back
/// `MKClusterAnnotation`s. SwiftUI `Map` has no equivalent, so the panel
/// computes it — see `RentalClustering`.
enum RentalMapItem: Identifiable {
    case single(VehicleRental)
    case cluster(id: String, coordinate: CLLocationCoordinate2D, members: [VehicleRental])

    var id: String {
        switch self {
        case .single(let rental): return "rental-\(rental.id)"
        case .cluster(let id, _, _): return id
        }
    }

    var coordinate: CLLocationCoordinate2D {
        switch self {
        case .single(let rental): return rental.coordinate
        case .cluster(_, let coordinate, _): return coordinate
        }
    }

    /// Every rental this item stands for — one for a single, all of them for a
    /// cluster. Used to resolve a tapped item back to a sheet route.
    var members: [VehicleRental] {
        switch self {
        case .single(let rental): return [rental]
        case .cluster(_, _, let members): return members
        }
    }
}
