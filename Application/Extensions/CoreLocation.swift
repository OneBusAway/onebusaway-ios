//
//  CoreLocation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 1/12/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import CoreLocation

public extension CLLocationDirection {

    /// Creates an affine transform from the specified rotation, and allows for an
    /// additional rotation value to be applied to it as well in order to accomodate
    /// different coordinate systems.
    ///
    /// - Parameter rotation: An additional, optional rotation.
    /// - Returns: The equivalent CGAffineTransform
    public func affineTransform(rotatedBy rotation: CGFloat) -> CGAffineTransform {
        return CGAffineTransform(rotationAngle: CGFloat(radians)).rotated(by: rotation)
    }

    /// Converts this value to radians.
    public var radians: Double {
        return Measurement(value: self, unit: UnitAngle.degrees).converted(to: UnitAngle.radians).value
    }
}
