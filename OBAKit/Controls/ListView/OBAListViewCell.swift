//
//  OBAListViewCell.swift
//  OBAKit
//
//  Created by Alan Chu on 10/10/20.
//

import OBAKitCore

// swiftlint:disable colon

/// The base cell for all `OBAListView` cells.
public class OBAListViewCell:
    SwipeCollectionViewCell,
    ReuseIdentifierProviding,
    Separated,
    OBAContentView {

    public func apply(_ config: OBAContentConfiguration) {
        // nop.
    }

    // A "blink" animation to grab the user's attention to this cell.
    public func blink(_ color: UIColor = ThemeColors.shared.gray, delay: Double = 0.0) {
        let flash = CABasicAnimation(keyPath: "backgroundColor")
        flash.beginTime = CACurrentMediaTime() + delay
        flash.duration = 0.1
        flash.fromValue = layer.backgroundColor
        flash.toValue = color.cgColor
        flash.autoreverses = true
        flash.repeatCount = 2

        layer.add(flash, forKey: nil)
    }

    // MARK: - Initialization
    override public init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.addSublayer(separator)
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Separator

    /// When true, the cell will extend the separator all the way to its leading edge.
    public var collapseLeftInset: Bool = false

    public let separator = tableCellSeparatorLayer()

    public override func layoutSubviews() {
        super.layoutSubviews()

        let inset: CGFloat? = collapseLeftInset ? 0 : nil
        layoutSeparator(leftSeparatorInset: inset)
    }

}
