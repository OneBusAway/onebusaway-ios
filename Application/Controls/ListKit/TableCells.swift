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

class TableRowCell: SwipeCollectionViewCell {
    fileprivate let kUseDebugColors = false

    fileprivate var tableRowView: TableRowView! {
        didSet {
            contentView.addSubview(tableRowView)
            tableRowView.pinToSuperview(.layoutMargins)
            tableRowView.useDebugColors = kUseDebugColors
        }
    }

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)

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

    private var _highlightedBackgroundColor = UIColor(white: 0.9, alpha: 1.0)
    @objc dynamic var highlightedBackgroundColor: UIColor {
        get { return _highlightedBackgroundColor }
        set { _highlightedBackgroundColor = newValue }
    }

    private var _leftSeparatorInset: CGFloat = 20.0
    @objc dynamic var leftSeparatorInset: CGFloat {
        get { return _leftSeparatorInset }
        set { _leftSeparatorInset = newValue }
    }

    @objc dynamic var separatorColor: UIColor {
        get { return UIColor(cgColor: separator.backgroundColor!) }
        set { separator.backgroundColor = newValue.cgColor }
    }

    @objc dynamic var titleFont: UIFont {
        get { return tableRowView.titleFont }
        set { tableRowView.titleFont = newValue }
    }

    @objc dynamic var subtitleFont: UIFont {
        get { return tableRowView.subtitleFont }
        set { tableRowView.subtitleFont = newValue }
    }

    @objc dynamic var subtitleTextColor: UIColor {
        get { return tableRowView.subtitleTextColor }
        set { tableRowView.subtitleTextColor = newValue }
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

    let separator: CALayer = {
        let layer = CALayer()
        layer.backgroundColor = UIColor(red: 200 / 255.0, green: 199 / 255.0, blue: 204 / 255.0, alpha: 1).cgColor
        return layer
    }()

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = contentView.bounds
        let height: CGFloat = 0.5
        separator.frame = CGRect(x: leftSeparatorInset, y: bounds.height - height, width: bounds.width - leftSeparatorInset, height: height)
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
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
        backgroundColor = UIColor(white: 0.95, alpha: 0.95)

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
