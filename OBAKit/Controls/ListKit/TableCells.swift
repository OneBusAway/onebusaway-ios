//
//  TableCells.swift
//  OBANext
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import IGListKit
import SwipeCellKit
import OBAKitCore

// MARK: - TableRowCell

class TableRowCell: SwipeCollectionViewCell, SelfSizing, Separated {
    fileprivate let kUseDebugColors = false

    fileprivate var tableRowView: TableRowView! {
        didSet {
            if kUseDebugColors {
                tableRowView.backgroundColor = .green
            }

            contentView.addSubview(tableRowView)
            NSLayoutConstraint.activate([
                tableRowView.leadingAnchor.constraint(equalTo: contentView.readableContentGuide.leadingAnchor),
                tableRowView.trailingAnchor.constraint(equalTo: contentView.readableContentGuide.trailingAnchor),
                tableRowView.topAnchor.constraint(equalTo: contentView.topAnchor),
                tableRowView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                tableRowView.heightAnchor.constraint(greaterThanOrEqualToConstant: 40.0)
            ])

            self.accessibilityElements = [tableRowView!]
        }
    }

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)

        fixiOS13AutoLayoutBug()

        contentView.layer.addSublayer(separator)

        if kUseDebugColors {
            backgroundColor = .red
            contentView.backgroundColor = .magenta
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Data

    var data: TableRowData? {
        get { return tableRowView.data }
        set { tableRowView.data = newValue }
    }

    // MARK: - Style

    public var style: CollectionController.TableCollectionStyle = .plain {
        didSet {
            contentView.backgroundColor = defaultBackgroundColor
        }
    }

    public var defaultBackgroundColor: UIColor? {
        if style == .plain {
            return nil
        }
        else {
            return ThemeColors.shared.groupedTableRowBackground
        }
    }

    // MARK: - UICollectionViewCell

    override func prepareForReuse() {
        super.prepareForReuse()
        tableRowView.prepareForReuse()
    }

    override var isHighlighted: Bool {
        didSet {
            contentView.backgroundColor = isHighlighted ? ThemeColors.shared.highlightedBackgroundColor : defaultBackgroundColor
        }
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        return calculateLayoutAttributesFitting(layoutAttributes)
    }

    // MARK: - Separator

    /// When true, the cell will extend the separator all the way to its leading edge.
    public var collapseLeftInset: Bool = false

    let separator = tableCellSeparatorLayer()

    override func layoutSubviews() {
        super.layoutSubviews()

        let inset: CGFloat? = collapseLeftInset ? 0 : nil
        layoutSeparator(leftSeparatorInset: inset)
    }
}

// MARK: - Default Cell

class DefaultTableCell: TableRowCell {
    override init(frame: CGRect) {
        super.init(frame: frame)
        tableRowView = DefaultTableRowView.autolayoutNew()
    }
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - Value Cell

class ValueTableCell: TableRowCell {
    override init(frame: CGRect) {
        super.init(frame: frame)
        tableRowView = ValueTableRowView.autolayoutNew()
    }
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - Subtitle Cell

class SubtitleTableCell: TableRowCell {
    override init(frame: CGRect) {
        super.init(frame: frame)
        tableRowView = SubtitleTableRowView.autolayoutNew()
        tableRowView.subtitleFont = UIFont.preferredFont(forTextStyle: .footnote)
    }
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
