//
//  ReuseIdentifierProviding.swift
//  OBAKit
//
//  Created by Alan Chu on 10/2/20.
//

import UIKit

/// Implements a common `ReuseIdentifier` property for recycling `UICollectionViewCell`s.
public protocol ReuseIdentifierProviding: UICollectionViewCell {
    static var ReuseIdentifier: String { get }
}

extension ReuseIdentifierProviding {
    // Default implementation.
    static public var ReuseIdentifier: String {
        return "\(String(describing: self))_ReuseIdentifier"
    }
}
