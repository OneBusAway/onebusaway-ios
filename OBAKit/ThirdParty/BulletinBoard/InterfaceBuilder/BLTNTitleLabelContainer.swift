/**
 *  BulletinBoard
 *  Copyright (c) 2017 - present Alexis Aubry. Licensed under the MIT license.
 */

import UIKit

/**
 * A view that contains a title label.
 */

@objc class BLTNTitleLabelContainer: UIView {

    /// The label contained in the view.
    @objc let label: UILabel

    // MARK: - Initialization

    @objc init(label: UILabel, horizontalInset: CGFloat) {
        self.label = label
        super.init(frame: .zero)
        configureSubviews(horizontalInset: horizontalInset)
        // OBA: `intrinsicContentSize` mirrors the label's, which changes with
        // Dynamic Type; without this the container kept the old size.
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self],
                                action: #selector(invalidateIntrinsicContentSize))
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureSubviews(horizontalInset: CGFloat) {

        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false

        label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalInset).isActive = true
        label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalInset).isActive = true
        label.topAnchor.constraint(equalTo: topAnchor).isActive = true
        label.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true

    }

    override var intrinsicContentSize: CGSize {
        return label.intrinsicContentSize
    }

}
