//
//  SurveyQuestionView.swift
//  OBAKit
//
//  Created by Mohamed Sliem on 23/12/2025.
//

import SwiftUI
import OBAKitCore

struct SurveyQuestionView: View {

    let question: SurveyQuestion

    let answer: SurveyQuestionAnswer?

    let isHeroQuestion: Bool

    let onUpdateAnswer: (SurveyQuestionAnswer) -> Void

    let onCloseAction: (() -> Void)?

    let onSubmitAction: (() -> Void)?

    init(
        question: SurveyQuestion,
        answer: SurveyQuestionAnswer? = nil,
        isHeroQuestion: Bool,
        onUpdateAnswer: @escaping (SurveyQuestionAnswer) -> Void,
        onCloseAction: (() -> Void)? = nil,
        onSubmitAction: (() -> Void)? = nil
    ) {
        self.question = question
        self.answer = answer
        self.isHeroQuestion = isHeroQuestion
        self.onUpdateAnswer = onUpdateAnswer
        self.onCloseAction = onCloseAction
        self.onSubmitAction = onSubmitAction
    }

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            questionHeader
            questionContent
            nextButton
        }
        .padding(.top, isHeroQuestion ? 24 : 16)
        .overlay(alignment: .topTrailing) {
            if isHeroQuestion {
                closeButton
            }
        }
        .clipShape(.rect(cornerRadius: 12))
        .background(borderView)
    }

    @ViewBuilder
    private var borderView: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(UIColor.tertiarySystemBackground.toColor())
    }

    private var questionHeader: some View {
        Text("\(question.position). \(question.content.labelText)")
            .font(.headline)
            .fontWeight(.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.trailing, 26)
    }

    @ViewBuilder
    private var questionContent: some View {
        let type = question.content.type

        if case .text = type {
            TextQuestionView(text: textAnswerValue, onUpdateAnswer: onUpdateAnswer)
        } else if case .radio = type {
            let options = question.content.options ?? []
            SelectionQuestionView(options: options, selection: selectionAnswerValues, isMultipleSelection: false, onUpdateAnswer: onUpdateAnswer)
        } else if case .checkbox = type {
            let options = question.content.options ?? []
            SelectionQuestionView(options: options, selection: selectionAnswerValues, isMultipleSelection: true, onUpdateAnswer: onUpdateAnswer)
        }
    }

    @ViewBuilder
    private var nextButton: some View {
        if isHeroQuestion {
            Button {
                onSubmitAction?()
            } label: {
                Text(Strings.next)
                    .font(.body)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(8)
                    .padding(.horizontal, 32)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(ThemeColors.shared.brand.toColor())
                    )
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)
        }
    }

    private var closeButton: some View {
        Button {
            onCloseAction?()
        } label: {
            Image(systemName: "xmark")
                .resizable()
                .fontWeight(.bold)
                .frame(width: 14, height: 14)
                .foregroundStyle(UIColor.label.toColor())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

}

// MARK: - Helper Methods
/// Helper methods that extract and normalize the current answer
/// from `SurveysVM` for use in SwiftUI-based question views hosted inside UIKit.
extension SurveyQuestionView {

    var textAnswerValue: String {
        guard case let .text(value) = answer else { return "" }
        return value
    }

    var selectionAnswerValues: Set<String> {
        switch answer {
        case .checkbox(let values):
            return values
        case .radio(let value):
            return [value]
        default:
            return []
        }
    }

}

#Preview {
    VStack {
        SurveyQuestionView(
            question: .init(
                id: 1,
                position: 2,
                required: true,
                content: .init(labelText: "Test question Test Test Test Test  Test Test  Test", type: .checkbox, options: ["yes", "No", "Maybe"])
            ),
            isHeroQuestion: false
        ) { _ in

        } onCloseAction: {

        } onSubmitAction: {

        }

    }
    .frame(maxHeight: .infinity)
    .background(UIColor.tertiarySystemBackground.toColor())
}
