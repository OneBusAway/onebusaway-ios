//
//  TableCells.swift
//  OBANext
//
//  Created by Aaron Brethorst on 1/15/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import UIKit
import IGListKit
import SwipeCellKit

// MARK: -

protocol SelfSizing: NSObjectProtocol {
    func calculateLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes
}

extension SelfSizing where Self: UICollectionViewCell {
    func calculateLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        setNeedsLayout()
        layoutIfNeeded()
        let size = contentView.systemLayoutSizeFitting(layoutAttributes.size)
        var newFrame = layoutAttributes.frame
        // note: don't change the width
        newFrame.size.height = ceil(size.height)
        layoutAttributes.frame = newFrame
        return layoutAttributes
    }
}

// MARK: - SeparatedCell

func tableCellSeparatorLayer() -> CALayer {
    let layer = CALayer()
    layer.backgroundColor = ThemeColors.shared.separator.cgColor
    return layer
}

protocol Separated: NSObjectProtocol {
    var separator: CALayer { get }
    func layoutSeparator(leftSeparatorInset: CGFloat?)
}

extension Separated where Self: UICollectionViewCell {
    func layoutSeparator(leftSeparatorInset: CGFloat? = nil) {
        let bounds = contentView.bounds
        let height: CGFloat = 0.5
        let inset = leftSeparatorInset ?? layoutMargins.left

        separator.frame = CGRect(x: inset, y: bounds.height - height, width: bounds.width - inset, height: height)
    }
}

// MARK: - TableRowCell

class TableRowCell: SwipeCollectionViewCell, SelfSizing, Separated {
    fileprivate let kUseDebugColors = false

    fileprivate var tableRowView: TableRowView! {
        didSet {
            contentView.addSubview(tableRowView)
            NSLayoutConstraint.activate([
                tableRowView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
                tableRowView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
                tableRowView.topAnchor.constraint(equalTo: contentView.topAnchor),
                tableRowView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
            tableRowView.useDebugColors = kUseDebugColors
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

    // MARK: - UIAppearance Selectors

    private let highlightedBackgroundColor = ThemeColors.shared.highlightedBackgroundColor

    @objc dynamic var titleFont: UIFont {
        get { return tableRowView.titleFont }
        set { tableRowView.titleFont = newValue }
    }

    @objc dynamic var subtitleFont: UIFont {
        get { return tableRowView.subtitleFont }
        set { tableRowView.subtitleFont = newValue }
    }

    // MARK: - UICollectionViewCell

    override func prepareForReuse() {
        super.prepareForReuse()
        tableRowView.prepareForReuse()
    }

    override var isHighlighted: Bool {
        didSet {
            contentView.backgroundColor = isHighlighted ? highlightedBackgroundColor : .clear
        }
    }

    let separator = tableCellSeparatorLayer()

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutSeparator()
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        return calculateLayoutAttributesFitting(layoutAttributes)
    }
}

// MARK: - Default Cell

class DefaultTableCell: TableRowCell {
    override init(frame: CGRect) {
        super.init(frame: frame)
        tableRowView = DefaultTableRowView.autolayoutNew()
        tableRowView.heightConstraint.priority = .defaultHigh
    }
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - Value Cell

class ValueTableCell: TableRowCell {
    override init(frame: CGRect) {
        super.init(frame: frame)
        tableRowView = ValueTableRowView.autolayoutNew()
        tableRowView.heightConstraint.priority = .defaultHigh
    }
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - Subtitle Cell

class SubtitleTableCell: TableRowCell {
    override init(frame: CGRect) {
        super.init(frame: frame)
        tableRowView = SubtitleTableRowView.autolayoutNew()
        tableRowView.heightConstraint.priority = .defaultHigh
    }
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

class TableSectionHeaderView: UICollectionReusableView {

    let textLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.font = UIFont.boldSystemFont(ofSize: UIFont.systemFontSize)
        return label
    }()

    @objc dynamic var font: UIFont {
        get { return textLabel.font }
        set { textLabel.font = newValue }
    }

    override var backgroundColor: UIColor? {
        didSet {
            textLabel.backgroundColor = backgroundColor
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(textLabel)

        NSLayoutConstraint.activate([
            textLabel.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor),
            textLabel.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor),
            textLabel.topAnchor.constraint(equalTo: self.topAnchor),
            textLabel.bottomAnchor.constraint(equalTo: self.bottomAnchor)
        ])
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        textLabel.text = nil
    }
}
