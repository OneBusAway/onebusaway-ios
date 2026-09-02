//
//  PolylineDirectionArrows.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import MapKit
import OBAKitCore
import UIKit

nonisolated struct PolylineArrowPlacement: Equatable {
    let coordinate: CLLocationCoordinate2D
    let headingDegrees: CLLocationDirection

    static func == (lhs: PolylineArrowPlacement, rhs: PolylineArrowPlacement) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.headingDegrees == rhs.headingDegrees
    }
}

nonisolated enum PolylineDirectionArrows {
    private static let maximumPlacementCount = 24

    private struct Segment {
        let start: MKMapPoint
        let end: MKMapPoint
        let startDistance: CLLocationDistance
        let length: CLLocationDistance

        var endDistance: CLLocationDistance { startDistance + length }

        func mapPoint(at distance: CLLocationDistance) -> MKMapPoint {
            let fraction = (distance - startDistance) / length
            return MKMapPoint(
                x: start.x + (end.x - start.x) * fraction,
                y: start.y + (end.y - start.y) * fraction
            )
        }
    }

    /// Places arrows along `coordinates` every `spacing` meters, beginning one
    /// full spacing from the first vertex.
    static func placements(
        along coordinates: [CLLocationCoordinate2D],
        spacing: CLLocationDistance = 500
    ) -> [PolylineArrowPlacement] {
        guard coordinates.count >= 2, spacing.isFinite, spacing > 0 else { return [] }

        var segments: [Segment] = []
        var totalDistance: CLLocationDistance = 0
        for (startCoordinate, endCoordinate) in zip(coordinates, coordinates.dropFirst()) {
            let length = startCoordinate.distance(from: endCoordinate)
            guard length.isFinite, length > 0 else { continue }

            segments.append(Segment(
                start: MKMapPoint(startCoordinate),
                end: MKMapPoint(endCoordinate),
                startDistance: totalDistance,
                length: length
            ))
            totalDistance += length
        }

        guard !segments.isEmpty else { return [] }

        // Leave half a spacing after the final arrow. This avoids a chevron
        // crowding the terminal stop or vehicle at the end of a short remainder.
        let finalPlacementDistance = totalDistance - spacing / 2
        guard finalPlacementDistance >= spacing else { return [] }

        var placements: [PolylineArrowPlacement] = []
        var distance = spacing
        while distance <= finalPlacementDistance, placements.count < maximumPlacementCount {
            guard let point = mapPoint(at: distance, in: segments) else { break }

            // A short sample on each side follows the local tangent through a
            // vertex instead of inheriting only the segment before or after it.
            let previous = mapPoint(at: max(0, distance - 1), in: segments) ?? point
            let next = mapPoint(at: min(totalDistance, distance + 1), in: segments) ?? point
            placements.append(PolylineArrowPlacement(
                coordinate: point.coordinate,
                headingDegrees: heading(from: previous, to: next)
            ))
            distance += spacing
        }

        return placements
    }

    /// `chevron.up` points north at identity. Compass heading is clockwise from
    /// north; UIKit view space has y down, so a positive `CGAffineTransform`
    /// rotation is clockwise too. Do not negate — that mirrored east/west.
    static func viewTransform(headingDegrees: CLLocationDirection) -> CGAffineTransform {
        CGAffineTransform(rotationAngle: CGFloat(headingDegrees.radians))
    }

    private static func mapPoint(at distance: CLLocationDistance, in segments: [Segment]) -> MKMapPoint? {
        guard let segment = segments.first(where: { distance <= $0.endDistance }) ?? segments.last else {
            return nil
        }
        return segment.mapPoint(at: min(max(distance, segment.startDistance), segment.endDistance))
    }

    /// MapKit's x axis points east and y axis points south. Swapping the usual
    /// atan2 arguments and negating y yields compass degrees: north = 0, east = 90.
    private static func heading(from start: MKMapPoint, to end: MKMapPoint) -> CLLocationDirection {
        let degrees = atan2(end.x - start.x, -(end.y - start.y)) * 180 / .pi
        return degrees >= 0 ? degrees : degrees + 360
    }
}

final class PolylineArrowAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let headingDegrees: CLLocationDirection
    let tintColor: UIColor
    let routeID: RouteID?
    var alpha: CGFloat

    init(
        placement: PolylineArrowPlacement,
        tintColor: UIColor,
        routeID: RouteID? = nil,
        alpha: CGFloat = 1
    ) {
        coordinate = placement.coordinate
        headingDegrees = placement.headingDegrees
        self.tintColor = tintColor
        self.routeID = routeID
        self.alpha = alpha
        super.init()
    }
}

final class PolylineArrowAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "PolylineArrowAnnotationView"

    override var annotation: MKAnnotation? {
        didSet { applyAnnotation() }
    }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = false
        isEnabled = false
        displayPriority = .defaultLow
        collisionMode = .none
        applyAnnotation()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func applyAnnotation() {
        guard let arrow = annotation as? PolylineArrowAnnotation else { return }

        let configuration = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        image = UIImage(systemName: "chevron.up", withConfiguration: configuration)?
            .withTintColor(arrow.tintColor, renderingMode: .alwaysOriginal)
        transform = PolylineDirectionArrows.viewTransform(headingDegrees: arrow.headingDegrees)
        alpha = arrow.alpha
        centerOffset = .zero
    }
}
