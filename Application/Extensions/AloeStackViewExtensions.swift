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

    /// Configures a new `AloeStackView` to work with Auto Layout.
    /// - Parameter backgroundColor: Optional. Background color for the stack.
    class func autolayoutNew(backgroundColor: UIColor?) -> AloeStackView {
        let stack = AloeStackView()
        stack.backgroundColor = backgroundColor
        stack.rowInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.alwaysBounceVertical = true
        return stack
    }

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

protocol AloeStackTableBuilder {
    var stackView: AloeStackView { get }
    var theme: Theme { get }

    func addTableHeaderToStack(headerText: String)
    func addGroupedTableRowToStack(_ row: UIView, isLastRow: Bool)
}

extension AloeStackTableBuilder where Self: UIViewController {

    func addTableHeaderToStack(headerText: String) {
        let header = TableHeaderView.autolayoutNew()
        header.textLabel.text = headerText
        stackView.addRow(header, hideSeparator: false)
        stackView.setSeparatorInset(forRow: header, inset: .zero)
    }

    func addGroupedTableRowToStack(_ row: UIView, isLastRow: Bool = false) {
        stackView.addRow(row, hideSeparator: false)
        stackView.setBackgroundColor(forRow: row, color: theme.colors.groupedTableRowBackground)

        if isLastRow {
            stackView.setSeparatorInset(forRow: row, inset: .zero)
        }
    }
}
