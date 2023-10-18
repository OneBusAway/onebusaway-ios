//
//  UIKitExtensions.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

// MARK: - UIButton

public extension UIButton {

    /// A button with a right-pointing arrow. Use this on map annotation view callouts.
    class var chevronButton: UIButton {
        let button = UIButton(type: .detailDisclosure)
        button.setImage(Icons.chevron, for: .normal)
        return button
    }

    class func buildCloseButton() -> UIButton {
        var configuration = UIButton.Configuration.borderless()
        configuration.image = Icons.closeCircle
        configuration.contentInsets = NSDirectionalEdgeInsets(top: ThemeMetrics.padding, leading: ThemeMetrics.padding, bottom: ThemeMetrics.padding, trailing: ThemeMetrics.padding)

        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .vertical)
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 40.0),
            button.widthAnchor.constraint(equalToConstant: 40.0)
        ])

        button.accessibilityLabel = Strings.close

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

// MARK: - UIApplication

extension UIApplication {

    /// Extracts the key window from the receiver's connected scenes.
    ///
    /// A replacement for the deprecated `UIApplication.windows` property.
    var keyWindowFromScene: UIWindow? {
        activeWindows.first(where: \.isKeyWindow)
    }

    var activeWindows: [UIWindow] {
        // Get connected scenes
        let windows = self.connectedScenes
            // Keep only active scenes, onscreen and visible to the user
            .filter { $0.activationState == .foregroundActive }
            // Keep only the first `UIWindowScene`
            .first(where: { $0 is UIWindowScene })
            // Get its associated windows
            .flatMap({ $0 as? UIWindowScene })?.windows

        return windows ?? []
    }

}
