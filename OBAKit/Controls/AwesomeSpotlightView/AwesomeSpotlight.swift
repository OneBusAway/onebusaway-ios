//
//  AwesomeSpotlight.swift
//  AwesomeSpotlightView
//
//  Created by Alex Shoshiashvili on 24.02.17.
//  Copyright © 2017 Alex Shoshiashvili. All rights reserved.
//

import UIKit

final public class AwesomeSpotlight: NSObject {
    let rect: CGRect
    let attributedText: NSAttributedString

    @objc public init(rect: CGRect, attributedText: NSAttributedString) {
        self.rect = rect
        self.attributedText = attributedText

        super.init()
    }
}
