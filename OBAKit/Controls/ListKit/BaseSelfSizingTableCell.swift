//
//  BaseSelfSizingTableCell.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 3/29/20.
//

import UIKit
import IGListKit
import OBAKitCore

/// A self-sizing table-style collection cell with a separator and support for highlighting on touch.
///
/// Use this as the base class for all of your collection cells that don't require support for swiping.
class BaseSelfSizingTableCell: SelfSizingCollectionCell, Separated {
    var separator = tableCellSeparatorLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.backgroundColor = normalBackgroundColor
        contentView.layer.addSublayer(separator)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutSeparator()
    }

    var normalBackgroundColor: UIColor? = ThemeColors.shared.systemBackground {
        didSet {
            contentView.backgroundColor = normalBackgroundColor
        }
    }

    var highlightedBackgroundColor = ThemeColors.shared.systemBackground

    override var isHighlighted: Bool {
        didSet {
            contentView.backgroundColor = isHighlighted ? highlightedBackgroundColor : normalBackgroundColor
        }
    }
}
