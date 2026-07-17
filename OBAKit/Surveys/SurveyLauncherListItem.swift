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
nonisolated struct SurveyLauncherListItem: OBAListViewItem {
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
nonisolated extension SurveyLauncherListItem: Equatable {
    static func == (lhs: SurveyLauncherListItem, rhs: SurveyLauncherListItem) -> Bool {
        return lhs.survey.id == rhs.survey.id &&
               lhs.title == rhs.title
    }
}

nonisolated extension SurveyLauncherListItem: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(survey.id)
        hasher.combine(title)
    }
}

// MARK: - Content Configuration
nonisolated struct SurveyLauncherContentConfiguration: OBAContentConfiguration {
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

    private let cardView = SurveyLauncherCardView(style: .grouped)

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

        cardView.onTakeSurvey = { [weak self] in self?.viewModel?.onTakeSurvey() }
        cardView.onDismiss = { [weak self] in self?.viewModel?.onDismiss() }

        contentView.addSubview(cardView)
        cardView.pinToSuperview(.edges)
    }

    // MARK: - Apply

    public override func apply(_ config: OBAContentConfiguration) {
        super.apply(config)

        guard let config = config as? SurveyLauncherContentConfiguration else {
            fatalError("Invalid configuration type for SurveyLauncherCell")
        }

        viewModel = config.viewModel
        cardView.configure(title: config.viewModel.title, subtitle: nil)
    }
}
