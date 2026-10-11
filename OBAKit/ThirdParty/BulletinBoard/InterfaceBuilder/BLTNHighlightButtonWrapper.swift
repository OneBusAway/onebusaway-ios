/**
 *  BulletinBoard
 *  Copyright (c) 2017 - present Alexis Aubry. Licensed under the MIT license.
 */

import UIKit

/**
 * A view that wraps a HighlightButton.
 *
 * A wrapper is required to avoid alpha animation issues when unhighlighting the button and performing
 * a bulletin transition.
 */

@objc class BLTNHighlightButtonWrapper: UIView {

    /// The underlying button.
    @objc let button: UIButton

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is unavailable. Use init(button:) instead.")
    }

    init(button: HighlightButton) {

        self.button = button
        super.init(frame: .zero)

        addSubview(button)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        button.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        button.topAnchor.constraint(equalTo: topAnchor).isActive = true
        button.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true

        // OBA: `intrinsicContentSize` mirrors the button's, which changes with
        // Dynamic Type; without this the wrapper kept the old size.
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self],
                                action: #selector(invalidateIntrinsicContentSize))

    }

    override var intrinsicContentSize: CGSize {
        return button.intrinsicContentSize
    }

}
