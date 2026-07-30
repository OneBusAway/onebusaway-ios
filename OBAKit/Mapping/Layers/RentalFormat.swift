//
//  RentalFormat.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import MapKit
import OBAKitCore
import OTPKit

/// Shared rider-facing formatting for rental entities, used by the detail sheet,
/// the cluster list, and the map annotation's fuel label.
enum RentalFormat {
    /// Cached: a fresh MKDistanceFormatter per row per render is waste.
    static let distanceFormatter = MKDistanceFormatter()

    /// A second formatter for space-constrained surfaces. The default style spells
    /// the unit out — 5,470 m renders as "3.4 miles" under en_US, where this one
    /// gives "3.4 mi". Only the abbreviated form fits under a map pin. The detail
    /// sheet's spelled-out rendering is deliberate, so the two coexist rather than
    /// one being mutated in place.
    static let abbreviatedDistanceFormatter: MKDistanceFormatter = {
        let formatter = MKDistanceFormatter()
        formatter.unitStyle = .abbreviated
        return formatter
    }()

    /// Straight-line walk estimate at the app's default walking speed.
    /// Nil beyond 10 km — a "119 min walk" line is noise, not information.
    static func walkTimeText(from userLocation: CLLocation?, to coordinate: CLLocationCoordinate2D) -> String? {
        guard let userLocation else { return nil }
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let meters = userLocation.distance(from: target)
        guard meters.isFinite, meters < 10_000 else { return nil }

        let minutes = max(1, Int((meters / WalkingSpeed.defaultMetersPerSecond / 60).rounded()))
        return String(format: OBALoc("rental_detail.walk_time_fmt", value: "%d min walk", comment: "Estimated walking time to a rental vehicle"), minutes)
    }

    static func batteryText(_ percent: Double) -> String {
        "\(Int((percent * 100).rounded()))%"
    }

    /// The text rendered beneath a rental map pin: battery percent when the feed
    /// provides it, else remaining range, else nothing.
    ///
    /// The percent-first ordering matches the mockup, but the range fallback is the
    /// common path in practice: on the launch feed `percent` is null across the
    /// whole fleet while `range` is populated.
    static func fuelLabelText(for rental: VehicleRental) -> String? {
        guard case .vehicle(let vehicle) = rental, let fuel = vehicle.fuel else { return nil }

        if let percent = fuel.percent {
            // Feeds do send values outside 0...1; clamp rather than render "120%".
            return batteryText(min(max(percent, 0), 1))
        }

        if let range = fuel.range {
            return abbreviatedDistanceFormatter.string(fromDistance: CLLocationDistance(range))
        }

        return nil
    }
}
