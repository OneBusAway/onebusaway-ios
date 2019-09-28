//
//  BorderedButton.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/26/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit

/// A subclass of `UIButton` that has a rounded, shadowed border.
public class BorderedButton: UIButton {

    override public init(frame: CGRect) {
        super.init(frame: frame)

        configureButton()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        configureButton()
    }

    func configureButton() {
        contentEdgeInsets = UIEdgeInsets(top: 0, left: ThemeMetrics.padding, bottom: 0, right: ThemeMetrics.padding)
        layer.cornerRadius = 4.0
    }

    public override var tintColor: UIColor! {
        didSet {
            backgroundColor = tintColor
        }
    }
}
