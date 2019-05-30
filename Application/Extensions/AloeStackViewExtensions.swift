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

    /// Extension: Add a row, plus specify separator visibility and insets in a single call.
    ///
    /// - Parameters:
    ///   - view: The view to add to the stack view
    ///   - hideSeparator: Hide the row separator or not.
    ///   - insets: Optionally set custom edge insets for this row. Leave this as `nil` to accept defaults.
    func addRow(_ view: UIView, hideSeparator: Bool, insets: UIEdgeInsets? = nil) {
        addRow(view)
        if hideSeparator {
            self.hideSeparator(forRow: view)
        }

        if let insets = insets {
            self.setInset(forRow: view, inset: insets)
        }
    }
}
