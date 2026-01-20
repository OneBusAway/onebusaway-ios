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

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {

        let swiftUIView = getQuestionView()
        let hostingController = UIHostingController(rootView: swiftUIView)
        hostingController.view.backgroundColor = .clear

        contentView.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: contentView.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])

    }

    @ViewBuilder
    private func getQuestionView() -> some View {
        if let model {
            questionView(for: model)
        }
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

    let id: String

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
        self.id = UUID().uuidString
        self.onSelectAction = onSelectAction
        self.onSubmitAction = onSubmitAction
        self.onCloseAction = onCloseAction
        self.answer = answer
        self.question = question
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: HeroQuestionListItem, rhs: HeroQuestionListItem) -> Bool {
        return lhs.id == rhs.id
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
