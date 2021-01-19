//
//  OBAListViewCell.swift
//  OBAKit
//
//  Created by Alan Chu on 10/10/20.
//

import OBAKitCore

/// The base cell for all `OBAListView` cells.
public class OBAListViewCell: SwipeCollectionViewCell, ReuseIdentifierProviding, OBAContentView {
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
}
