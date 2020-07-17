//
//  StackedMarqueeTitleView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import MarqueeLabel
import OBAKitCore

class StackedMarqueeTitleView: UIView {
    public let topLabel: MarqueeLabel
    public let bottomLabel: MarqueeLabel

    init(width: CGFloat) {
        topLabel = StackedMarqueeTitleView.buildLabel(width: width, bold: true)
        bottomLabel = StackedMarqueeTitleView.buildLabel(width: width, bold: false)

        let height = topLabel.frame.height + bottomLabel.frame.height

        super.init(frame: CGRect(x: 0, y: 0, width: width, height: height))

        addSubview(topLabel)
        addSubview(bottomLabel)

        bottomLabel.frame.origin.y = topLabel.frame.maxY
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private class func buildLabel(width: CGFloat, bold: Bool) -> MarqueeLabel {
        let label = MarqueeLabel(frame: CGRect(x: 0, y: 0, width: width, height: 10.0))
        if bold {
            label.font = UIFont.preferredFont(forTextStyle: .footnote).bold
        }
        else {
            label.font = UIFont.preferredFont(forTextStyle: .footnote)
        }
        label.adjustsFontForContentSizeCategory = true
        label.trailingBuffer = ThemeMetrics.padding
        label.fadeLength = ThemeMetrics.padding
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.resizeHeightToFit()

        return label
    }
}
