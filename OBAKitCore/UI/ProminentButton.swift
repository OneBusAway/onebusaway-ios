//
//  ProminentButton.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit

/// A button with a background color, designed to give the button more of a tappable affordance.
public class ProminentButton: UIButton {

    override public init(frame: CGRect) {
        prominentColor = UIColor(white: 0.5, alpha: 0.1)
        highlightLayer.backgroundColor = prominentColor.cgColor
        super.init(frame: frame)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public var prominentColor: UIColor {
        didSet {
            highlightLayer.backgroundColor = prominentColor.cgColor
        }
    }

    private let highlightLayer: CALayer = {
        let layer = CALayer()
        layer.cornerRadius = ThemeMetrics.compactCornerRadius

        return layer
    }()

    override public func layoutSubviews() {
        super.layoutSubviews()

        if highlightLayer.superlayer == nil {
            layer.addSublayer(highlightLayer)
        }

        let highlightFrame: CGRect

        if let imageView = imageView, let titleLabel = titleLabel {
            highlightFrame = imageView.frame.union(titleLabel.frame)
        }
        else if let imageView = imageView {
            highlightFrame = imageView.frame
        }
        else if let titleLabel = titleLabel {
            highlightFrame = titleLabel.frame
        }
        else {
            highlightFrame = .zero
        }

        highlightLayer.frame = highlightFrame.insetBy(dx: -ThemeMetrics.buttonContentPadding, dy: -ThemeMetrics.buttonContentPadding)
    }
}
