//
//  ListKitDebugging.swift
//  OBANext
//
//  Created by Aaron Brethorst on 1/13/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import UIKit
import IGListKit

final class LabelSectionController: ListSectionController {
    private var object: String?

    override func sizeForItem(at index: Int) -> CGSize {
        return CGSize(width: collectionContext!.containerSize.width, height: 40)
    }

    override func cellForItem(at index: Int) -> UICollectionViewCell {
        guard let cell = collectionContext?.dequeueReusableCell(of: LabelCell.self, for: self, at: index) as? LabelCell else {
            fatalError()
        }
        cell.text = object
        return cell
    }

    override func didUpdate(to object: Any) {
        self.object = String(describing: object)
    }
}

final class LabelCell: UICollectionViewCell {
    fileprivate static let insets = UIEdgeInsets(top: 8, left: 15, bottom: 8, right: 15)
    fileprivate static let font = UIFont.systemFont(ofSize: 17)

    static var singleLineHeight: CGFloat {
        return font.lineHeight + insets.top + insets.bottom
    }

    static func textHeight(_ text: String, width: CGFloat) -> CGFloat {
        let constrainedSize = CGSize(width: width - insets.left - insets.right, height: CGFloat.greatestFiniteMagnitude)
        let attributes = [ NSAttributedString.Key.font: font ]
        let options: NSStringDrawingOptions = [.usesFontLeading, .usesLineFragmentOrigin]
        let bounds = (text as NSString).boundingRect(with: constrainedSize, options: options, attributes: attributes, context: nil)
        return ceil(bounds.height) + insets.top + insets.bottom
    }

    fileprivate let label: UILabel = {
        let label = UILabel()
        label.backgroundColor = .clear
        label.numberOfLines = 0
        label.font = LabelCell.font
        return label
    }()

    let separator: CALayer = {
        let layer = CALayer()
        layer.backgroundColor = ThemeColors.shared.separator.cgColor
        return layer
    }()

    var text: String? {
        get {
            return label.text
        }
        set {
            label.text = newValue
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(label)
        contentView.layer.addSublayer(separator)
        contentView.backgroundColor = .white
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = contentView.bounds
        label.frame = bounds.inset(by: LabelCell.insets)
        let height: CGFloat = 0.5
        let left = LabelCell.insets.left
        separator.frame = CGRect(x: left, y: bounds.height - height, width: bounds.width - left, height: height)
    }

    override var isHighlighted: Bool {
        didSet {
            contentView.backgroundColor = ThemeColors.shared.highlightedBackgroundColor
        }
    }

}
