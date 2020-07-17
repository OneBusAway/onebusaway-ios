//
//  FloatingPanelTitleView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

/// The top view on a floating panel. Provides a title label, subtitle label, and close button.
class FloatingPanelTitleView: UIView {
    // MARK: - Labels

    public let titleLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.numberOfLines = 0
        label.font = UIFont.preferredFont(forTextStyle: .title1).bold
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    public let subtitleLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.numberOfLines = 0
        label.font = UIFont.preferredFont(forTextStyle: .body)
        return label
    }()

    private lazy var labelStackWrapper: UIView = labelStack.embedInWrapperView()
    private lazy var labelStack: UIStackView = UIStackView.verticalStack(arrangedSubviews: [titleLabel, subtitleLabel])

    // MARK: - Close Button

    public let closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(Icons.closeCircle, for: .normal)
        button.accessibilityLabel = Strings.close
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .vertical)
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 40.0),
            button.widthAnchor.constraint(equalToConstant: 40.0)
        ])
        button.imageEdgeInsets = UIEdgeInsets(top: ThemeMetrics.padding, left: ThemeMetrics.padding, bottom: ThemeMetrics.padding, right: ThemeMetrics.padding)
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

    private let kUseDebugColors = false

    public override init(frame: CGRect) {
        super.init(frame: frame)

        let topStack = UIStackView.horizontalStack(arrangedSubviews: [labelStackWrapper, closeButtonWrapper])
        addSubview(topStack)
        topStack.pinToSuperview(.layoutMargins)

        if kUseDebugColors {
            titleLabel.backgroundColor = .red
            subtitleLabel.backgroundColor = .purple
            labelStackWrapper.backgroundColor = .yellow
            closeButton.backgroundColor = .blue
            closeButtonWrapper.backgroundColor = .green
            backgroundColor = .magenta
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
