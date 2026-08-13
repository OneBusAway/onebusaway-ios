//
//  SurveyLauncherCardView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore
import UIKit

/// The "Option A" survey launcher card: an icon tile, a title (+ optional
/// subtitle), and a two-action footer (`Take survey` / `Not now`).
///
/// Shared by the stop view (embedded in a list cell, ``Style/grouped``) and the
/// map (a floating overlay, ``Style/floating``). It is a teaser — tapping
/// `Take survey` opens/presents the survey; the card itself shows no questions.
final class SurveyLauncherCardView: UIView {

    /// Visual treatment. The two surfaces differ only in corner radius, fill,
    /// shadow, and info padding (per the design handoff).
    enum Style {
        /// Inset-grouped list card on the stop view: no shadow, grouped fill.
        case grouped
        /// Floating overlay on the map: drop shadow, opaque fill, larger radius.
        case floating
    }

    var onTakeSurvey: (() -> Void)?
    var onDismiss: (() -> Void)?

    private let style: Style

    // MARK: - Metrics (from the design handoff)
    private enum Metrics {
        static let tileSize: CGFloat = 42.0
        static let tileRadius: CGFloat = 10.0
        static let tileGlyphPointSize: CGFloat = 20.0
        static let infoHorizontalPadding: CGFloat = 16.0
        static let tileTextGap: CGFloat = 14.0
        static let footerVerticalPadding: CGFloat = 12.0
        static let hairline: CGFloat = 0.5
        static let titleTextSize: CGFloat = 18.0
        static let subtitleTextSize: CGFloat = 14.5
        static let footerTextSize: CGFloat = 16.0
        static let minimumTapTarget: CGFloat = 44.0
    }

    private var cardRadius: CGFloat { style == .floating ? 18.0 : 16.0 }
    private var infoVerticalPadding: CGFloat { style == .floating ? 14.0 : 15.0 }
    private var cardBackgroundColor: UIColor {
        style == .floating ? .systemBackground : .secondarySystemGroupedBackground
    }

    // MARK: - Subviews

    private lazy var cardView: UIView = {
        let view = UIView.autolayoutNew()
        view.backgroundColor = cardBackgroundColor
        view.layer.cornerRadius = cardRadius
        view.clipsToBounds = true
        return view
    }()

    private let iconTile: UIView = {
        let view = UIView.autolayoutNew()
        view.backgroundColor = ThemeColors.shared.brand
        view.layer.cornerRadius = Metrics.tileRadius
        return view
    }()

    private let tileGlyph: UIImageView = {
        let symbol = UIImage(
            systemName: "list.clipboard",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: Metrics.tileGlyphPointSize, weight: .semibold)
        )
        let imageView = UIImageView(image: symbol)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.numberOfLines = 0
        label.textColor = .label
        label.font = UIFontMetrics(forTextStyle: .headline)
            .scaledFont(for: .systemFont(ofSize: Metrics.titleTextSize, weight: .bold))
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.numberOfLines = 0
        label.textColor = .secondaryLabel
        label.font = UIFontMetrics(forTextStyle: .subheadline)
            .scaledFont(for: .systemFont(ofSize: Metrics.subtitleTextSize, weight: .regular))
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private lazy var takeSurveyButton = SurveyLauncherCardView.footerButton(
        title: OBALoc("survey_launcher.take_survey_button", value: "Take survey", comment: "Primary button on the survey launcher card; opens the survey."),
        weight: .semibold,
        titleColor: ThemeColors.shared.brand,
        pressedColor: ThemeColors.shared.brand.withAlphaComponent(0.08)
    )

    private lazy var notNowButton = SurveyLauncherCardView.footerButton(
        title: OBALoc("survey_launcher.not_now_button", value: "Not now", comment: "Secondary button on the survey launcher card; dismisses the prompt."),
        weight: .medium,
        titleColor: .secondaryLabel,
        pressedColor: UIColor.label.withAlphaComponent(0.06)
    )

    // MARK: - Init

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Configuration

