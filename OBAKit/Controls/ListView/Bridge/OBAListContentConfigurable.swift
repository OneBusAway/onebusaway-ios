//
//  OBAListContentConfigurable.swift
//  OBAKit
//
//  Created by Alan Chu on 10/3/20.
//

import Foundation

public protocol OBAListContentConfigurable: UICollectionViewCell, ReuseIdentifierProviding {
    func configure(with config: OBAListContentConfiguration)
}
