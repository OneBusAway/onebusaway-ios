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

    /// Hides the separator after the last row added to the receiver. Does nothing if the stack view doesn't have any rows in it.
    func hideLastRowSeparator() {
        guard let lastRow = lastRow else {
            return
        }

        removeRow(lastRow)
        addRow(lastRow, hideSeparator: true)
    }
}

protocol AloeStackTableBuilder {
    var stackView: AloeStackView { get }

    func addGroupedTableHeaderToStack(headerText: String)
    func addGroupedTableRowToStack<T>(_ row: T, isLastRow: Bool, tapHandler: ((T) -> Void)?) where T: UIView
}

extension AloeStackTableBuilder where Self: UIViewController {

    func addTableHeaderToStack(headerText: String, backgroundColor: UIColor? = nil, textColor: UIColor? = nil) {
        let header = TableHeaderView.autolayoutNew()
        header.text = headerText
        if let textColor = textColor {
            header.textColor = textColor
        }
        header.backgroundColor = backgroundColor ?? ThemeColors.shared.secondaryBackgroundColor
        header.directionalLayoutMargins = NSDirectionalEdgeInsets(top: ThemeMetrics.compactPadding, leading: 10, bottom: ThemeMetrics.compactPadding, trailing: 10)
        stackView.addRow(header, hideSeparator: true)

        stackView.setInset(forRow: header, inset: .zero)
    }

    func addGroupedTableHeaderToStack(headerText: String) {
        let header = TableHeaderView.autolayoutNew()
        header.text = headerText
        header.directionalLayoutMargins = NSDirectionalEdgeInsets(top: ThemeMetrics.controllerMargin, leading: ThemeMetrics.controllerMargin, bottom: ThemeMetrics.compactPadding, trailing: ThemeMetrics.controllerMargin)

        stackView.addRow(header, hideSeparator: false)

        stackView.setInset(forRow: header, inset: .zero)
        stackView.setSeparatorInset(forRow: header, inset: .zero)
    }

    func addGroupedTableRowToStack<T>(_ row: T, isLastRow: Bool = false, tapHandler: ((T) -> Void)? = nil) where T: UIView {
        row.backgroundColor = ThemeColors.shared.groupedTableRowBackground
        row.layoutMargins = ThemeMetrics.groupedRowLayoutMargins

        stackView.addRow(row, hideSeparator: false)

        stackView.setInset(forRow: row, inset: .zero)

        if isLastRow {
            stackView.setSeparatorInset(forRow: row, inset: .zero)
        }

        if let tapHandler = tapHandler {
            stackView.setTapHandler(forRow: row, handler: tapHandler)
        }
    }
}
