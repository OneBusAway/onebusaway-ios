//
//  TableSectionHeaderView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 3/21/20.
//

import UIKit
import OBAKitCore

class TableSectionHeaderView: UICollectionReusableView, Separated {
    private let kUseDebugColors = false

    let textLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.font = UIFont.preferredFont(forTextStyle: .body).bold
        label.backgroundColor = ThemeColors.shared.secondaryBackgroundColor
        return label
    }()

    private lazy var bottomLabelAnchor = textLabel.bottomAnchor.constraint(equalTo: bottomAnchor)

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(textLabel)

        NSLayoutConstraint.activate([
            textLabel.leadingAnchor.constraint(equalTo: readableContentGuide.leadingAnchor),
            textLabel.trailingAnchor.constraint(equalTo: readableContentGuide.trailingAnchor),
            bottomLabelAnchor
        ])

        if kUseDebugColors {
            backgroundColor = .red
            textLabel.backgroundColor = .magenta
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        textLabel.text = nil
    }

    // MARK: - Separator

    /// Set this to true when the header is being used in a grouped style.
    public var isGrouped: Bool = false {
        didSet {
            if isGrouped {
                bottomLabelAnchor.constant = -ThemeMetrics.ultraCompactPadding
                if separator.superlayer == nil {
                    layer.addSublayer(separator)
                }
                setNeedsLayout()
            }
            else {
                bottomLabelAnchor.constant = 0.0
                separator.removeFromSuperlayer()
            }
        }
    }

    let separator = tableCellSeparatorLayer()

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutSeparator(leftSeparatorInset: 0)
    }
}
