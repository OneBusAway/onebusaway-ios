//
//  BorderedButton.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

/// A subclass of `UIButton` that has a rounded, shadowed border.
class BorderedButton: UIButton {

    override public init(frame: CGRect) {
        super.init(frame: frame)

        setTitleColor(ThemeColors.shared.lightText, for: .normal)
        tintColor = ThemeColors.shared.brand
        contentEdgeInsets = UIEdgeInsets(top: 0, left: ThemeMetrics.padding, bottom: 0, right: ThemeMetrics.padding)
        layer.cornerRadius = 4.0
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError()
    }
}
