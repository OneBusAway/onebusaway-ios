//
//  StackedButton.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

/// A subclass of `UIControl` that looks like a two row button with an icon on top and a text label below.
class StackedButton: UIControl {

    let kDebugColors = false

    public var title: String? {
        get {
            return textLabel.text
        }
        set {
            textLabel.text = newValue
            accessibilityLabel = newValue
        }
    }

    public let textLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.numberOfLines = 1
        label.textColor = ThemeColors.shared.brand
        label.text = "LABEL"
        label.textAlignment = .center
        label.isUserInteractionEnabled = false
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.font = UIFont.preferredFont(forTextStyle: .footnote).bold

        return label
    }()

    public let imageView: UIImageView = {
        let imageView = UIImageView.autolayoutNew()
        imageView.contentMode = .scaleAspectFit
        imageView.setContentHuggingPriority(.required, for: .vertical)
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        imageView.isUserInteractionEnabled = false
        imageView.tintColor = ThemeColors.shared.brand

        return imageView
    }()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false

        isUserInteractionEnabled = true
        backgroundColor = .clear

        let stack = UIStackView.verticalStack(arrangedSubviews: [imageView, textLabel])
        stack.isUserInteractionEnabled = false
        let wrapper = stack.embedInWrapperView()
        addSubview(wrapper)

        wrapper.pinToSuperview(.edges)

        if kDebugColors {
            backgroundColor = .magenta
            textLabel.backgroundColor = .green
            imageView.backgroundColor = .red
        }
    }

    required public init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
