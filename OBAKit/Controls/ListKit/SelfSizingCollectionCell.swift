//
//  SelfSizingCollectionCell.swift
//  OBANext
//
//  Created by Aaron Brethorst on 12/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit
import OBAKitCore

class SelfSizingCollectionCell: UICollectionViewCell, SelfSizing {
    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        return calculateLayoutAttributesFitting(layoutAttributes)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        clipsToBounds = true

        contentView.frame = bounds
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.clipsToBounds = true
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
