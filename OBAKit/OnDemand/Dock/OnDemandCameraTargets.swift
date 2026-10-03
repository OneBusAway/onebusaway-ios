//
//  OnDemandCameraTargets.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import MapKit
import OBAKitCore

/// Spec 3.4 thumbnail tap: fit the union bbox of the stack with 20 % padding,
/// never smaller than twice the street gate, never larger than 0.9 × the
/// outer window, centred on the probe point when clamped.
///
/// `setVisibleMapRect` grows a rect to the map's aspect ratio, which on a tall
/// phone can push a wide zone's height past the window, so the target takes
/// the viewport's aspect before the clamp and the map adds nothing to it.
enum OnDemandCameraTargets {
    static let minimumZoomOutHeight = 2 * OnDemandZoomLevel.streetMaxVisibleHeight
    static let maximumZoomOutHeight = 0.9 * OnDemandZoomLevel.regionMaxVisibleHeight
    static let paddingFraction = 0.2

    /// - Parameter viewportSize: the map view's size; an empty size keeps the
    ///   zones' own aspect ratio.
    static func zoomOutRect(areas: [ServiceArea], probePoint: CLLocationCoordinate2D, viewportSize: CGSize) -> MKMapRect? {
        let union = areas.map(mapRect).reduce(MKMapRect.null) { $0.union($1) }
        guard !union.isNull, union.height > 0, union.width > 0 else { return nil }

        let padded = union.insetBy(dx: -union.width * paddingFraction, dy: -union.height * paddingFraction)
        let fitted = fit(padded, toAspectOf: viewportSize)
        let clampedHeight = min(max(fitted.height, minimumZoomOutHeight), maximumZoomOutHeight)
        guard clampedHeight != fitted.height else { return fitted }

        let scale = clampedHeight / fitted.height
        let centre = MKMapPoint(probePoint)
        let width = fitted.width * scale
        return MKMapRect(x: centre.x - width / 2, y: centre.y - clampedHeight / 2, width: width, height: clampedHeight)
    }

    /// Grows `rect` about its centre to the viewport's width-to-height ratio,
    /// as `MKMapView` would.
    private static func fit(_ rect: MKMapRect, toAspectOf viewportSize: CGSize) -> MKMapRect {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return rect }
        let aspect = Double(viewportSize.width / viewportSize.height)
        let width = max(rect.width, rect.height * aspect)
        let height = max(rect.height, rect.width / aspect)
        return MKMapRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
    }

    private static func mapRect(of area: ServiceArea) -> MKMapRect {
        let topLeft = MKMapPoint(CLLocationCoordinate2D(latitude: area.bbox.maxLatitude, longitude: area.bbox.minLongitude))
        let bottomRight = MKMapPoint(CLLocationCoordinate2D(latitude: area.bbox.minLatitude, longitude: area.bbox.maxLongitude))
        return MKMapRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y)
    }
}
