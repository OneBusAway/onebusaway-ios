//
//  OBAListViewCell.swift
//  OBAKit
//
//  Created by Alan Chu on 10/10/20.
//

import SwipeCellKit

/// The base cell for all `OBAListView` cells.
public class OBAListViewCell: SwipeCollectionViewCell, ReuseIdentifierProviding, OBAContentView {
    public func apply(_ config: OBAContentConfiguration) {
        // nop.
    }
}
