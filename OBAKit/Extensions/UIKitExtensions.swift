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
import SwiftUI

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

// MARK: - UIView

extension UIView {

    /// Breadth-first search for the nearest descendant scroll view, including the receiver itself.
    ///
    /// SwiftUI exposes no public handle on the `UICollectionView` backing a `List`, but
    /// `FloatingPanel` needs one to drive scroll-to-expand. The search is breadth-first so it
    /// finds the list's own scroll view rather than one nested inside a row.
    ///
    /// - Important: `nil` means "SwiftUI's view hierarchy no longer has the shape we expect,"
    ///   which is possible on any OS update. Callers must degrade gracefully — for the stop
    ///   sheet that means grabber-only dragging — rather than treating it as a failure.
    func nearestDescendantScrollView() -> UIScrollView? {
        var queue: [UIView] = [self]
        var index = 0

        while index < queue.count {
            let view = queue[index]
            index += 1

            if let scrollView = view as? UIScrollView {
                return scrollView
            }

            queue.append(contentsOf: view.subviews)
        }

        return nil
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
