//
//  RouteDirectionArrows.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OBAKitCore
import Synchronization
import UIKit

/// Where the direction chevrons sit along a route line.
///
/// Every rule is in screen points, so the layout depends on the zoom: the caller
/// supplies the line in any unit and `scale`, the screen points per unit. A
/// candidate falls every `spacing` points along the line; it may shift a little to
/// find a clear spot, and is dropped rather than shifted further. A clear spot is
/// on a segment long enough to read, away from either end of it — a chevron on a
/// corner looks broken — and away from every stop marker.
///
/// Candidates sit at fixed distances along the whole line and each is resolved on
/// its own, so asking about one part of the line gives the same arrows there as
/// asking about all of it. `RouteLineRenderer` depends on that: MapKit draws a line
/// tile by tile, and an arrow straddling two tiles has to land in the same place
/// in both.
nonisolated struct RouteArrowLayout {

    struct Rules {
        /// From the start of the line to the first candidate.
        var startOffset: CGFloat = 30
        var spacing: CGFloat = 64
        /// How far a candidate may move, either way, to find a clear spot.
        var maximumShift: CGFloat = 8
        var minimumSegmentLength: CGFloat = 40
        /// From either end of the segment.
        var cornerClearance: CGFloat = 12
        /// From the center of any stop marker.
        var markerClearance: CGFloat = 22

        static let standard = Rules()
    }

    struct Arrow: Equatable {
        /// Which candidate this is, counting from the start of the line.
        let index: Int
        let point: CGPoint
        /// Radians from +x toward +y: y runs down, as on screen and in MapKit's map
        /// points, so a positive angle turns clockwise.
        let angle: CGFloat
    }

    private let points: [CGPoint]
    /// The distance along the line to each point, in the line's own units.
    private let distances: [CGFloat]

    init(points: [CGPoint]) {
        self.points = points
        var distances: [CGFloat] = []
        distances.reserveCapacity(points.count)
        var total: CGFloat = 0
        for (index, point) in points.enumerated() {
            if index > 0 {
                total += Self.distance(points[index - 1], point)
            }
            distances.append(total)
        }
        self.distances = distances
    }

    /// - Parameters:
    ///   - scale: Screen points per unit of the line.
    ///   - markers: Stop marker centers, in the line's units.
    ///   - rect: When set, only arrows that could reach this rect, in the line's
    ///     units. An arrow is returned whole even when only part of it is inside.
    func arrows(
        scale: CGFloat,
        avoiding markers: [CGPoint] = [],
        in rect: CGRect? = nil,
        margin: CGFloat = 0,
        rules: Rules = .standard
    ) -> [Arrow] {
        guard points.count >= 2, scale.isFinite, scale > 0, rules.spacing > 0 else { return [] }

        let length = (distances.last ?? 0) * scale
        guard length >= rules.startOffset else { return [] }
        let lastIndex = Int(((length - rules.startOffset) / rules.spacing).rounded(.down))

        let candidates: [Int]
        if let rect {
            candidates = candidateIndices(near: rect, margin: margin, scale: scale, lastIndex: lastIndex, rules: rules)
        } else {
            candidates = Array(0...lastIndex)
        }

        return candidates.compactMap { resolve($0, scale: scale, markers: markers, rules: rules) }
    }

    /// The candidates whose search window overlaps a segment that crosses `rect`.
    /// A placed arrow sits on a segment, so a segment that misses the rect can't
    /// put one in it.
    private func candidateIndices(near rect: CGRect, margin: CGFloat, scale: CGFloat, lastIndex: Int, rules: Rules) -> [Int] {
        let reach = rect.insetBy(dx: -margin / scale, dy: -margin / scale)
        var indices = IndexSet()
        for segment in 0..<(points.count - 1) {
            // Edges rather than `CGRect.intersects`, which misses a segment that runs
            // exactly north–south or east–west: its bounding box has no width.
            let start = points[segment], end = points[segment + 1]
            guard min(start.x, end.x) <= reach.maxX, max(start.x, end.x) >= reach.minX,
                  min(start.y, end.y) <= reach.maxY, max(start.y, end.y) >= reach.minY else { continue }

            let low = distances[segment] * scale - rules.maximumShift - rules.startOffset
            let high = distances[segment + 1] * scale + rules.maximumShift - rules.startOffset
            let first = max(0, Int((low / rules.spacing).rounded(.up)))
            let last = min(lastIndex, Int((high / rules.spacing).rounded(.down)))
            if first <= last {
                indices.insert(integersIn: first...last)
            }
        }
        return Array(indices)
    }

    /// The nearest clear spot to candidate `index`, trying the exact spot first and
    /// then a point further each way, or nil when none is within reach.
    private func resolve(_ index: Int, scale: CGFloat, markers: [CGPoint], rules: Rules) -> Arrow? {
        let target = rules.startOffset + CGFloat(index) * rules.spacing
        let steps = Int(rules.maximumShift.rounded(.down))
        for step in 0...steps {
            for offset in step == 0 ? [CGFloat(0)] : [CGFloat(-step), CGFloat(step)] {
                if let arrow = arrow(index: index, at: target + offset, scale: scale, markers: markers, rules: rules) {
                    return arrow
                }
            }
        }
        return nil
    }

    private func arrow(index: Int, at position: CGFloat, scale: CGFloat, markers: [CGPoint], rules: Rules) -> Arrow? {
        let along = position / scale
        guard along >= 0, along <= distances[distances.count - 1] else { return nil }

        let segment = segmentIndex(containing: along)
        let segmentLength = (distances[segment + 1] - distances[segment]) * scale
        let fromStart = (along - distances[segment]) * scale
        guard segmentLength >= rules.minimumSegmentLength,
              fromStart >= rules.cornerClearance,
              segmentLength - fromStart >= rules.cornerClearance else { return nil }

        let start = points[segment], end = points[segment + 1]
        let fraction = fromStart / segmentLength
        let point = CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction)

        let clearance = rules.markerClearance / scale
        guard markers.allSatisfy({ Self.distance($0, point) >= clearance }) else { return nil }

        return Arrow(index: index, point: point, angle: atan2(end.y - start.y, end.x - start.x))
    }

    /// The last segment starting at or before `along`. A zero-length segment never
    /// wins, because the one after it starts at the same distance.
    private func segmentIndex(containing along: CGFloat) -> Int {
        var low = 0, high = points.count - 2
        while low < high {
            let middle = (low + high + 1) / 2
            if distances[middle] <= along {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return low
    }

    private static func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(rhs.x - lhs.x, rhs.y - lhs.y)
    }
}

