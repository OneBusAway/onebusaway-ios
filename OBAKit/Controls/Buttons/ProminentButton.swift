//
//  ProminentButton.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/2/19.
//

import UIKit

/// A button with a background color, designed to give the button more of a tappable affordance.
class ProminentButton: UIButton {

    override init(frame: CGRect) {
        prominentColor = UIColor(white: 0.5, alpha: 0.1)
        highlightLayer.backgroundColor = prominentColor.cgColor
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
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

    override func layoutSubviews() {
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

        highlightLayer.frame = highlightFrame.insetBy(dx: -ThemeMetrics.compactPadding, dy: -ThemeMetrics.compactPadding)
    }
}
