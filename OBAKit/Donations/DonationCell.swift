//
//  DonationCell.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/30/23.
//

import UIKit
import OBAKitCore

class DonationCell: OBAListViewCell {

    var donationRequest: DonationRequest?
    var viewModel: DonationListItem?

    public override func apply(_ config: OBAContentConfiguration) {
        super.apply(config)

        guard let config = config as? DonationContentConfiguration else {
            fatalError()
        }

        viewModel = config.viewModel
    }

    lazy var titleLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .title3).bold

        label.text = OBALoc("donation_cell.title", value: "🚨 OneBusAway needs your help", comment: "Title of the donation widget that appears on the stop view controller.")
        return label
    }()

    lazy var closeButton = {
        let button = UIButton.buildCloseButton()
        let action = UIAction { [self] _ in
            guard let viewModel = viewModel else { return }
            viewModel.onCloseAction?(viewModel)
        }
        button.addAction(action, for: .touchUpInside)
        return button
    }()

    lazy var closeButtonWrapper: UIView = {
        let wrapper = closeButton.embedInWrapperView(setConstraints: false)
        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            closeButton.topAnchor.constraint(equalTo: wrapper.topAnchor),
            closeButton.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            wrapper.heightAnchor.constraint(greaterThanOrEqualTo: closeButton.heightAnchor)
        ])

        return wrapper
    }()

    lazy var titleRow = UIStackView.horizontalStack(arrangedSubviews: [titleLabel, closeButtonWrapper])

    lazy var messageLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.numberOfLines = 0
        label.text = OBALoc("donation_cell.body", value: "This app is currently built with 100% volunteer labor, and we need you to help us fund future development.", comment: "Body of the donation widget that appears on the stop view controller")
        return label
    }()

    lazy var learnMoreButton: UIButton = {
        let action = UIAction { [self] _ in
            guard let viewModel = viewModel else { return }
            viewModel.onLearnMoreAction?(viewModel)
        }
        let button = UIButton(configuration: .bordered(), primaryAction: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(OBALoc("donation_cell.learn_more_button_title", value: "Learn More", comment: "Title of the button that shows the donation explanation UI."), for: .normal)
        return button
    }()

    lazy var donateButton: UIButton = {
        let button = UIButton(configuration: .borderedProminent())
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(OBALoc("donation_cell.donate_button_title", value: "Donate Now", comment: "Title of the button that shows the donation UI."), for: .normal)

        let action = UIAction { [self] _ in
            guard let viewModel = viewModel else { return }
            viewModel.onSelectAction?(viewModel)
        }
        button.addAction(action, for: .touchUpInside)
        return button
    }()

    lazy var buttonStack: UIStackView = {
        let stack = UIStackView.horizontalStack(arrangedSubviews: [learnMoreButton, donateButton])
        stack.spacing = ThemeMetrics.compactPadding

        return stack
    }()

    lazy var outerStack: UIStackView = {
        let stack = UIStackView.verticalStack(arrangedSubviews: [
            titleRow,
            messageLabel,
            UIView.spacerView(height: 4.0),
            buttonStack
        ])
        stack.spacing = 4.0
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        addSubview(outerStack)
        outerStack.pinToSuperview(.edges, insets: NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: -8, trailing: -8))
    }
}
