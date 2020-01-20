//
//  EmptyDataSetView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 6/12/19.
//

import UIKit

/// Provides a simple implementation of the 'empty data set' UI pattern.
public class EmptyDataSetView: UIView {

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
        let label = UILabel.autolayoutNew()
        label.setContentHuggingPriority(.required, for: .vertical)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.backgroundColor = .clear
        return label
    }()

    /// The body label. This property is exposed primarily to let you set the `text` property.
    public let bodyLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.setContentHuggingPriority(.required, for: .vertical)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.backgroundColor = .clear
        return label
    }()

    public override init(frame: CGRect) {
        super.init(frame: frame)

        let stack = UIStackView.verticalStack(arangedSubviews: [titleLabel, bodyLabel])
        addSubview(stack)

        let leading = stack.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor)
        let trailing = stack.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor)

        // Priorities are specified to ensure that, for the period of time when this view
        // has a width==0, we don't end up with 'unsatisfiable constraints' errors.
        leading.priority = .defaultHigh
        trailing.priority = .defaultHigh

        let vertical = stack.centerYAnchor.constraint(equalTo: self.layoutMarginsGuide.centerYAnchor)

        NSLayoutConstraint.activate([vertical, leading, trailing])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
