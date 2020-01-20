//
//  SwipeCellKitExtensions.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 1/17/20.
//

import UIKit
import SwipeCellKit

extension SwipeCollectionViewCell {

    /// Call this in `init(frame:)` after `super.init(frame:)` to fix the iOS 13 Auto Layout
    /// bug described here: https://github.com/SwipeCellKit/SwipeCellKit/pull/333
    func fixiOS13AutoLayoutBug() {
        contentView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            contentView.topAnchor.constraint(equalTo: self.topAnchor),
            contentView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: self.bottomAnchor)
        ])
    }
}
