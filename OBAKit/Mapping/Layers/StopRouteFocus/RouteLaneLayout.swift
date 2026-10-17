//
//  RouteLaneLayout.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import MapKit
import OBAKitCore

/// Spreads routes that share a street across it, side by side, instead of drawing
/// them one on top of the other, where only the last one drawn shows (#1569).
///
/// Each route gets a lane at every point along it: 0, the middle of its street, or a
/// signed number of lane widths to one side where other routes share the street.
/// Lanes are counted in widths rather than distances because the lines they keep
/// apart are as wide in screen points at every zoom; `Line.offsetCoordinates(laneWidth:)`
/// turns them into map points for the zoom the map is at.
///
/// Two routes share a street where they run within `Rules.sharingDistance` of each
/// other and nearly parallel, in either direction; streets that only cross don't
/// count. Where several routes share, they take slots in the order they were given,
/// so a route keeps to the same side all along a shared stretch. The slots are
/// counted from the side of the first of them, so two routes running opposite ways
/// don't each move to their own right and land on the same side.
nonisolated enum RouteLaneLayout {

    enum Rules {
        /// Agencies trace one street through different points, and some down
        /// either side of it. Further apart than this is a different street.
        static let sharingDistance: CLLocationDistance = 20
        /// How far from parallel two lines can run and still share the street.
        static let maximumAngle: Double = 25 * .pi / 180
        /// Long segments are cut into pieces this long, so a line moves over where
        /// the sharing starts rather than drifting across a whole segment.
        static let sampleSpacing: CLLocationDistance = 20
    }

    /// One route's line, ready to offset.
    struct Line {
        /// The route's shape, resampled, in map points.
        let points: [MKMapPoint]
        /// At each point, in lane widths. Positive is to the right of travel.
        let lanes: [Double]

        var isShared: Bool { lanes.contains { $0 != 0 } }

        /// The line, moved off the middle of the street wherever it shares it.
        ///
        /// - Parameter laneWidth: In map points.
        func offsetCoordinates(laneWidth: Double) -> [CLLocationCoordinate2D] {
            points.indices.map { index in
                guard lanes[index] != 0 else { return points[index].coordinate }
                let normal = RouteLaneLayout.normal(at: index, in: points)
                let distance = lanes[index] * laneWidth
                return MKMapPoint(
                    x: points[index].x + normal.dx * distance,
                    y: points[index].y + normal.dy * distance
                ).coordinate
            }
        }
    }

    /// - Parameter routes: In priority order: the first route takes the first slot
    ///   wherever it shares a street.
    /// - Returns: A line for every route with at least two distinct points.
    static func lines(for routes: [(routeID: RouteID, coordinates: [CLLocationCoordinate2D])]) -> [RouteID: Line] {
        guard let anyCoordinate = routes.lazy.compactMap(\.coordinates.first).first else { return [:] }
        // One scale for the whole set: the routes serving one stop span a few
        // kilometers, over which it barely changes.
        let mapPointsPerMeter = MKMapPointsPerMeterAtLatitude(anyCoordinate.latitude)

        let sampled = routes.compactMap { route -> (routeID: RouteID, points: [MKMapPoint])? in
            let points = resample(route.coordinates.map(MKMapPoint.init), spacing: Rules.sampleSpacing * mapPointsPerMeter)
            return points.count >= 2 ? (route.routeID, points) : nil
        }

        let reach = Rules.sharingDistance * mapPointsPerMeter
        let index = SegmentIndex(lines: sampled.map(\.points), cellSize: reach)
        let minimumAlignment = cos(Rules.maximumAngle)

        var lines: [RouteID: Line] = [:]
        for (routeIndex, route) in sampled.enumerated() {
            let lanes = route.points.indices.map { pointIndex -> Double in
                let direction = tangent(at: pointIndex, in: route.points)
                // Every other route sharing the street here, with whether it runs
                // the same way as this one.
                var sharers: [(route: Int, sameWay: Bool)] = []
                for match in index.nearest(to: route.points[pointIndex], within: reach, excluding: routeIndex) {
                    let alignment = direction.dx * match.direction.dx + direction.dy * match.direction.dy
                    if abs(alignment) >= minimumAlignment {
                        sharers.append((match.line, alignment > 0))
                    }
                }
                guard !sharers.isEmpty else { return 0 }

                sharers.append((routeIndex, true))
                sharers.sort { $0.route < $1.route }
                let slot = Double(sharers.firstIndex { $0.route == routeIndex } ?? 0)
                let centered = slot - Double(sharers.count - 1) / 2
                // Counted from the first sharer's right, which is this route's left
                // when the two run opposite ways.
                return sharers[0].sameWay ? centered : -centered
            }
            lines[route.routeID] = Line(points: route.points, lanes: lanes)
        }
        return lines
    }

    // MARK: - Geometry

    struct Vector {
        var dx: Double
        var dy: Double

        var length: Double { hypot(dx, dy) }

        var normalized: Vector? {
            let length = length
            return length > 0 ? Vector(dx: dx / length, dy: dy / length) : nil
        }

        /// A quarter turn clockwise on screen, where y runs down: the right of travel.
        var right: Vector { Vector(dx: -dy, dy: dx) }
    }

    /// `points` with any repeats dropped and every segment longer than `spacing` cut
    /// into equal pieces no longer than it.
    static func resample(_ points: [MKMapPoint], spacing: Double) -> [MKMapPoint] {
        guard var previous = points.first else { return [] }
        var resampled = [previous]
        for point in points.dropFirst() {
            let length = hypot(point.x - previous.x, point.y - previous.y)
            guard length > 0 else { continue }
            let pieces = max(1, Int((length / spacing).rounded(.up)))
            for piece in 1...pieces {
                let fraction = Double(piece) / Double(pieces)
                resampled.append(MKMapPoint(
                    x: previous.x + (point.x - previous.x) * fraction,
                    y: previous.y + (point.y - previous.y) * fraction
                ))
            }
            previous = point
        }
        return resampled
    }

    /// The direction of travel through point `index`, from its neighbors.
    private static func tangent(at index: Int, in points: [MKMapPoint]) -> Vector {
        let before = points[max(index - 1, 0)], after = points[min(index + 1, points.count - 1)]
        return Vector(dx: after.x - before.x, dy: after.y - before.y).normalized ?? Vector(dx: 1, dy: 0)
    }

    /// Which way, and how far, one lane width at point `index` moves it: to the right
    /// of travel, lengthened at a corner so the line beside it keeps its width.
    fileprivate static func normal(at index: Int, in points: [MKMapPoint]) -> Vector {
        func segmentRight(_ from: Int, _ to: Int) -> Vector? {
            guard from >= 0, to < points.count else { return nil }
            return Vector(dx: points[to].x - points[from].x, dy: points[to].y - points[from].y).normalized?.right
        }
        let incoming = segmentRight(index - 1, index), outgoing = segmentRight(index, index + 1)
        guard let incoming else { return outgoing ?? Vector(dx: 0, dy: 0) }
        guard let outgoing else { return incoming }
        guard let bisector = Vector(dx: incoming.dx + outgoing.dx, dy: incoming.dy + outgoing.dy).normalized else {
            return incoming
        }
        // A miter, capped so a hairpin doesn't throw the point off into the distance.
        let alignment = max(bisector.dx * incoming.dx + bisector.dy * incoming.dy, 0.5)
        return Vector(dx: bisector.dx / alignment, dy: bisector.dy / alignment)
    }
}

