//
//  TransitAlertCell.swift
//  OBAKit
//
//  Created by Alan Chu on 8/30/20.
//

import UIKit
import OBAKitCore

protocol TransitAlertData {
    var subjectText: String? { get }
    var subtitleText: String? { get }
    var isUnread: Bool { get }
}

final class TransitAlertCell: BaseSelfSizingTableCell {
    private let useDebugColors = false

    /// The maximum number of lines to display for the summary before truncation. Set to `0` for unlimited lines.
    /// - Note: A multiple of this value is used when the user's content size is set to an accessibility size.
    var titleNumberOfLines: Int = 2

    /// The maximum number of lines to display for the subject before truncation. Set to `0` for unlimited lines.
    /// - Note: A multiple of this value is used when the user's content size is set to an accessibility size.
    var subtitleNumberOfLines: Int = 1

    // MARK: - UI

    private var contentStack: UIStackView!
    let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.setCompressionResistance(vertical: .required)
        view.setHugging(horizontal: .defaultHigh)
        view.tintColor = ThemeColors.shared.brand
        view.preferredSymbolConfiguration = .init(font: .preferredFont(forTextStyle: .headline))

        return view
    }()

    private var textStack: UIStackView!

    let titleLabel: UILabel = .obaLabel(font: .preferredFont(forTextStyle: .body))
    let subtitleLabel: UILabel = .obaLabel(font: .preferredFont(forTextStyle: .footnote), textColor: ThemeColors.shared.secondaryLabel)

    private var chevronView: UIImageView!

    // MARK: - Data
    var data: TransitAlertData? {
        didSet {
            configureView()
        }
    }

    // MARK: - UICollectionViewCell

    override func prepareForReuse() {
        super.prepareForReuse()

        titleLabel.text = nil
        subtitleLabel.text = nil

        configureView()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.textStack = UIStackView.stack(axis: .vertical, distribution: .equalSpacing, arrangedSubviews: [titleLabel, subtitleLabel])
        self.textStack.spacing = ThemeMetrics.compactPadding

        self.contentStack = UIStackView.stack(axis: .horizontal, distribution: .fill, alignment: .leading, arrangedSubviews: [imageView, textStack])
        contentStack.spacing = ThemeMetrics.padding

        chevronView = UIImageView.autolayoutNew()
        chevronView.image = Icons.chevron
        NSLayoutConstraint.activate([
            chevronView.heightAnchor.constraint(equalToConstant: 14),
            chevronView.widthAnchor.constraint(equalToConstant: 8)
        ])
        chevronView.setContentHuggingPriority(.required, for: .horizontal)

        let outerStack = UIStackView.stack(axis: .horizontal, distribution: .fill, alignment: .center, arrangedSubviews: [contentStack, chevronView])

        contentView.addSubview(outerStack)

        outerStack.pinToSuperview(.readableContent) {
            $0.trailing.priority = .required - 1
        }

        configureView()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        configureView()
    }

    private func configureView() {
        guard let data = self.data else { return }

        imageView.image = data.isUnread ? Icons.unreadAlert : Icons.readAlert

        titleLabel.text = data.subjectText
        subtitleLabel.text = data.subtitleText

        if titleNumberOfLines > 0 {
            titleLabel.numberOfLines = isAccessibility ? titleNumberOfLines * 3 : titleNumberOfLines
        }
        else {
            titleLabel.numberOfLines = titleNumberOfLines
        }

        if subtitleNumberOfLines > 0 {
            subtitleLabel.numberOfLines = isAccessibility ? subtitleNumberOfLines * 4 : subtitleNumberOfLines
        }
        else {
            subtitleLabel.numberOfLines = subtitleNumberOfLines
        }

        contentStack.axis = isAccessibility ? .vertical : .horizontal
        contentStack.alignment = isAccessibility ? .leading : .center

        isAccessibilityElement = true
        accessibilityTraits = [.button, .staticText]
        accessibilityLabel = data.subjectText
        accessibilityLabel = Strings.serviceAlert
        accessibilityValue = data.subtitleText

        if useDebugColors {
            titleLabel.backgroundColor = .green
            contentView.backgroundColor = .yellow
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
