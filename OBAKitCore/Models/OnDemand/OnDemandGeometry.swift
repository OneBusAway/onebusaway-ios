//
//  OnDemandGeometry.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation

/// One of eight compass points (spec 2.7).
public enum CompassDirection: String, CaseIterable, Sendable {
    case north, northeast, east, southeast, south, southwest, west, northwest
}

/// The nearest point on a service's boundary to a probe point (spec 2.7).
public struct OnDemandEdge: Equatable, Sendable {
    public let distanceMeters: Double
    public let point: CLLocationCoordinate2D
    /// From the probe point to `point`, degrees clockwise from north in `[0, 360)`.
    public let bearingDegrees: Double

    /// Where the rider must walk to reach the edge (inside near-edge title).
    public var edgeDirection: CompassDirection {
        OnDemandGeometry.compassDirection(bearingDegrees: bearingDegrees)
    }

    /// Where the rider stands relative to the zone (outside title).
    public var riderDirection: CompassDirection {
        OnDemandGeometry.compassDirection(bearingDegrees: bearingDegrees + 180)
    }

    public init(distanceMeters: Double, point: CLLocationCoordinate2D, bearingDegrees: Double) {
        self.distanceMeters = distanceMeters
        self.point = point
        self.bearingDegrees = bearingDegrees
    }

    public static func == (lhs: OnDemandEdge, rhs: OnDemandEdge) -> Bool {
        lhs.distanceMeters == rhs.distanceMeters
            && lhs.bearingDegrees == rhs.bearingDegrees
            && lhs.point.latitude == rhs.point.latitude
            && lhs.point.longitude == rhs.point.longitude
    }
}

/// The only client-side geometry the spec allows: the label point (2.3) and
/// the full-geometry nearest-edge distance (2.7). Containment for anything a
/// rider reads still comes from the server.
public enum OnDemandGeometry {

    public static let earthRadiusMeters = 6_371_000.0

    /// Inside with a client edge distance below this is "near edge".
    public static let nearEdgeMeters = 100.0
    /// Two services' pins closer than this read as one (ruling on coincident labels).
    public static let labelSeparationMeters = 50.0

    // MARK: - Projection

    /// Local equirectangular projection with its origin at the probe point:
    /// `x = (lon − lon0) · cos(lat0) · R`, `y = (lat − lat0) · R`.
    /// Public so the dock thumbnail projects zones with the same maths.
    public struct LocalProjection: Sendable {
        public let origin: CLLocationCoordinate2D
        private let cosLatitude: Double

        public init(origin: CLLocationCoordinate2D) {
            self.origin = origin
            cosLatitude = cos(origin.latitude * .pi / 180)
        }

        public func project(_ coordinate: CLLocationCoordinate2D) -> (x: Double, y: Double) {
            let x = (coordinate.longitude - origin.longitude) * .pi / 180 * cosLatitude * earthRadiusMeters
            let y = (coordinate.latitude - origin.latitude) * .pi / 180 * earthRadiusMeters
            return (x, y)
        }

