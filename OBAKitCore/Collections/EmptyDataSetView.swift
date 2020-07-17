//
//  EmptyDataSetView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit

/// Provides a simple implementation of the 'empty data set' UI pattern.
public class EmptyDataSetView: UIView {

    public enum EmptyDataSetAlignment {
        case top, center
    }

    /// The font used on the title label.
    @objc public dynamic var titleLabelFont: UIFont {
        set { titleLabel.font = newValue }
        get { return titleLabel.font }
    }

    /// The font used on the body label.
    @objc public dynamic var bodyLabelFont: UIFont {
        set { bodyLabel.font = newValue }
        get { return bodyLabel.font }
    }

    /// The text color used for the title and body labels.
    @objc public dynamic var textColor: UIColor {
        set {
            titleLabel.textColor = newValue
            bodyLabel.textColor = newValue
        }
        get { return titleLabel.textColor }
    }

    /// The title label. This property is exposed primarily to let you set the `text` property.
    public let titleLabel: UILabel = {
        let label = UILabel.obaLabel(font: UIFont.preferredFont(forTextStyle: .title1).bold,
                                        textColor: ThemeColors.shared.secondaryLabel)
        label.setContentHuggingPriority(.required, for: .vertical)
        label.textAlignment = .center
        label.backgroundColor = .clear
        return label
    }()

    /// The body label. This property is exposed primarily to let you set the `text` property.
    public let bodyLabel: UILabel = {
        let label = UILabel.obaLabel(textColor: ThemeColors.shared.secondaryLabel)
        label.setContentHuggingPriority(.required, for: .vertical)
        label.textAlignment = .center
        label.backgroundColor = .clear
        return label
    }()

    public init(alignment: EmptyDataSetAlignment = .center) {
        super.init(frame: .zero)

        let stack = UIStackView.verticalStack(arrangedSubviews: [titleLabel, bodyLabel])
        addSubview(stack)

        let leading = stack.leadingAnchor.constraint(equalTo: readableContentGuide.leadingAnchor)
        let trailing = stack.trailingAnchor.constraint(equalTo: readableContentGuide.trailingAnchor)

        // Priorities are specified to ensure that, for the period of time when this view
        // has a width==0, we don't end up with 'unsatisfiable constraints' errors.
        leading.priority = .defaultHigh
        trailing.priority = .defaultHigh

        let vertical: NSLayoutConstraint

        if alignment == .center {
            vertical = stack.centerYAnchor.constraint(equalTo: layoutMarginsGuide.centerYAnchor)
        }
        else {
            vertical = stack.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor)
        }

        NSLayoutConstraint.activate([vertical, leading, trailing])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
