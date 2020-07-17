//
//  TableHeaderSection.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import IGListKit
import OBAKitCore

// MARK: - TableHeaderData

/// View model for a collection cell that mimics the appearance of a header in a UITableView.
final class TableHeaderData: NSObject, ListDiffable {
    func diffIdentifier() -> NSObjectProtocol {
        self as NSObjectProtocol
    }

    func isEqual(toDiffableObject object: ListDiffable?) -> Bool {
        guard let object = object as? TableHeaderData else { return false }

        return title == object.title
    }

    let title: String

    init(title: String) {
        self.title = title
    }
}

// MARK: - TableHeaderSectionController

/// Section controller for a collection cell that mimics the appearance of a header in a UITableView.
final class TableHeaderSectionController: OBAListSectionController<TableHeaderData> {
    public override func sizeForItem(at index: Int) -> CGSize {
        return CGSize(width: collectionContext!.containerSize.width,
                      height: cellForItem(at: index).intrinsicContentSize.height)
    }

    // MARK: - Cell

    override func cellForItem(at index: Int) -> UICollectionViewCell {
        guard let sectionData = sectionData else { fatalError() }

        let cell = dequeueReusableCell(type: TableHeaderCell.self, at: index)
        cell.textLabel.text = sectionData.title
        cell.isGrouped = style == .grouped
        cell.hasVisualEffectBackground = hasVisualEffectBackground

        return cell
    }
}

// MARK: - TableHeaderCell

/// A collection cell that mimics the appearance of a header in a UITableView.
final class TableHeaderCell: SelfSizingCollectionCell, Separated {
    private let kUseDebugColors = false

    let textLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.font = UIFont.preferredFont(forTextStyle: .footnote).bold
        label.numberOfLines = 1
        label.accessibilityTraits = .header
        return label
    }()

    private lazy var bottomLabelAnchor = textLabel.bottomAnchor.constraint(equalTo: bottomAnchor).setPriority(.required - 1)

    override var intrinsicContentSize: CGSize {
        return self.systemLayoutSizeFitting(UIView.layoutFittingExpandedSize)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = defaultBackgroundColor
        addSubview(textLabel)

        NSLayoutConstraint.activate([
            textLabel.leadingAnchor.constraint(equalTo: readableContentGuide.leadingAnchor),
            textLabel.trailingAnchor.constraint(equalTo: readableContentGuide.trailingAnchor).setPriority(.required - 1),
            textLabel.topAnchor.constraint(equalTo: self.topAnchor, constant: ThemeMetrics.compactPadding),
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

    // MARK: - Visual Effect Background

    private let defaultBackgroundColor = ThemeColors.shared.secondaryBackgroundColor

    var hasVisualEffectBackground: Bool = false {
        didSet {
            if hasVisualEffectBackground {
                backgroundColor = UIColor(white: 1.0, alpha: 0.2)
            }
            else {
                backgroundColor = defaultBackgroundColor
            }
        }
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
