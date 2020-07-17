//
//  StackedTitleView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit

/// Provides a title label and a subtitle label stacked on top of each other. Meant for use in the `titleView` of a navigation bar.
class StackedTitleView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(stackView)
        stackView.pinToSuperview(.edges)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The top label on the `StackedTitleView`.
    let titleLabel = StackedTitleView.buildLabel(font: UIFont.preferredFont(forTextStyle: .footnote).bold)

    /// The bottom label on the `StackedTitleView`.
    let subtitleLabel = StackedTitleView.buildLabel(font: UIFont.preferredFont(forTextStyle: .footnote))

    private lazy var stackView = UIStackView.verticalStack(arrangedSubviews: [titleLabel, subtitleLabel])

    private class func buildLabel(font: UIFont) -> UILabel {
        let label = UILabel.autolayoutNew()
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.textAlignment = .center
        label.font = font
        label.allowsDefaultTighteningForTruncation = true

        return label
    }
}
