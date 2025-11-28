//
//  RealtimeVehicle.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import OBAKitCore

/// Represents a real-time vehicle position for display on the vehicles map
struct RealtimeVehicle: Identifiable, Hashable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let bearing: Float?
    let tripID: String?
    let routeID: String?
    let vehicleID: String?
    let vehicleLabel: String?
    let timestamp: Date?

    // Agency information
    let agencyID: String
    let agencyName: String
    let agencyPhone: String?
    let agencyEmail: String?
    let agencyURL: URL?
    let fareURL: URL?

    init(from entity: TransitRealtime_FeedEntity, agency: Agency?) {
        self.id = entity.id
        let vehicle = entity.vehicle
        let position = vehicle.position

        self.coordinate = CLLocationCoordinate2D(
            latitude: CLLocationDegrees(position.latitude),
            longitude: CLLocationDegrees(position.longitude)
        )
        self.bearing = position.hasBearing ? position.bearing : nil
        self.tripID = vehicle.hasTrip ? vehicle.trip.tripID : nil
        self.routeID = vehicle.hasTrip ? vehicle.trip.routeID : nil
        self.vehicleID = vehicle.hasVehicle ? vehicle.vehicle.id : nil
        self.vehicleLabel = vehicle.hasVehicle ? vehicle.vehicle.label : nil
        self.timestamp = vehicle.hasTimestamp ? Date(timeIntervalSince1970: TimeInterval(vehicle.timestamp)) : nil

        // Agency information
        self.agencyID = agency?.id ?? "unknown"
        self.agencyName = agency?.name ?? "Unknown Agency"
        self.agencyPhone = agency?.phone.isEmpty == false ? agency?.phone : nil
        self.agencyEmail = agency?.email
        self.agencyURL = agency?.agencyURL
        self.fareURL = agency?.fareURL
    }

    /// Returns the bearing formatted as a compass direction (e.g., "Northeast (45°)")
    var bearingDescription: String? {
        guard let bearing = bearing else { return nil }
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((bearing + 22.5).truncatingRemainder(dividingBy: 360) / 45)
        let direction = directions[index]
        return "\(direction) (\(Int(bearing))°)"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: RealtimeVehicle, rhs: RealtimeVehicle) -> Bool {
        lhs.id == rhs.id
    }
}