    /// Sets the card's copy. Pass `nil` for `subtitle` to hide the subtitle row.
    func configure(title: String, subtitle: String?) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle?.isEmpty ?? true
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        guard style == .floating else { return }
        // A shadow path lets the drop shadow render even though `cardView` clips.
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: cardRadius).cgPath
    }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        clipsToBounds = false

        if style == .floating {
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.18
            layer.shadowOffset = CGSize(width: 0, height: 6)
            layer.shadowRadius = 14
        }

        takeSurveyButton.addAction(UIAction { [weak self] _ in self?.onTakeSurvey?() }, for: .touchUpInside)
        notNowButton.addAction(UIAction { [weak self] _ in self?.onDismiss?() }, for: .touchUpInside)

        let textStack = UIStackView.verticalStack(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.spacing = 2.0

        iconTile.addSubview(tileGlyph)

        let infoRegion = UIStackView.horizontalStack(arrangedSubviews: [iconTile, textStack])
        infoRegion.alignment = .center
        infoRegion.spacing = Metrics.tileTextGap
        infoRegion.isLayoutMarginsRelativeArrangement = true
        infoRegion.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: infoVerticalPadding,
            leading: Metrics.infoHorizontalPadding,
            bottom: infoVerticalPadding,
            trailing: Metrics.infoHorizontalPadding
        )

        // The top divider lives in a container so the (fill-aligned) card stack
        // stretches the container while the hairline keeps its 16pt left inset.
        let topDivider = SurveyLauncherCardView.hairline()
        let topDividerContainer = UIView.autolayoutNew()
        topDividerContainer.addSubview(topDivider)

        let footerDivider = SurveyLauncherCardView.hairline()

        let footer = UIStackView.horizontalStack(arrangedSubviews: [takeSurveyButton, footerDivider, notNowButton])
        footer.alignment = .fill
        footer.distribution = .fill

        let cardStack = UIStackView.verticalStack(arrangedSubviews: [infoRegion, topDividerContainer, footer])

        cardView.addSubview(cardStack)
        cardStack.pinToSuperview(.edges)
        addSubview(cardView)
        cardView.pinToSuperview(.edges)

        NSLayoutConstraint.activate([
            iconTile.widthAnchor.constraint(equalToConstant: Metrics.tileSize),
            iconTile.heightAnchor.constraint(equalToConstant: Metrics.tileSize),
            tileGlyph.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            tileGlyph.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),

            // Top divider inset 16pt from the left, flush right.
            topDividerContainer.heightAnchor.constraint(equalToConstant: Metrics.hairline),
            topDivider.topAnchor.constraint(equalTo: topDividerContainer.topAnchor),
            topDivider.bottomAnchor.constraint(equalTo: topDividerContainer.bottomAnchor),
            topDivider.leadingAnchor.constraint(equalTo: topDividerContainer.leadingAnchor, constant: Metrics.infoHorizontalPadding),
            topDivider.trailingAnchor.constraint(equalTo: topDividerContainer.trailingAnchor),

            // Footer: equal-width halves split by a full-height vertical hairline.
            footerDivider.widthAnchor.constraint(equalToConstant: Metrics.hairline),
            notNowButton.widthAnchor.constraint(equalTo: takeSurveyButton.widthAnchor),
            takeSurveyButton.heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.minimumTapTarget)
        ])
    }

    // MARK: - Factories

    private static func footerButton(
        title: String,
        weight: UIFont.Weight,
        titleColor: UIColor,
        pressedColor: UIColor
    ) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.baseForegroundColor = titleColor
        config.contentInsets = NSDirectionalEdgeInsets(
            top: Metrics.footerVerticalPadding,
            leading: 0,
            bottom: Metrics.footerVerticalPadding,
            trailing: 0
        )
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFontMetrics(forTextStyle: .body)
                .scaledFont(for: .systemFont(ofSize: Metrics.footerTextSize, weight: weight))
            return outgoing
        }

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.configurationUpdateHandler = { btn in
            var updated = btn.configuration
            updated?.background.backgroundColor = btn.isHighlighted ? pressedColor : .clear
            btn.configuration = updated
        }
        return button
    }

    private static func hairline() -> UIView {
        let view = UIView.autolayoutNew()
        view.backgroundColor = .separator
        return view
    }
}
