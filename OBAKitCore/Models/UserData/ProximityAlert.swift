//
//  ProximityAlert.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation

/// A user-created alert that fires when entering a geofence around a destination stop.
public class ProximityAlert: NSObject, Codable {
    public let id: UUID
    public let stopID: StopID
    public let stopName: String
    public let latitude: Double
    public let longitude: Double
    public let radiusMeters: Double
    public let createdAt: Date

    /// The coordinate of the destination stop.
    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// The maximum age (in seconds) before a proximity alert is considered stale and should be removed.
    public static let expirationInterval: TimeInterval = 24 * 60 * 60 // 24 hours

    public init(stop: Stop, radiusMeters: Double = 200.0, createdAt: Date = Date()) {
        self.id = UUID()
        self.stopID = stop.id
        self.stopName = stop.name
        self.latitude = stop.location.coordinate.latitude
        self.longitude = stop.location.coordinate.longitude
        self.radiusMeters = radiusMeters
        self.createdAt = createdAt
    }

    /// Whether this alert has expired based on `expirationInterval`.
    public var isExpired: Bool {
        Date().timeIntervalSince(createdAt) > ProximityAlert.expirationInterval
    }

    // MARK: - Equatable and Hashable

    public override func isEqual(_ object: Any?) -> Bool {
        guard let rhs = object as? ProximityAlert else { return false }
        return id == rhs.id
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(id)
        return hasher.finalize()
    }
}
