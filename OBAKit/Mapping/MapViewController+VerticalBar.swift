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
    /// Whether the system puts bars in a vertical column beside this view, as on
    /// iPhone Duo. `verticalBarEdge` reports the system's preferred edge whether or
    /// not a bar is showing, so deciding from it doesn't depend on our own toolbar.
    var presentsBarsVertically: Bool {
        guard #available(iOS 27.1, *) else { return false }
        return traitCollection.verticalBarEdge != .unspecified
    }

    func observeVerticalBarEdge() {
        guard #available(iOS 27.1, *) else { return }
        registerForTraitChanges(UITraitCollection.systemTraitsAffectingVerticalBarEdge) { (self: Self, _) in
            self.updateControlsPlacement(animated: true)
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
