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

    /// In screen points.
    enum Rules {
        /// From the start of the line to the first candidate.
        static let startOffset: CGFloat = 30
        static let spacing: CGFloat = 64
        /// How far a candidate may move, either way, to find a clear spot.
        static let maximumShift: CGFloat = 8
        static let minimumSegmentLength: CGFloat = 40
        /// From either end of the segment.
        static let cornerClearance: CGFloat = 12
        /// From the center of any stop marker.
        static let markerClearance: CGFloat = 22
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
    ///   - rect: When set, only the arrows that land in this rect, in the line's
    ///     units, placed as they would be for the whole line.
    func arrows(scale: CGFloat, avoiding markers: [CGPoint] = [], in rect: CGRect? = nil) -> [Arrow] {
        guard points.count >= 2, scale.isFinite, scale > 0 else { return [] }

        let length = (distances.last ?? 0) * scale
        guard length >= Rules.startOffset else { return [] }
        let lastIndex = Int(((length - Rules.startOffset) / Rules.spacing).rounded(.down))

        guard let rect else {
            return (0...lastIndex).compactMap { resolve($0, scale: scale, markers: markers) }
        }

        // Only a marker this close can decide where an arrow in the rect goes. A spot
        // tried outside the rect is at most two shifts from one the whole line would
        // place inside it, and must be judged against the same markers.
        let reach = (2 * Rules.maximumShift + Rules.markerClearance) / scale
        let nearby = rect.insetBy(dx: -reach, dy: -reach)
        let markers = markers.filter { nearby.contains($0) }
        return candidateIndices(near: rect, scale: scale, lastIndex: lastIndex)
            .compactMap { resolve($0, scale: scale, markers: markers) }
            // A candidate from a segment that crosses the rect can still land
            // outside it, judged against markers filtered for the rect.
            .filter { rect.contains($0.point) }
    }

    /// The candidates whose search window overlaps a segment that crosses `rect`.
    /// A placed arrow sits on a segment, so a segment that misses the rect can't
    /// put one in it.
    private func candidateIndices(near reach: CGRect, scale: CGFloat, lastIndex: Int) -> IndexSet {
        var indices = IndexSet()
        for segment in 0..<(points.count - 1) {
            // Edges rather than `CGRect.intersects`, which misses a segment that runs
            // exactly north–south or east–west: its bounding box has no width.
            let start = points[segment], end = points[segment + 1]
            guard min(start.x, end.x) <= reach.maxX, max(start.x, end.x) >= reach.minX,
                  min(start.y, end.y) <= reach.maxY, max(start.y, end.y) >= reach.minY else { continue }

            let low = distances[segment] * scale - Rules.maximumShift - Rules.startOffset
            let high = distances[segment + 1] * scale + Rules.maximumShift - Rules.startOffset
            let first = max(0, Int((low / Rules.spacing).rounded(.up)))
            let last = min(lastIndex, Int((high / Rules.spacing).rounded(.down)))
            if first <= last {
                indices.insert(integersIn: first...last)
            }
        }
        return indices
    }

    /// The nearest clear spot to candidate `index`, trying the exact spot first and
    /// then a point further each way, or nil when none is within reach.
    private func resolve(_ index: Int, scale: CGFloat, markers: [CGPoint]) -> Arrow? {
        let target = Rules.startOffset + CGFloat(index) * Rules.spacing
        // 0, -1, +1, -2, +2, …: the nearest spot wins, and backward breaks a tie.
        for attempt in 0...(2 * Int(Rules.maximumShift)) {
            let offset = CGFloat((attempt + 1) / 2) * (attempt.isMultiple(of: 2) ? 1 : -1)
            if let arrow = arrow(index: index, at: target + offset, scale: scale, markers: markers) {
                return arrow
            }
        }
        return nil
    }

    private func arrow(index: Int, at position: CGFloat, scale: CGFloat, markers: [CGPoint]) -> Arrow? {
        let along = position / scale
        guard along >= 0, along <= distances[distances.count - 1] else { return nil }

        let segment = segmentIndex(containing: along)
        let segmentLength = (distances[segment + 1] - distances[segment]) * scale
        let fromStart = (along - distances[segment]) * scale
        guard segmentLength >= Rules.minimumSegmentLength,
              fromStart >= Rules.cornerClearance,
              segmentLength - fromStart >= Rules.cornerClearance else { return nil }

        let start = points[segment], end = points[segment + 1]
        let fraction = fromStart / segmentLength
        let point = CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction)

        let clearance = Rules.markerClearance / scale
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
        routeColor.wcagContrastRatio(against: .white) < 3 ? nearBlack : .white
    }

    private static let nearBlack = UIColor(hex: "1C1C1E") ?? .black

    /// The route color darkened by about 30%, so the line keeps an edge over the
    /// basemap in light mode and dark mode alike.
    static func casingColor(for routeColor: UIColor) -> UIColor {
        routeColor.blended(with: .black, amount: 0.3)
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
    /// Order doesn't count: `MKMapView.annotations` promises none.
    @discardableResult
    func update(_ points: [CGPoint]) -> Bool {
        let points = points.sorted { ($0.x, $0.y) < ($1.x, $1.y) }
        return state.withLock { current in
            guard current != points else { return false }
            current = points
            return true
        }
    }

    /// Reads the stop markers on `mapView` again, and redraws any of `overlays`
    /// that carry arrows if the markers moved.
    @MainActor
    func refresh(from mapView: MKMapView, redrawing overlays: [MKOverlay]) {
        guard update(Self.positions(in: mapView.annotations)) else { return }
        for overlay in overlays {
            (mapView.renderer(for: overlay) as? RouteLineRenderer)?.setNeedsDisplay()
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

        // Grown by a chevron's reach, so one centered just outside the tile still
        // draws its part inside it.
        let reach = RouteArrowStyle.extent / zoomScale
        let tile = CGRect(x: mapRect.origin.x, y: mapRect.origin.y, width: mapRect.size.width, height: mapRect.size.height)
        let arrows = layout.arrows(scale: zoomScale, avoiding: markers.points, in: tile.insetBy(dx: -reach, dy: -reach))
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
