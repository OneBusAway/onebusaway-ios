//
//  VisualEffectContainerView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 9/19/19.
//

import UIKit

/// A container view that simplifies using a `UIVisualEffectView` with blur and vibrancy effects.
class VisualEffectContainerView: UIView {
    private let effectView: UIVisualEffectView
    private let vibrancyView: UIVisualEffectView

    /// Add your subviews to this view, not the receiver.
    public var contentView: UIView { vibrancyView.contentView }

    init(blurEffect: UIBlurEffect) {
        effectView = UIVisualEffectView(effect: blurEffect)
        effectView.translatesAutoresizingMaskIntoConstraints = false

        let vibrancyEffect = UIVibrancyEffect(blurEffect: blurEffect)
        vibrancyView = UIVisualEffectView(effect: vibrancyEffect)
        vibrancyView.translatesAutoresizingMaskIntoConstraints = false

        effectView.contentView.addSubview(vibrancyView)
        super.init(frame: .zero)

        addSubview(effectView)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            vibrancyView.leadingAnchor.constraint(equalTo: effectView.contentView.leadingAnchor),
            vibrancyView.trailingAnchor.constraint(equalTo: effectView.contentView.trailingAnchor),
            vibrancyView.topAnchor.constraint(equalTo: effectView.contentView.topAnchor),
            vibrancyView.bottomAnchor.constraint(equalTo: effectView.contentView.bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
