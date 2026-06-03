//
//  SurveyLauncherListItem.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore
import UIKit

/// Compact "survey launcher" card shown on the stop view for external surveys.
///
/// An icon tile, a title, and a two-action footer
/// (`Take survey` / `Not now`). It is a teaser — tapping `Take survey`
/// opens the survey; the card itself shows no questions.
struct SurveyLauncherListItem: OBAListViewItem {
    var configuration: OBAListViewItemConfiguration {
        return .custom(SurveyLauncherContentConfiguration(self))
    }

    static var customCellType: OBAListViewCell.Type? {
        return SurveyLauncherCell.self
    }

    var separatorConfiguration: OBAListRowSeparatorConfiguration {
        return .hidden()
    }

    var id: Int { survey.id }
    let survey: Survey
    let title: String

    let onTakeSurvey: () -> Void
    let onDismiss: () -> Void

    init(
        survey: Survey,
        title: String,
        onTakeSurvey: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.survey = survey
        self.title = title
        self.onTakeSurvey = onTakeSurvey
        self.onDismiss = onDismiss
    }
}

// MARK: - Protocol Conformances
extension SurveyLauncherListItem: Equatable {
    static func == (lhs: SurveyLauncherListItem, rhs: SurveyLauncherListItem) -> Bool {
        return lhs.survey.id == rhs.survey.id &&
               lhs.title == rhs.title
    }
}

extension SurveyLauncherListItem: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(survey.id)
        hasher.combine(title)
    }
}

// MARK: - Content Configuration
struct SurveyLauncherContentConfiguration: OBAContentConfiguration {
    var formatters: OBAKitCore.Formatters?

    var viewModel: SurveyLauncherListItem

    var obaContentView: (OBAContentView & ReuseIdentifierProviding).Type {
        return SurveyLauncherCell.self
    }

    init(_ viewModel: SurveyLauncherListItem) {
        self.viewModel = viewModel
    }
}

// MARK: - Cell
final class SurveyLauncherCell: OBAListViewCell {

    private var viewModel: SurveyLauncherListItem?

    // MARK: - Metrics (from the Option A design handoff)
    private enum Metrics {
        static let cardRadius: CGFloat = 16.0
        static let tileSize: CGFloat = 42.0
        static let tileRadius: CGFloat = 10.0
        static let tileGlyphPointSize: CGFloat = 20.0
        static let infoHorizontalPadding: CGFloat = 16.0
        static let infoVerticalPadding: CGFloat = 15.0
        static let tileTextGap: CGFloat = 14.0
        static let footerVerticalPadding: CGFloat = 12.0
        static let hairline: CGFloat = 0.5
        static let titleTextSize: CGFloat = 18.0
        static let footerTextSize: CGFloat = 16.0
        static let minimumTapTarget: CGFloat = 44.0
    }

    // MARK: - Subviews

    private let cardView: UIView = {
        let view = UIView.autolayoutNew()
        view.backgroundColor = .secondarySystemGroupedBackground
        view.layer.cornerRadius = Metrics.cardRadius
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

    private lazy var takeSurveyButton = SurveyLauncherCell.footerButton(
        title: OBALoc("survey_launcher.take_survey_button", value: "Take survey", comment: "Primary button on the survey launcher card; opens the survey."),
        weight: .semibold,
        titleColor: ThemeColors.shared.brand,
        pressedColor: ThemeColors.shared.brand.withAlphaComponent(0.08)
    )

    private lazy var notNowButton = SurveyLauncherCell.footerButton(
        title: OBALoc("survey_launcher.not_now_button", value: "Not now", comment: "Secondary button on the survey launcher card; dismisses the prompt."),
        weight: .medium,
        titleColor: .secondaryLabel,
        pressedColor: UIColor.label.withAlphaComponent(0.06)
    )

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        backgroundColor = .clear
        // Clear the inset-grouped list cell's default background so only our card shows.
        backgroundConfiguration = UIBackgroundConfiguration.clear()

        takeSurveyButton.addAction(UIAction { [weak self] _ in self?.viewModel?.onTakeSurvey() }, for: .touchUpInside)
        notNowButton.addAction(UIAction { [weak self] _ in self?.viewModel?.onDismiss() }, for: .touchUpInside)

        let textStack = UIStackView.verticalStack(arrangedSubviews: [titleLabel])
        textStack.spacing = 2.0

        iconTile.addSubview(tileGlyph)

        let infoRegion = UIStackView.horizontalStack(arrangedSubviews: [iconTile, textStack])
        infoRegion.alignment = .center
        infoRegion.spacing = Metrics.tileTextGap
        infoRegion.translatesAutoresizingMaskIntoConstraints = false
        infoRegion.isLayoutMarginsRelativeArrangement = true
        infoRegion.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Metrics.infoVerticalPadding,
            leading: Metrics.infoHorizontalPadding,
            bottom: Metrics.infoVerticalPadding,
            trailing: Metrics.infoHorizontalPadding
        )

        // The top divider lives in a container so the (fill-aligned) card stack
        // stretches the container while the hairline keeps its 16pt left inset.
        let topDivider = SurveyLauncherCell.hairline()
        let topDividerContainer = UIView.autolayoutNew()
        topDividerContainer.addSubview(topDivider)

        let footerDivider = SurveyLauncherCell.hairline()

        let footer = UIStackView.horizontalStack(arrangedSubviews: [takeSurveyButton, footerDivider, notNowButton])
        footer.alignment = .fill
        footer.distribution = .fill
        footer.translatesAutoresizingMaskIntoConstraints = false

        let cardStack = UIStackView.verticalStack(arrangedSubviews: [infoRegion, topDividerContainer, footer])
        cardStack.translatesAutoresizingMaskIntoConstraints = false

        cardView.addSubview(cardStack)
        contentView.addSubview(cardView)

        NSLayoutConstraint.activate([
            // Tile + glyph.
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
            takeSurveyButton.heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.minimumTapTarget),

            // Card stack fills the card.
            cardStack.topAnchor.constraint(equalTo: cardView.topAnchor),
            cardStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            cardStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            cardStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor)
        ])

        cardView.pinToSuperview(.edges)
    }

    // MARK: - Apply

    public override func apply(_ config: OBAContentConfiguration) {
        super.apply(config)

        guard let config = config as? SurveyLauncherContentConfiguration else {
            fatalError("Invalid configuration type for SurveyLauncherCell")
        }

        viewModel = config.viewModel
        titleLabel.text = config.viewModel.title
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
