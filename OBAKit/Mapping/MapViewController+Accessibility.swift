//
//  MapViewController+Accessibility.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import FloatingPanel
import UIKit

extension MapViewController {

    /// The toolbar's buttons are 42pt icons that don't grow with Dynamic Type, so
    /// at the accessibility sizes a long press shows them in the large content
    /// viewer, as the tab bar does.
    ///
    /// The interaction has no delegate: the default lift action sends the button
    /// its `touchUpInside`, and `MapViewController`'s delegate method is written
    /// for the status pill alone.
    func configureLargeContentViewer(on toolbar: UIView, buttons: [UIButton]) {
        for button in buttons {
            button.showsLargeContentViewer = true
            button.scalesLargeContentImage = true
            if button.largeContentTitle == nil {
                button.largeContentTitle = button.accessibilityLabel
            }
        }
        toolbar.addInteraction(UILargeContentViewerInteraction())
    }

    /// Adds a semi-modal panel over the map and moves VoiceOver into it. Without
    /// the screen change, focus stays on whatever opened the panel — often a pin
    /// that is now underneath it — and nothing says that a card appeared.
    func addSemiModalPanel(_ panel: FloatingPanelController) {
        panel.addPanel(toParent: self)
        UIAccessibility.post(notification: .screenChanged, argument: panel.contentViewController?.view)
    }
}
