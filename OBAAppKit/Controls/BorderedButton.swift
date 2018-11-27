//
//  BorderedButton.swift
//  OBAAppKit
//
//  Created by Aaron Brethorst on 11/26/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit

@objc(OBABorderedButton)
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
        contentEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        layer.cornerRadius = 4.0
        layer.shadowRadius = 2.0
        layer.shadowOpacity = 0.25
        layer.shadowOffset = CGSize(width: 0, height: 1)
    }

    public override var tintColor: UIColor! {
        didSet {
            backgroundColor = tintColor
        }
    }
}
