/**
 *  BulletinBoard
 *  Copyright (c) 2017 - present Alexis Aubry. Licensed under the MIT license.
 */

import UIKit

/**
 * Represents a spacing value.
 */

@objc class BLTNSpacing: NSObject {
    let rawValue: CGFloat

    init(rawValue: CGFloat) {
        self.rawValue = rawValue
    }

    /// A custom spacing.
    /// - parameter value: The spacing to apply.
    @objc class func custom(_ value: CGFloat) -> BLTNSpacing {
        return BLTNSpacing(rawValue: value)
    }

    /// No spacing is applied. (value: 0)
    /// - note: If you use this spacing, corner radii will be ignored.
    @objc class var none: BLTNSpacing {
        return BLTNSpacing(rawValue: 0)
    }

     /// A compact spacing. (value: 6)
    @objc class var compact: BLTNSpacing {
        return BLTNSpacing(rawValue: 6)
    }

    /// The standard spacing. (value: 12)
    @objc class var regular: BLTNSpacing {
        return BLTNSpacing(rawValue: 12)
    }
}