/// Finds the routes near a point without measuring every segment of every route.
nonisolated private struct SegmentIndex {
    struct Match {
        let line: Int
        let direction: RouteLaneLayout.Vector
    }

    private struct Cell: Hashable {
        let x: Int
        let y: Int
    }

    private struct Segment {
        let line: Int
        let start: MKMapPoint
        let end: MKMapPoint
    }

    private let cellSize: Double
    private var cells: [Cell: [Segment]] = [:]

    init(lines: [[MKMapPoint]], cellSize: Double) {
        self.cellSize = cellSize
        for (line, points) in lines.enumerated() {
            for (start, end) in zip(points, points.dropFirst()) {
                let segment = Segment(line: line, start: start, end: end)
                let low = cell(MKMapPoint(x: min(start.x, end.x), y: min(start.y, end.y)))
                let high = cell(MKMapPoint(x: max(start.x, end.x), y: max(start.y, end.y)))
                for x in low.x...high.x {
                    for y in low.y...high.y {
                        cells[Cell(x: x, y: y), default: []].append(segment)
                    }
                }
            }
        }
    }

    private func cell(_ point: MKMapPoint) -> Cell {
        Cell(x: Int((point.x / cellSize).rounded(.down)), y: Int((point.y / cellSize).rounded(.down)))
    }

    /// Each other line's nearest segment to `point`, among those within `reach`.
    func nearest(to point: MKMapPoint, within reach: Double, excluding excluded: Int) -> [Match] {
        let center = cell(point)
        var nearest: [Int: (distance: Double, segment: Segment)] = [:]
        for x in (center.x - 1)...(center.x + 1) {
            for y in (center.y - 1)...(center.y + 1) {
                for segment in cells[Cell(x: x, y: y)] ?? [] where segment.line != excluded {
                    let distance = Self.distance(from: point, to: segment)
                    guard distance <= reach, distance < nearest[segment.line]?.distance ?? .infinity else { continue }
                    nearest[segment.line] = (distance, segment)
                }
            }
        }
        return nearest.compactMap { line, found in
            RouteLaneLayout.Vector(dx: found.segment.end.x - found.segment.start.x, dy: found.segment.end.y - found.segment.start.y)
                .normalized
                .map { Match(line: line, direction: $0) }
        }
    }

    private static func distance(from point: MKMapPoint, to segment: Segment) -> Double {
        let dx = segment.end.x - segment.start.x, dy = segment.end.y - segment.start.y
        let lengthSquared = dx * dx + dy * dy
        let t = lengthSquared == 0 ? 0 : max(0, min(1, ((point.x - segment.start.x) * dx + (point.y - segment.start.y) * dy) / lengthSquared))
        return hypot(point.x - (segment.start.x + t * dx), point.y - (segment.start.y + t * dy))
    }
}
