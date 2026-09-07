//
//  GetOffAlert.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation

/// A rider-created alert that fires once, via a geofence, when they are
/// approaching a specific stop during an active trip.
///
/// Stored in `UserDataStore` and armed via `LocationService` region monitoring,
/// following the same lifecycle as `ProximityAlert`. The key difference is that
/// a `GetOffAlert` is trip-scoped: it carries the `tripID` and `stopSequence`
/// it was set on so it can be identified and cancelled when the trip ends, even
/// if the rider navigates away from the trip page before the stop is reached.
///
/// Expires after `expirationInterval` (4 hours), which covers a single transit
/// trip with margin. Expiry is checked at every reconciliation, not just at
/// notification delivery, so a stale alert never occupies a region-monitoring
/// slot overnight.
// @unchecked Sendable: all stored properties are immutable `let`s set at init
// and never mutated — the class is safe to pass across concurrency domains.
public final class GetOffAlert: NSObject, Codable, @unchecked Sendable {

    // MARK: - Identity

    public let id: UUID

    // MARK: - Stop Info

    /// The ID of the stop the rider wants to get off at.
    public let stopID: StopID

    /// The display name of the stop, shown in the notification body.
    public let stopName: String

    /// Coordinate of the stop, used as the geofence centre.
    public let latitude: Double
    public let longitude: Double

    /// The geofence radius. Clamped to `minimumRadiusMeters`…`maximumRadiusMeters`
    /// on init and on decode so no stored value can exceed device limits.
    public let radiusMeters: CLLocationDistance

    // MARK: - Trip Scoping

    /// The trip this alert was set on. Used to cancel the alert if the trip
    /// ends before the stop is reached, avoiding a stale geofence.
    public let tripID: String

    /// The stop's position in the trip's stop list. Carried so that if two trips
    /// on the same service call at the same stop (loop routes), this alert is
    /// associated with the correct leg.
    public let stopSequence: Int

    // MARK: - Region

    /// The OBA region the alert was set in, so a tap on the notification opens
    /// the right stop page. Optional for the same reason as `ProximityAlert.regionID`:
    /// alerts persisted before this field existed should fall back to current region.
    public let regionID: Int?

    // MARK: - Lifecycle

    public let createdAt: Date

    /// Alerts expire after 4 hours — long enough for any transit trip, short
    /// enough that a forgotten alert never blocks a slot the following morning.
    public static let expirationInterval: TimeInterval = 4 * 60 * 60

    public var isExpired: Bool {
        Date().timeIntervalSince(createdAt) > Self.expirationInterval
    }

    // MARK: - Coordinate

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    // MARK: - Radius Constants

    /// Default geofence radius. Slightly tighter than `ProximityAlert.defaultRadiusMeters`
    /// because an in-trip alert fires while the rider is on the vehicle and
    /// can act quickly.
    public static let defaultRadiusMeters: CLLocationDistance = 150

    public static let minimumRadiusMeters: CLLocationDistance = 50
    public static let maximumRadiusMeters: CLLocationDistance = 10_000

    static func clampedRadius(_ radius: CLLocationDistance) -> CLLocationDistance {
        guard radius.isFinite else {
            Logger.warn("GetOffAlert radius \(radius) is not finite; using \(defaultRadiusMeters)m default.")
            return defaultRadiusMeters
        }
        let clamped = min(max(radius, minimumRadiusMeters), maximumRadiusMeters)
        if clamped != radius {
            Logger.warn("GetOffAlert radius \(radius)m out of range; clamped to \(clamped)m.")
        }
        return clamped
    }

    // MARK: - Init

    public init(
        stop: Stop,
        tripID: String,
        stopSequence: Int,
        radiusMeters: CLLocationDistance = GetOffAlert.defaultRadiusMeters,
        createdAt: Date = Date(),
        regionID: Int? = nil
    ) {
        self.id = UUID()
        self.stopID = stop.id
        self.stopName = stop.name
        self.latitude = stop.location.coordinate.latitude
        self.longitude = stop.location.coordinate.longitude
        self.radiusMeters = GetOffAlert.clampedRadius(radiusMeters)
        self.tripID = tripID
        self.stopSequence = stopSequence
        self.createdAt = createdAt
        self.regionID = regionID
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, stopID, stopName, latitude, longitude, radiusMeters
        case tripID, stopSequence, regionID, createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        stopID = try c.decode(StopID.self, forKey: .stopID)
        stopName = try c.decode(String.self, forKey: .stopName)
        latitude = try c.decode(Double.self, forKey: .latitude)
        longitude = try c.decode(Double.self, forKey: .longitude)
        radiusMeters = GetOffAlert.clampedRadius(try c.decode(CLLocationDistance.self, forKey: .radiusMeters))
        tripID = try c.decode(String.self, forKey: .tripID)
        stopSequence = try c.decode(Int.self, forKey: .stopSequence)
        regionID = try c.decodeIfPresent(Int.self, forKey: .regionID)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }

    // MARK: - Equatable / Hashable

    public override func isEqual(_ object: Any?) -> Bool {
        guard let rhs = object as? GetOffAlert else { return false }
        return id == rhs.id
    }

    override public var hash: Int {
        var h = Hasher()
        h.combine(id)
        return h.finalize()
    }
}
