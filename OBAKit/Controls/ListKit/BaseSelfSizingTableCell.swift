//
//  BaseSelfSizingTableCell.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import IGListKit
import OBAKitCore

/// A self-sizing table-style collection cell with a separator and support for highlighting on touch.
///
/// Use this as the base class for all of your collection cells that don't require support for swiping.
class BaseSelfSizingTableCell: SelfSizingCollectionCell, Separated {
    var separator = tableCellSeparatorLayer()
    var shouldHighlightOnTap: Bool = true

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

    var highlightedBackgroundColor = ThemeColors.shared.highlightedBackgroundColor

    override var isHighlighted: Bool {
        didSet {
            guard shouldHighlightOnTap else { return }
            contentView.backgroundColor = isHighlighted ? highlightedBackgroundColor : normalBackgroundColor
        }
    }
}
