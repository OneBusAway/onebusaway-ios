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

    init(from entity: TransitRealtime_FeedEntity) {
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
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: RealtimeVehicle, rhs: RealtimeVehicle) -> Bool {
        lhs.id == rhs.id
    }
}