/// How a direction chevron and the line under it look.
nonisolated enum RouteArrowStyle {
    /// An open chevron pointing along +x, centered on the line, in screen points.
    static let chevron: [CGPoint] = [
        CGPoint(x: -2.2, y: -3.2),
        CGPoint(x: 1.6, y: 0),
        CGPoint(x: -2.2, y: 3.2)
    ]
    static let strokeWidth: CGFloat = 2
    /// Furthest any part of a stroked chevron reaches from its center.
    static let extent: CGFloat = 5

    /// A line thinner than this has no room for a chevron.
    static let minimumLineWidth: CGFloat = 6

    /// The casing drawn under a line, as wide as the line plus this.
    static let casingExtraWidth: CGFloat = 2

    /// White reads on every route color but the palest; those get near-black.
    static func chevronColor(on routeColor: UIColor) -> UIColor {
        routeColor.wcagContrastRatio(against: .white) < 3 ? UIColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1) : .white
    }

    /// The route color darkened by about 30%, so the line keeps an edge over the
    /// basemap in light mode and dark mode alike.
    static func casingColor(for routeColor: UIColor) -> UIColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard routeColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return routeColor }
        return UIColor(red: red * 0.7, green: green * 0.7, blue: blue * 0.7, alpha: alpha)
    }
}

/// Where stop markers are on the map, for direction arrows to keep clear of.
///
/// Written on the main actor by the layer that owns the line, read by
/// `RouteLineRenderer` from MapKit's drawing threads.
nonisolated final class RouteArrowMarkers: Sendable {
    private let state = Mutex<[CGPoint]>([])

    /// In map points.
    var points: [CGPoint] { state.withLock { $0 } }

    /// Returns whether anything changed, so the caller only redraws when it must.
    @discardableResult
    func update(_ points: [CGPoint]) -> Bool {
        state.withLock { current in
            guard current != points else { return false }
            current = points
            return true
        }
    }

    /// The annotations that draw as stop markers: stops, bookmarked stops, and a
    /// followed trip's stop dots.
    @MainActor
    static func positions(in annotations: [MKAnnotation]) -> [CGPoint] {
        annotations.compactMap { annotation in
            guard annotation is Stop || annotation is Bookmark || annotation is TripStopAnnotation else { return nil }
            let point = MKMapPoint(annotation.coordinate)
            return CGPoint(x: point.x, y: point.y)
        }
    }
}

/// A route line with direction chevrons drawn on it.
///
/// The chevrons belong to the line's renderer rather than being annotations, for
/// two reasons. Overlays always draw under annotations, so the chevrons sit above
/// the line and below the stop markers. And the renderer redraws whenever the zoom
/// changes, which is what lets the spacing be in screen points: MapKit hands each
/// draw its zoom scale.
nonisolated final class RouteLineRenderer: MKPolylineRenderer {
    private let layout: RouteArrowLayout
    private let arrowColor: CGColor
    private let markers: RouteArrowMarkers

    init(polyline: MKPolyline, routeColor: UIColor, markers: RouteArrowMarkers) {
        let mapPoints = UnsafeBufferPointer(start: polyline.points(), count: polyline.pointCount)
        layout = RouteArrowLayout(points: mapPoints.map { CGPoint(x: $0.x, y: $0.y) })
        arrowColor = RouteArrowStyle.chevronColor(on: routeColor).cgColor
        self.markers = markers
        // `init(overlay:)`, the designated initializer: `init(polyline:)` is a convenience
        // that calls back into `init(overlay:)` on the subclass, which this one lacks.
        super.init(overlay: polyline)
    }

    /// Test seam: the arrows a draw at `zoomScale` would place, over the whole line.
    func arrows(zoomScale: MKZoomScale) -> [RouteArrowLayout.Arrow] {
        layout.arrows(scale: zoomScale, avoiding: markers.points)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        super.draw(mapRect, zoomScale: zoomScale, in: context)
        guard lineWidth >= RouteArrowStyle.minimumLineWidth else { return }

        let arrows = layout.arrows(
            scale: zoomScale,
            avoiding: markers.points,
            in: CGRect(x: mapRect.origin.x, y: mapRect.origin.y, width: mapRect.size.width, height: mapRect.size.height),
            margin: RouteArrowStyle.extent
        )
        guard !arrows.isEmpty else { return }

        let path = CGMutablePath()
        for arrow in arrows {
            let center = point(for: MKMapPoint(x: arrow.point.x, y: arrow.point.y))
            let transform = CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: arrow.angle)
                .scaledBy(x: 1 / zoomScale, y: 1 / zoomScale)
            path.addLines(between: RouteArrowStyle.chevron, transform: transform)
        }

        context.saveGState()
        context.addPath(path)
        context.setStrokeColor(arrowColor)
        context.setLineWidth(RouteArrowStyle.strokeWidth / zoomScale)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
        context.restoreGState()
    }
}