        public func unproject(x: Double, y: Double) -> CLLocationCoordinate2D {
            let latitude = origin.latitude + y / earthRadiusMeters * 180 / .pi
            let longitude = cosLatitude == 0 ? origin.longitude : origin.longitude + x / (earthRadiusMeters * cosLatitude) * 180 / .pi
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    // MARK: - Label point

    /// Spec 2.3: the midpoint of the widest run of the bbox mid-latitude line
    /// inside the polygon (holes cut out, even-odd), else the exterior
    /// centroid when it is inside the ring, else the bbox centre.
    /// - Parameter rowFraction: where the label row sits up the bbox height;
    ///   0.5 is the spec's mid-latitude line, other rows move a coincident pin.
    public static func labelPoint(polygon: [[CLLocationCoordinate2D]], bbox: BoundingBox, rowFraction: Double = 0.5) -> CLLocationCoordinate2D {
        guard let exterior = polygon.first, exterior.count >= 3 else { return bbox.center }
        let midLatitude = bbox.minLatitude + (bbox.maxLatitude - bbox.minLatitude) * rowFraction

        let crossings = polygon.flatMap { longitudeCrossings(of: $0, atLatitude: midLatitude) }.sorted()
        var widest: (start: Double, end: Double)?
        var index = 0
        while index + 1 < crossings.count {
            let run = (start: crossings[index], end: crossings[index + 1])
            if widest == nil || run.end - run.start > widest!.end - widest!.start {
                widest = run
            }
            index += 2
        }
        if let widest {
            return CLLocationCoordinate2D(latitude: midLatitude, longitude: (widest.start + widest.end) / 2)
        }

        if let centroid = centroid(of: exterior), pointInRing(centroid, ring: exterior) {
            return centroid
        }
        return bbox.center
    }

    /// The label point of the largest polygon across `areas`, or nil when no
    /// area has a non-degenerate ring. Size is the exterior ring's shoelace
    /// area in the local projection, so a ring of repeated points never wins.
    public static func labelPoint(areas: [ServiceArea]) -> CLLocationCoordinate2D? {
        guard let largest = polygonsBySize(areas).first else { return nil }
        return labelPoint(polygon: largest, bbox: boundingBox(of: largest[0]))
    }

    /// The label rows tried on a service's largest polygon once every
    /// polygon's own label is taken.
    private static let fallbackRowFractions = [1.0 / 3, 2.0 / 3]

    /// One label point per service, placed in service id order so a pan
    /// never swaps them. A service whose label falls within
    /// `labelSeparationMeters` of an earlier one takes its next-largest
    /// polygon's label, then the label rows at 1/3 and 2/3 of its largest
    /// polygon's bbox height; when all of those collide it keeps its own.
    /// Services with no drawable ring get no entry.
    public static func labelPoints(areasByServiceID: [String: [ServiceArea]]) -> [String: CLLocationCoordinate2D] {
        var placed: [String: CLLocationCoordinate2D] = [:]
        for serviceID in areasByServiceID.keys.sorted() {
            let candidates = labelCandidates(areas: areasByServiceID[serviceID] ?? [])
            guard let preferred = candidates.first else { continue }
            let isClear = { (candidate: CLLocationCoordinate2D) in
                placed.values.allSatisfy { distanceMeters(candidate, $0) >= labelSeparationMeters }
            }
            placed[serviceID] = candidates.first(where: isClear) ?? preferred
        }
        return placed
    }

    private static func labelCandidates(areas: [ServiceArea]) -> [CLLocationCoordinate2D] {
        let polygons = polygonsBySize(areas)
        guard let largest = polygons.first else { return [] }
        let largestBox = boundingBox(of: largest[0])
        return polygons.map { labelPoint(polygon: $0, bbox: boundingBox(of: $0[0])) }
            + fallbackRowFractions.map { labelPoint(polygon: largest, bbox: largestBox, rowFraction: $0) }
    }

    /// Every polygon with a non-degenerate exterior, largest first. Size is
    /// the exterior ring's shoelace area in the local projection, so a ring
    /// of repeated points never counts.
    private static func polygonsBySize(_ areas: [ServiceArea]) -> [[[CLLocationCoordinate2D]]] {
        areas
            .flatMap(\.polygons)
            .compactMap { polygon -> (polygon: [[CLLocationCoordinate2D]], area: Double)? in
                guard let exterior = polygon.first, exterior.count >= 3 else { return nil }
                let area = projectedArea(of: exterior)
                return area > 0 ? (polygon, area) : nil
            }
            .sorted { $0.area > $1.area }
            .map(\.polygon)
    }

    private static func distanceMeters(_ lhs: CLLocationCoordinate2D, _ rhs: CLLocationCoordinate2D) -> Double {
        let offset = LocalProjection(origin: lhs).project(rhs)
        return (offset.x * offset.x + offset.y * offset.y).squareRoot()
    }

    /// Longitudes where `ring` crosses the horizontal line at `latitude`.
    private static func longitudeCrossings(of ring: [CLLocationCoordinate2D], atLatitude latitude: Double) -> [Double] {
        guard ring.count >= 2 else { return [] }
        var crossings: [Double] = []
        for index in ring.indices {
            let start = ring[index]
            let end = ring[(index + 1) % ring.count]
            guard (start.latitude > latitude) != (end.latitude > latitude) else { continue }
            let fraction = (latitude - start.latitude) / (end.latitude - start.latitude)
            crossings.append(start.longitude + fraction * (end.longitude - start.longitude))
        }
        return crossings
    }

    /// Shoelace centroid in degrees; nil for a degenerate ring.
    private static func centroid(of ring: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D? {
        var twiceArea = 0.0
        var latitudeSum = 0.0
        var longitudeSum = 0.0
        for index in ring.indices {
            let current = ring[index]
            let next = ring[(index + 1) % ring.count]
            let cross = current.longitude * next.latitude - next.longitude * current.latitude
            twiceArea += cross
            longitudeSum += (current.longitude + next.longitude) * cross
            latitudeSum += (current.latitude + next.latitude) * cross
        }
        guard abs(twiceArea) > 1e-18 else { return nil }
        return CLLocationCoordinate2D(latitude: latitudeSum / (3 * twiceArea), longitude: longitudeSum / (3 * twiceArea))
    }

    /// Absolute shoelace area of `ring` in square metres of the local
    /// projection centred on the ring's own bbox.
    static func projectedArea(of ring: [CLLocationCoordinate2D]) -> Double {
        guard ring.count >= 3 else { return 0 }
        let projection = LocalProjection(origin: boundingBox(of: ring).center)
        let points = ring.map(projection.project)
        var twiceArea = 0.0
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            twiceArea += current.x * next.y - next.x * current.y
        }
        return abs(twiceArea) / 2
    }

    /// Ray casting, even-odd. Allowed only for the label point.
    static func pointInRing(_ point: CLLocationCoordinate2D, ring: [CLLocationCoordinate2D]) -> Bool {
        var inside = false
        var previous = ring.count - 1
        for index in ring.indices {
            let current = ring[index]
            let last = ring[previous]
            if (current.latitude > point.latitude) != (last.latitude > point.latitude) {
                let crossing = (last.longitude - current.longitude) * (point.latitude - current.latitude) / (last.latitude - current.latitude) + current.longitude
                if point.longitude < crossing {
                    inside.toggle()
                }
            }
            previous = index
        }
        return inside
    }

    public static func boundingBox(of ring: [CLLocationCoordinate2D]) -> BoundingBox {
        BoundingBox(
            minLongitude: ring.map(\.longitude).min() ?? 0,
            minLatitude: ring.map(\.latitude).min() ?? 0,
            maxLongitude: ring.map(\.longitude).max() ?? 0,
            maxLatitude: ring.map(\.latitude).max() ?? 0
        )
    }

    // MARK: - Nearest edge

    /// The closest point on any ring (exterior and holes) of any area to `from`.
    /// Nil when no area carries geometry.
    public static func nearestBoundaryPoint(from probe: CLLocationCoordinate2D, areas: [ServiceArea]) -> OnDemandEdge? {
        let projection = LocalProjection(origin: probe)
        var best: (distance: Double, nearest: (x: Double, y: Double))?

        for ring in areas.flatMap(\.polygons).flatMap({ $0 }) where ring.count >= 2 {
            let points = ring.map(projection.project)
            for index in points.indices {
                let start = points[index]
                let end = points[(index + 1) % points.count]
                let nearest = nearestPoint(onSegmentFrom: start, to: end)
                let distance = hypot(nearest.x, nearest.y)
                if best == nil || distance < best!.distance {
                    best = (distance, nearest)
                }
            }
        }

        guard let best else { return nil }
        return OnDemandEdge(
            distanceMeters: best.distance,
            point: projection.unproject(x: best.nearest.x, y: best.nearest.y),
            bearingDegrees: normalizedBearing(dx: best.nearest.x, dy: best.nearest.y)
        )
    }

    /// An edge from the server's `distanceToArea` and `nearestPointOnBoundary`:
    /// the bearing runs from the probe point to the server point.
    public static func edge(from probe: CLLocationCoordinate2D, toServerPoint point: CLLocationCoordinate2D, distanceMeters: Double) -> OnDemandEdge {
        OnDemandEdge(distanceMeters: distanceMeters, point: point, bearingDegrees: bearingDegrees(from: probe, to: point))
    }

    /// The point on the segment nearest the origin, with the projection
    /// parameter clamped to `[0, 1]`.
    private static func nearestPoint(onSegmentFrom start: (x: Double, y: Double), to end: (x: Double, y: Double)) -> (x: Double, y: Double) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return start }
        let parameter = max(0, min(1, -(start.x * dx + start.y * dy) / lengthSquared))
        return (start.x + parameter * dx, start.y + parameter * dy)
    }

    // MARK: - Bearing

    public static func bearingDegrees(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let projected = LocalProjection(origin: from).project(to)
        return normalizedBearing(dx: projected.x, dy: projected.y)
    }

    /// `atan2(dx, dy)` in degrees from north, normalised to `[0, 360)`.
    private static func normalizedBearing(dx: Double, dy: Double) -> Double {
        let degrees = atan2(dx, dy) * 180 / .pi
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    /// `floor((bearing + 22.5) / 45) mod 8`, after normalising the bearing.
    public static func compassDirection(bearingDegrees: Double) -> CompassDirection {
        let wrapped = bearingDegrees.truncatingRemainder(dividingBy: 360)
        let positive = wrapped < 0 ? wrapped + 360 : wrapped
        let bucket = Int(floor((positive + 22.5) / 45)) % 8
        return CompassDirection.allCases[bucket]
    }
}
