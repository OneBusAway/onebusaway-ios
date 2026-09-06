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

    /// The region the rider was looking at when they set this alert.
    ///
    /// Optional because alerts persisted before the field existed have no answer
    /// and inventing one would be worse than admitting it: `nil` means "fall back
    /// to whichever region is current when the notification is tapped", which is
    /// exactly what every alert did before.
    public let regionID: Int?

    /// The coordinate of the destination stop.
    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// The maximum age (in seconds) before a proximity alert is considered stale and should be removed.
    public static let expirationInterval: TimeInterval = 24 * 60 * 60 // 24 hours

    // MARK: - Radius

    /// The geofence radius used when a caller doesn't choose one.
    public static let defaultRadiusMeters: CLLocationDistance = 200

    /// The tightest geofence worth arming. Core Location's own accuracy floor
    /// means anything smaller fires late, early, or not at all.
    public static let minimumRadiusMeters: CLLocationDistance = 50

    /// A conservative ceiling for a radius, applied where the device's real limit
    /// isn't reachable.
    ///
    /// `LocationManager.maximumRegionMonitoringDistance` is the authoritative
    /// value and varies with hardware and current resource constraints, so this
    /// model can't consult it. `LocationService` clamps a second time against the
    /// live value when it actually arms the region.
    public static let maximumRadiusMeters: CLLocationDistance = 10_000

    /// Brings `radius` into the monitorable range, logging whenever it has to.
    ///
    /// An out-of-range radius can't simply be passed along: Core Location rejects
    /// an oversize region with `CLError.regionMonitoringFailure`, delivered
    /// asynchronously and without the radius, so the alert would fail with nothing
    /// anywhere recording what it had asked for.
    static func clampedRadius(_ radius: CLLocationDistance) -> CLLocationDistance {
        guard radius.isFinite else {
            Logger.warn("ProximityAlert radius \(radius) is not a finite number; using the \(defaultRadiusMeters)m default.")
            return defaultRadiusMeters
        }

        let clamped = min(max(radius, minimumRadiusMeters), maximumRadiusMeters)
        if clamped != radius {
            Logger.warn("ProximityAlert radius \(radius)m falls outside \(minimumRadiusMeters)m–\(maximumRadiusMeters)m; clamped to \(clamped)m.")
        }

        return clamped
    }

    public init(stop: Stop, radiusMeters: CLLocationDistance = ProximityAlert.defaultRadiusMeters, createdAt: Date = Date(), regionID: Int? = nil) {
        self.id = UUID()
        self.stopID = stop.id
        self.stopName = stop.name
        self.latitude = stop.location.coordinate.latitude
        self.longitude = stop.location.coordinate.longitude
        self.radiusMeters = ProximityAlert.clampedRadius(radiusMeters)
        self.createdAt = createdAt
        self.regionID = regionID
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, stopID, stopName, latitude, longitude, radiusMeters, createdAt, regionID
    }

    /// Re-applies the radius clamp on the way in, so the invariant also holds for
    /// alerts persisted by a build that predates it. Keys match the property
    /// names the synthesized conformance used, keeping stored alerts readable.
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        stopID = try container.decode(StopID.self, forKey: .stopID)
        stopName = try container.decode(String.self, forKey: .stopName)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        radiusMeters = ProximityAlert.clampedRadius(try container.decode(CLLocationDistance.self, forKey: .radiusMeters))
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        regionID = try container.decodeIfPresent(Int.self, forKey: .regionID)
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
