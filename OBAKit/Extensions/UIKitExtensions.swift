//
//  UIKitExtensions.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit

// MARK: - UIButton

public extension UIButton {

    /// A button with a right-pointing arrow. Use this on map annotation view callouts.
    class var chevronButton: UIButton {
        let button = UIButton(type: .detailDisclosure)
        button.setImage(Icons.chevron, for: .normal)
        return button
    }
}

// MARK: - UITraitEnvironment Accessibility
extension UITraitEnvironment {
    /// For OneBusAway, `isAccessibility` is anything equal to or larger than `.extraLarge`.
    var isAccessibility: Bool {
        let contentSize = traitCollection.preferredContentSizeCategory
        return contentSize >= .extraLarge
    }
}
