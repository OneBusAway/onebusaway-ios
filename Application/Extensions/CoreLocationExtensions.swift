//
//  CoreLocation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 1/12/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import CoreLocation

extension CLAuthorizationStatus: LosslessStringConvertible {
    public init?(_ description: String) { nil }

    public var description: String {
        switch self {
        case .authorizedAlways: return "authorizedAlways"
        case .authorizedWhenInUse: return "authorizedWhenInUse"
        case .denied: return "denied"
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        @unknown default:
            return "unknown value: \(self)"
        }
    }
}

public extension CLLocationDirection {

    /// Creates an affine transform from the specified rotation, and allows for an
    /// additional rotation value to be applied to it as well in order to accomodate
    /// different coordinate systems.
    ///
    /// - Parameter rotation: An additional, optional rotation expressed in radians.
    /// - Returns: The equivalent CGAffineTransform
    func affineTransform(rotatedBy rotation: CGFloat) -> CGAffineTransform {
        return CGAffineTransform(rotationAngle: CGFloat(radians)).rotated(by: rotation)
    }

    /// Converts this value to radians.
    var radians: Double {
        return Measurement(value: self, unit: UnitAngle.degrees).converted(to: UnitAngle.radians).value
    }
}

public extension CLLocationCoordinate2D {

    /// Calculates the distance from the receiver to `coordinate`.
    ///
    /// - Parameter coordinate: The location to which distance will be calculated.
    /// - Returns: The distance between `self` and `coordinate`.
    func distance(from coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        let start = CLLocation(latitude: latitude, longitude: longitude)
        let end = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return start.distance(from: end)
    }
}

public extension CLCircularRegion {

    /// Creates a reasonably accurate circular region from the specified map rect.
    ///
    /// - Parameter mapRect: The map rect that will be translated into a circular region.
    convenience init(mapRect: MKMapRect) {
        let northeast = MKMapPoint(x: mapRect.maxX, y: mapRect.minY).coordinate
        let southwest = MKMapPoint(x: mapRect.minX, y: mapRect.maxY).coordinate
        let radius = northeast.distance(from: southwest) / 2.0
        let center = MKMapPoint(x: mapRect.midX, y: mapRect.midY).coordinate

        self.init(center: center, radius: radius, identifier: "MapRectRegion")
    }
}
