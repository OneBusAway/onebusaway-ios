//
//  OBAListViewSeparatorSupplementaryView.swift
//  OBAKit
//
//  Created by Alan Chu on 10/10/20.
//

import OBAKitCore

/// A footer view displaying a separator line. Useful for faking a cell row collapse animation.
class OBAListViewSeparatorSupplementaryView: UICollectionReusableView {
    static let ReuseIdentifier: String = "OBAListRowSeparatorSupplementaryView_ReuseIdentifier"

    public override init(frame: CGRect) {
        super.init(frame: frame)

        self.layer.backgroundColor = UIColor.secondarySystemBackground.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
