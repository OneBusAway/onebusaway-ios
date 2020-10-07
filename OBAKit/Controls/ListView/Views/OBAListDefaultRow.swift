//
//  OBAListViewRow.swift
//  OBAKit
//
//  Created by Alan Chu on 10/2/20.
//

import UIKit

// MARK: - iOS 14+
@available(iOS 14, *)
extension UICollectionViewListCell: OBAListContentConfigurable {
    public func configure(with config: OBAListContentConfiguration) {
        self.contentConfiguration = config.listContentConfiguration
    }
}
