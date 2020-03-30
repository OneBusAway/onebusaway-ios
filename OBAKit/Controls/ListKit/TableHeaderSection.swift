//
//  TableHeaderSection.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 3/28/20.
//

import Foundation
import IGListKit
import OBAKitCore

// MARK: - TableHeaderData

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

final class TableHeaderSectionController: OBAListSectionController<TableHeaderData> {
    public override func sizeForItem(at index: Int) -> CGSize {
        return CGSize(width: collectionContext!.containerSize.width, height: 20.0)
    }

    // MARK: - Cell

    override func cellForItem(at index: Int) -> UICollectionViewCell {
        let cell = dequeueReusableCell(type: TableHeaderCell.self, at: index)
        cell.textLabel.text = sectionData?.title ?? ""
        cell.isGrouped = style == .grouped
        return cell
    }
}

// MARK: - TableHeaderCell

final class TableHeaderCell: SelfSizingCollectionCell, Separated {
    private let kUseDebugColors = false

    let textLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.font = UIFont.preferredFont(forTextStyle: .footnote).bold
        return label
    }()

    private lazy var bottomLabelAnchor = textLabel.bottomAnchor.constraint(equalTo: bottomAnchor)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = ThemeColors.shared.secondaryBackgroundColor

        addSubview(textLabel)

        NSLayoutConstraint.activate([
            textLabel.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            textLabel.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
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
