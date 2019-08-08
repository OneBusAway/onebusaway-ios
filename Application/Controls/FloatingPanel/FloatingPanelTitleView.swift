//
//  FloatingPanelTitleView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 1/7/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import UIKit

/// The top view on a floating panel. Provides a title label, subtitle label, and close button.
public class FloatingPanelTitleView: UIView {

    // MARK: - Labels

    @objc dynamic var titleFont: UIFont {
        get { titleLabel.font }
        set { titleLabel.font = newValue }
    }

    public let titleLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.numberOfLines = 0
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    @objc dynamic var subtitleFont: UIFont {
        get { subtitleLabel.font }
        set { subtitleLabel.font = newValue }
    }

    public let subtitleLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.numberOfLines = 0
        return label
    }()

    private lazy var labelStackWrapper: UIView = labelStack.embedInWrapperView()
    private lazy var labelStack: UIStackView = UIStackView.verticalStack(arangedSubviews: [titleLabel, subtitleLabel])

    // MARK: - Close Button

    public let closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(Icons.closeCircle, for: .normal)
        button.accessibilityLabel = Strings.close
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .vertical)
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 30.0),
            button.widthAnchor.constraint(equalToConstant: 30.0)
        ])
        return button
    }()

    private lazy var closeButtonWrapper: UIView = {
        let wrapper = closeButton.embedInWrapperView(setConstraints: false)
        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            closeButton.topAnchor.constraint(equalTo: wrapper.topAnchor),
            closeButton.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            wrapper.heightAnchor.constraint(greaterThanOrEqualTo: closeButton.heightAnchor)
        ])

        return wrapper
    }()

    // MARK: - Config

    public override init(frame: CGRect) {
        super.init(frame: frame)

        let topStack = UIStackView.horizontalStack(arrangedSubviews: [labelStackWrapper, closeButtonWrapper])
        addSubview(topStack)
        topStack.pinToSuperview(.edges, insets: NSDirectionalEdgeInsets(top: ThemeMetrics.floatingPanelTopInset * 2.0, leading: 0, bottom: 0, trailing: 0))
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
