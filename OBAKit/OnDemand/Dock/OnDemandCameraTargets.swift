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
enum OnDemandCameraTargets {
    static let minimumZoomOutHeight = 2 * OnDemandZoomLevel.streetMaxVisibleHeight
    static let maximumZoomOutHeight = 0.9 * OnDemandZoomLevel.regionMaxVisibleHeight
    static let paddingFraction = 0.2

    static func zoomOutRect(areas: [ServiceArea], probePoint: CLLocationCoordinate2D) -> MKMapRect? {
        let union = areas.map(mapRect).reduce(MKMapRect.null) { $0.union($1) }
        guard !union.isNull, union.height > 0, union.width > 0 else { return nil }

        let padded = union.insetBy(dx: -union.width * paddingFraction, dy: -union.height * paddingFraction)
        let clampedHeight = min(max(padded.height, minimumZoomOutHeight), maximumZoomOutHeight)
        guard clampedHeight != padded.height else { return padded }

        let scale = clampedHeight / padded.height
        let centre = MKMapPoint(probePoint)
        let width = padded.width * scale
        return MKMapRect(x: centre.x - width / 2, y: centre.y - clampedHeight / 2, width: width, height: clampedHeight)
    }

    private static func mapRect(of area: ServiceArea) -> MKMapRect {
        let topLeft = MKMapPoint(CLLocationCoordinate2D(latitude: area.bbox.maxLatitude, longitude: area.bbox.minLongitude))
        let bottomRight = MKMapPoint(CLLocationCoordinate2D(latitude: area.bbox.minLatitude, longitude: area.bbox.maxLongitude))
        return MKMapRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y)
    }
}
