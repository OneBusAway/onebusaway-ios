//
//  SelfSizingCollectionCell.swift
//  OBANext
//
//  Created by Aaron Brethorst on 12/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit

class SelfSizingCollectionCell: UICollectionViewCell {
    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        setNeedsLayout()
        layoutIfNeeded()
        let size = contentView.systemLayoutSizeFitting(layoutAttributes.size)
        var newFrame = layoutAttributes.frame
        // note: don't change the width
        newFrame.size.height = ceil(size.height)
        layoutAttributes.frame = newFrame
        return layoutAttributes
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
