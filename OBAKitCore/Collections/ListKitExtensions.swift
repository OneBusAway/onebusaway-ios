//
//  ListKitExtensions.swift
//  OBAKitCore
//
//  Created by Aaron Brethorst on 2/12/20.
//

import UIKit

// MARK: - SelfSizing

public protocol SelfSizing: NSObjectProtocol {
    func calculateLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes
}

public extension SelfSizing where Self: UICollectionViewCell {
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

public func tableCellSeparatorLayer() -> CALayer {
    let layer = CALayer()
    layer.backgroundColor = ThemeColors.shared.separator.cgColor
    return layer
}

public protocol Separated: NSObjectProtocol {
    var separator: CALayer { get }
    func layoutSeparator(leftSeparatorInset: CGFloat?)
}

public extension Separated where Self: UICollectionViewCell {
    func layoutSeparator(leftSeparatorInset: CGFloat? = nil) {
        let bounds = contentView.bounds
        let height: CGFloat = 0.5
        let inset = leftSeparatorInset ?? layoutMargins.left

        separator.frame = CGRect(x: inset, y: bounds.height - height, width: bounds.width - inset, height: height)
    }
}
