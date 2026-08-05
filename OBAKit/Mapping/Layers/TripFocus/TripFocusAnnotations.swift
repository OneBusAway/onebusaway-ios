//
//  TripFocusAnnotations.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OBAKitCore
import UIKit

/// One half of a trip's shape — travelled or remaining, casing or core.
///
/// Carries its own identity for the same reason `RouteShapeOverlay` does: the
/// renderer is handed an overlay and nothing else, and a side table keyed by
/// object identity is a leak waiting to happen.
final class TripShapeOverlay: MKPolyline {
    /// Matches the isolation of the nonisolated `MKPolyline` initializer it
    /// overrides — the pattern `RouteShapeOverlay` and `VehicleAnnotation` use.
    nonisolated override init() {
        super.init()
    }

    /// Behind the vehicle. Drawn gray, so the rider can see at a glance how much
    /// of the trip is already gone.
    var isSpent: Bool = false
    /// The white line drawn underneath the colored one, which is what keeps a
    /// route-colored shape legible over the basemap.
    var isCasing: Bool = false

    static func make(coordinates: [CLLocationCoordinate2D], isSpent: Bool, isCasing: Bool) -> TripShapeOverlay {
        var coordinates = coordinates
        let overlay = TripShapeOverlay(coordinates: &coordinates, count: coordinates.count)
        overlay.isSpent = isSpent
        overlay.isCasing = isCasing
        return overlay
    }
}

/// A stop on the focused trip.
final class TripStopAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let isPassed: Bool
    let isUserStop: Bool
    let isTerminal: Bool
    let routeColor: UIColor

    init(row: TripStopListModel.Row, coordinate: CLLocationCoordinate2D, routeColor: UIColor) {
        self.coordinate = coordinate
        self.title = row.name
        self.isPassed = row.isPassed && !row.isVehicleHere
        self.isUserStop = row.isUserStop
        self.isTerminal = row.isTerminal
        self.routeColor = routeColor
        super.init()
    }
}

/// The ring dots strung along the focused trip.
///
/// Drawn rather than composed from subviews: there is one of these per stop and a
/// long trip runs to sixty-odd, so each one being a single cached image keeps the
/// map's annotation churn cheap as the rider pans.
final class TripStopAnnotationView: MKAnnotationView {

    static let reuseIdentifier = "TripStopAnnotationView"

    override var annotation: MKAnnotation? {
        didSet { applyAnnotation() }
    }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = true
        applyAnnotation()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func applyAnnotation() {
        guard let stop = annotation as? TripStopAnnotation else { return }

        let diameter = Self.diameter(for: stop)
        image = Self.dot(
            diameter: diameter,
            fill: stop.isPassed ? .systemGray3 : .secondarySystemGroupedBackground,
            stroke: stop.isPassed ? .systemGray3 : stop.routeColor,
            isFilled: stop.isUserStop
        )
        // Terminals and the rider's own stop sit above the ordinary dots they
        // would otherwise be hidden behind where a route doubles back.
        displayPriority = stop.isUserStop || stop.isTerminal ? .required : .defaultLow
        centerOffset = .zero
    }

    private static func diameter(for stop: TripStopAnnotation) -> CGFloat {
        if stop.isUserStop { return 16 }
        if stop.isTerminal { return 14 }
        return 10
    }

    private static func dot(diameter: CGFloat, fill: UIColor, stroke: UIColor, isFilled: Bool) -> UIImage {
        let lineWidth: CGFloat = 2.5
        let size = CGSize(width: diameter + lineWidth, height: diameter + lineWidth)

        return UIGraphicsImageRenderer(size: size).image { context in
            let rect = CGRect(
                x: lineWidth / 2,
                y: lineWidth / 2,
                width: diameter,
                height: diameter
            )
            let path = UIBezierPath(ovalIn: rect)
            (isFilled ? stroke : fill).setFill()
            path.fill()
            stroke.setStroke()
            path.lineWidth = lineWidth
            path.stroke()
            _ = context
        }
    }
}
