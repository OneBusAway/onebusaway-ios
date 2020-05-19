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

public protocol Separated: NSObjectProtocol {
    var separator: CALayer { get }
    func layoutSeparator(leftSeparatorInset: CGFloat?)

    static func tableCellSeparatorLayer() -> CALayer
}

public extension Separated where Self: UICollectionReusableView {
    func layoutSeparator(leftSeparatorInset: CGFloat? = nil) {
        let height: CGFloat = 1.0 / UIScreen.main.scale
        let inset = leftSeparatorInset ?? layoutMargins.left

        separator.frame = CGRect(x: inset, y: bounds.height - height, width: bounds.width - inset, height: height)
    }

    static func tableCellSeparatorLayer() -> CALayer {
        let layer = CALayer()
        layer.backgroundColor = ThemeColors.shared.separator.cgColor
        return layer
    }
}
