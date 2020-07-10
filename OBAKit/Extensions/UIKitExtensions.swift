//
//  UIKitExtensions.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 4/11/20.
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
    var isAccessibility: Bool {
        return traitCollection.preferredContentSizeCategory.isAccessibilityCategory
    }
}
