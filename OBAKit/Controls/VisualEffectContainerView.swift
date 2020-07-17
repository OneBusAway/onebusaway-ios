//
//  VisualEffectContainerView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit

/// A container view that simplifies using a `UIVisualEffectView`.
class VisualEffectContainerView: UIView {
    private let effectView: UIVisualEffectView

    /// Add your subviews to this view, not the receiver.
    public var contentView: UIView { effectView.contentView }

    init(blurEffect: UIBlurEffect) {
        effectView = UIVisualEffectView(effect: blurEffect)
        effectView.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: .zero)

        addSubview(effectView)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
