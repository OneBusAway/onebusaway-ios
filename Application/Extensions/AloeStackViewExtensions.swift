//
//  AloeStackViewExtensions.swift
//  OBANext
//
//  Created by Aaron Brethorst on 12/30/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit
import AloeStackView

public extension AloeStackView {

    /// Extension: Add a row and specify whether or not to hide the separator in a single call.
    ///
    /// - Parameters:
    ///   - view: The view to add to the stack view
    ///   - hideSeparator: Hide the row separator or not.
    func addRow(_ view: UIView, hideSeparator: Bool) {
        addRow(view)
        if hideSeparator {
            self.hideSeparator(forRow: view)
        }
    }
}
