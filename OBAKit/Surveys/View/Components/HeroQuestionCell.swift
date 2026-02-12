//
//  HeroQuestionView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore
import SwiftUI

class HeroQuestionCell: OBAListViewCell {

    var model: HeroQuestionListItem?

    public override func apply(_ config: OBAContentConfiguration) {
        guard let config = config as? HeroQuestionContentConfiguration else {
            fatalError()
        }

        model = config.model
        setupView()
    }

    private func setupView() {
        guard let model else { return }

        contentConfiguration = UIHostingConfiguration {
            questionView(for: model)
        }
        .margins(.all, 0)
    }

    @ViewBuilder
    private func questionView(for model: HeroQuestionListItem) -> some View {
        switch model.question.content.type {
        case .externalSurvey:
            ExternalSurveyView(
                question: model.question,
                onCloseAction: model.onCloseAction,
                onSubmitAction: model.onSubmitAction
            )

        default:
            SurveyQuestionView(
                question: model.question,
                answer: model.answer,
                isHeroQuestion: true,
                onUpdateAnswer: model.onSelectAction,
                onCloseAction: model.onCloseAction,
                onSubmitAction: model.onSubmitAction
            )
        }
    }

}

// MARK: - List Item
struct HeroQuestionListItem: OBAListViewItem {
    var configuration: OBAListViewItemConfiguration {
        return .custom(HeroQuestionContentConfiguration(self))
    }

    static var customCellType: OBAListViewCell.Type? {
        return HeroQuestionCell.self
    }

    var id: Int { question.id }

    let question: SurveyQuestion

    let answer: SurveyQuestionAnswer?

    let onSelectAction: (SurveyQuestionAnswer) -> Void
    let onSubmitAction: () -> Void
    let onCloseAction: () -> Void

    init(
        question: SurveyQuestion,
        answer: SurveyQuestionAnswer? = nil,
        onSelectAction: @escaping (SurveyQuestionAnswer) -> Void,
        onSubmitAction: @escaping () -> Void,
        onCloseAction: @escaping () -> Void
    ) {
        self.onSelectAction = onSelectAction
        self.onSubmitAction = onSubmitAction
        self.onCloseAction = onCloseAction
        self.answer = answer
        self.question = question
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(answer)
    }

    static func == (lhs: HeroQuestionListItem, rhs: HeroQuestionListItem) -> Bool {
        return lhs.id == rhs.id && lhs.answer == rhs.answer
    }
}

// MARK: - Configuration
struct HeroQuestionContentConfiguration: OBAContentConfiguration {
    var formatters: OBAKitCore.Formatters?

    var model: HeroQuestionListItem

    var obaContentView: (OBAContentView & ReuseIdentifierProviding).Type {
        return HeroQuestionCell.self
    }

    init(_ model: HeroQuestionListItem) {
        self.model = model
    }
}
