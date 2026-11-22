//
//  RealtimeVehicle.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import SwiftProtobuf

/// Represents a real-time vehicle position for display on the vehicles map and within core transit workflows.
public struct RealtimeVehicle: Identifiable, Hashable, Sendable {
    public let id: String
    public let coordinate: CLLocationCoordinate2D
    public let bearing: Float?
    public let tripID: String?
    public let routeID: String?
    public let vehicleID: String?
    public let vehicleLabel: String?
    public let timestamp: Date?

    // Agency information
    public let agencyID: String
    public let agencyName: String
    public let agencyPhone: String?
    public let agencyEmail: String?
    public let agencyURL: URL?
    public let fareURL: URL?

    // MARK: - Validation & Normalization Helpers

    /// Validates whether the given coordinate is within valid geographic bounds
    /// (latitude in [-90.0, 90.0], longitude in [-180.0, 180.0]) and is not Null Island (0.0, 0.0).
    public static func isValidCoordinate(_ coordinate: CLLocationCoordinate2D) -> Bool {
        isValidCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    /// Validates whether latitude and longitude are within valid geographic bounds
    /// (latitude in [-90.0, 90.0], longitude in [-180.0, 180.0]) and is not Null Island (0.0, 0.0).
    public static func isValidCoordinate(latitude: Double, longitude: Double) -> Bool {
        guard latitude.isFinite, longitude.isFinite else {
            return false
        }
        guard (-90.0...90.0).contains(latitude), (-180.0...180.0).contains(longitude) else {
            return false
        }
        if latitude == 0.0 && longitude == 0.0 {
            return false
        }
        return true
    }

    /// Convenience validator for Float coordinates from Protobuf messages.
    public static func isValidCoordinate(latitude: Float, longitude: Float) -> Bool {
        isValidCoordinate(latitude: Double(latitude), longitude: Double(longitude))
    }

    /// Normalises a bearing in degrees into the half-open interval `[0.0, 360.0)`.
    public static func normalizeBearing(_ bearing: Float) -> Float {
        guard bearing.isFinite else { return 0.0 }
        let remainder = (bearing.truncatingRemainder(dividingBy: 360.0) + 360.0).truncatingRemainder(dividingBy: 360.0)
        return remainder == 0.0 ? 0.0 : remainder
    }

    /// Normalises a bearing in degrees into the half-open interval `[0.0, 360.0)`.
    public static func normalizeBearing(_ bearing: Double) -> Double {
        guard bearing.isFinite else { return 0.0 }
        let remainder = (bearing.truncatingRemainder(dividingBy: 360.0) + 360.0).truncatingRemainder(dividingBy: 360.0)
        return remainder == 0.0 ? 0.0 : remainder
    }

    // MARK: - Initializers

    /// Memberwise initializer with coordinate validation and bearing normalisation.
    /// Returns `nil` if `coordinate` is invalid or Null Island (0.0, 0.0).
    public init?(
        id: String,
        coordinate: CLLocationCoordinate2D,
        bearing: Float? = nil,
        tripID: String? = nil,
        routeID: String? = nil,
        vehicleID: String? = nil,
        vehicleLabel: String? = nil,
        timestamp: Date? = nil,
        agencyID: String = "unknown",
        agencyName: String = "Unknown Agency",
        agencyPhone: String? = nil,
        agencyEmail: String? = nil,
        agencyURL: URL? = nil,
        fareURL: URL? = nil
    ) {
        guard Self.isValidCoordinate(coordinate) else {
            return nil
        }

        self.id = id
        self.coordinate = coordinate
        self.bearing = bearing.map(Self.normalizeBearing)
        self.tripID = tripID
        self.routeID = routeID
        self.vehicleID = vehicleID
        self.vehicleLabel = vehicleLabel
        self.timestamp = timestamp
        self.agencyID = agencyID
        self.agencyName = agencyName
        self.agencyPhone = agencyPhone
        self.agencyEmail = agencyEmail
        self.agencyURL = agencyURL
        self.fareURL = fareURL
    }

    /// Failable initializer from a GTFS-RT `TransitRealtime_FeedEntity`.
    /// Returns `nil` if the entity lacks a vehicle position or has an invalid/zero coordinate.
    public init?(from entity: TransitRealtime_FeedEntity, agency: Agency?) {
        guard entity.hasVehicle, entity.vehicle.hasPosition else {
            return nil
        }

        let vehicle = entity.vehicle
        let position = vehicle.position

        let coordinate = CLLocationCoordinate2D(
            latitude: CLLocationDegrees(position.latitude),
            longitude: CLLocationDegrees(position.longitude)
        )

        guard Self.isValidCoordinate(coordinate) else {
            return nil
        }

        self.id = entity.id
        self.coordinate = coordinate
        self.bearing = position.hasBearing ? Self.normalizeBearing(position.bearing) : nil
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

    // MARK: - Computed Properties

    /// Returns the bearing formatted as a compass direction (e.g., "Northeast (45°)")
    public var bearingDescription: String? {
        guard let bearing = bearing else { return nil }
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let rawIndex = Int((bearing + 22.5).truncatingRemainder(dividingBy: 360.0) / 45.0)
        let index = (rawIndex % 8 + 8) % 8
        let direction = directions[index]
        return "\(direction) (\(Int(bearing))°)"
    }

    // MARK: - Equatable & Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: RealtimeVehicle, rhs: RealtimeVehicle) -> Bool {
        lhs.id == rhs.id
    }
}
