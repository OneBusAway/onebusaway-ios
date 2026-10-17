//
//  MapViewController+VerticalBar.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit

/// Where the map's controls live: the floating hover bar, or — when the system
/// presents bars vertically on the side of the display — the navigation
/// controller's toolbar, which the system stacks above the tab bar.
extension MapViewController {
    var presentsBarsVertically: Bool {
        traitCollection.presentsBarsVertically
    }

    func observeVerticalBarEdge() {
        registerForVerticalBarChanges { [weak self] in
            self?.updateControlsPlacement(animated: true)
        }
    }

    /// Moves the controls between the hover bar and the system toolbar.
    func updateControlsPlacement(animated: Bool) {
        let vertical = presentsBarsVertically
        toolbar.isHidden = vertical
        setToolbarItems(vertical ? verticalBarItems.items : nil, animated: animated)

        // Only the visible page owns the navigation controller's toolbar.
        guard let navigationController, navigationController.topViewController === self else { return }
        navigationController.setToolbarHidden(!vertical, animated: animated)
    }
}
