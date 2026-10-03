//
//  OnDemandServiceMatch.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation

/// Where a probe point came from (spec 2.1, 2.8).
public enum ProbeSource: Equatable, Sendable {
    /// The rider's location fix.
    case rider
    /// The map centre, when location is off or has no fix.
    case mapCenter
    /// A dropped pin, search result or planner endpoint.
    case point(label: String?)
}

/// The location facts a zone detail page was opened with (spec 3.6 item 3).
public struct OnDemandLocationCheck: Equatable, Sendable {
    public let source: ProbeSource
    public let isInside: Bool
    public let locality: String?
    public let coordinate: CLLocationCoordinate2D

    public init(source: ProbeSource, isInside: Bool, locality: String?, coordinate: CLLocationCoordinate2D) {
        self.source = source
        self.isInside = isInside
        self.locality = locality
        self.coordinate = coordinate
    }

    /// The same check with a resolved locality.
    public func withLocality(_ locality: String?) -> OnDemandLocationCheck {
        OnDemandLocationCheck(source: source, isInside: isInside, locality: locality, coordinate: coordinate)
    }

    public static func == (lhs: OnDemandLocationCheck, rhs: OnDemandLocationCheck) -> Bool {
        lhs.source == rhs.source
            && lhs.isInside == rhs.isInside
            && lhs.locality == rhs.locality
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

/// One `services-for-location` point-mode match with the service's
/// availability at the probe time (spec 2.1). `distanceToArea` is the
/// minimum over the service's areas and `nearestPointOnBoundary` the one
/// belonging to that minimum; a pure stop group has neither.
public struct OnDemandServiceMatch: Identifiable, Equatable, Sendable {
    /// The largest `distanceToArea` the dock and address check show (spec 2.4, 3.7).
    public static let nearbyRadiusMeters = 5_000.0

    public let service: OnDemandService
    public let matchReason: MatchReason
    public let distanceToArea: Double?
    public let nearestPointOnBoundary: CLLocationCoordinate2D?
    public let availability: OnDemandAvailability

    public var id: String { service.id }

    public var isInside: Bool { matchReason == .areaContainsPoint }

    /// Outside, with a finite distance the dock is allowed to show.
    public var isNearby: Bool {
        guard !isInside, let distanceToArea else { return false }
        return distanceToArea.isFinite && distanceToArea <= Self.nearbyRadiusMeters
    }

    public init(service: OnDemandService, matchReason: MatchReason, distanceToArea: Double?, nearestPointOnBoundary: CLLocationCoordinate2D?, availability: OnDemandAvailability) {
        self.service = service
        self.matchReason = matchReason
        self.distanceToArea = distanceToArea
        self.nearestPointOnBoundary = nearestPointOnBoundary
        self.availability = availability
    }

    /// Derives the distance fields from the service's areas.
    public init(service: OnDemandService, availability: OnDemandAvailability) {
        let nearest = service.areas
            .compactMap { area -> (distance: Double, point: CLLocationCoordinate2D?)? in
                area.distanceToArea.map { ($0, area.nearestPointOnBoundary) }
            }
            .min { $0.distance < $1.distance }
        self.init(
            service: service,
            matchReason: service.matchReason ?? .unknown,
            distanceToArea: nearest?.distance,
            nearestPointOnBoundary: nearest?.point,
            availability: availability
        )
    }

    /// Every list element of a point-mode response, evaluated at `now`.
    public static func matches(from services: [OnDemandService], now: Date) -> [OnDemandServiceMatch] {
        services.map { service in
            OnDemandServiceMatch(service: service, availability: OnDemandAvailability.evaluate(service: service, timeZone: service.timeZone, now: now))
        }
    }

    public static func == (lhs: OnDemandServiceMatch, rhs: OnDemandServiceMatch) -> Bool {
        lhs.id == rhs.id
            && lhs.matchReason == rhs.matchReason
            && lhs.distanceToArea == rhs.distanceToArea
            && lhs.nearestPointOnBoundary?.latitude == rhs.nearestPointOnBoundary?.latitude
            && lhs.nearestPointOnBoundary?.longitude == rhs.nearestPointOnBoundary?.longitude
            && lhs.availability == rhs.availability
    }
}

/// Spec 2.6: tier ascending, then distance ascending (0 inside, nil last),
/// then name with the locale's natural comparison, then id so the order is
/// total and stable across refreshes.
public func sortedSoonestUsable(_ matches: [OnDemandServiceMatch]) -> [OnDemandServiceMatch] {
    matches.sorted { lhs, rhs in
        if lhs.availability.usabilityTier != rhs.availability.usabilityTier {
            return lhs.availability.usabilityTier < rhs.availability.usabilityTier
        }
        switch (lhs.distanceToArea, rhs.distanceToArea) {
        case let (left?, right?) where left != right:
            return left < right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            break
        }
        let byName = lhs.service.name.localizedStandardCompare(rhs.service.name)
        if byName != .orderedSame {
            return byName == .orderedAscending
        }
        return lhs.id < rhs.id
    }
}
