//
//  OnDemandLocalityResolver.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation

/// Spec 2.8 Locality: the reverse-geocoded locality of a point when it
/// arrives within a second; otherwise nil and the copy falls back.
struct OnDemandLocalityResolver {
    static let timeout: TimeInterval = 1

    func locality(for coordinate: CLLocationCoordinate2D) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask {
                let geocoder = CLGeocoder()
                let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                let placemarks = try? await geocoder.reverseGeocodeLocation(location)
                return placemarks?.first?.locality
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(Self.timeout))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
