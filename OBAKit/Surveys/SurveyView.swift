//
//  SurveyView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The survey form: the study's description, one block per question, and a
/// submit button. Answers go to `SurveyViewModel` as they change; submission
/// outcomes and the Close button belong to `SurveyViewController`.
struct SurveyView: View {
    @ObservedObject var viewModel: SurveyViewModel
    let openExternalSurvey: () -> Void

    var body: some View {
        Form {
            if let description = viewModel.survey.study.description {
                Section {
                    Text(description)
                }
            }

            Section {
                ForEach(viewModel.questionsToShow, id: \.id) { question in
                    SurveyQuestionRows(question: question, viewModel: viewModel, openExternalSurvey: openExternalSurvey)
                }
            } header: {
                Text(OBALoc("survey_vc.questions_section_title", value: "Questions", comment: "Section header for survey questions"))
            }

            Section {
                Button(Self.submitTitle(isSubmitting: viewModel.isSubmitting)) {
                    Task { await viewModel.submit() }
                }
                .disabled(viewModel.isSubmitting)
            }
        }
    }

    /// While a submit is in flight the button reads "Submitting…" and is
    /// disabled, so a second tap isn't silently dropped by the view model's
    /// in-flight guard (#1169).
    static func submitTitle(isSubmitting: Bool) -> String {
        isSubmitting
            ? OBALoc("survey_vc.submitting_button", value: "Submitting…", comment: "Submit button title while a survey submission is in flight")
            : OBALoc("survey_vc.submit_button", value: "Submit Survey", comment: "Button to submit the survey")
    }
}

/// The rows for one question. Holds the question's on-screen answer; every
/// change is reported to the view model, which owns the submitted answers.
private struct SurveyQuestionRows: View {
    let question: SurveyQuestion
    let viewModel: SurveyViewModel
    let openExternalSurvey: () -> Void

    @State private var choice: String?
    @State private var checked: Set<String> = []
    @State private var text = ""

    private var options: [String] { question.content.options ?? [] }

    var body: some View {
        switch question.content.type {
        case .label:
            Text(question.content.labelText)

        case .radio:
            prompt
            if options.count <= 3 {
                Picker(question.content.labelText, selection: $choice) {
                    ForEach(options, id: \.self) { Text($0).tag(Optional($0)) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: choice) { _, choice in
                    if let choice { viewModel.updateAnswer(for: question, answer: choice) }
                }
            } else {
                ForEach(options, id: \.self) { option in
                    CheckmarkRow(title: option, isChecked: choice == option) {
                        choice = option
                        viewModel.updateAnswer(for: question, answer: option)
                    }
                }
            }

        case .checkbox:
            prompt
            ForEach(options, id: \.self) { option in
                CheckmarkRow(title: option, isChecked: checked.contains(option)) {
                    let isChecked = !checked.contains(option)
                    if isChecked { checked.insert(option) } else { checked.remove(option) }
                    viewModel.toggleCheckbox(option: option, selected: isChecked, for: question)
                }
            }

        case .text:
            prompt
            TextField(
                OBALoc("survey_vc.text_placeholder", value: "Enter your answer...", comment: "Placeholder for text answer field"),
                text: $text,
                axis: .vertical
            )
            .lineLimit(3...8)
            .onChange(of: text) { _, text in
                // A cleared field takes the answer back, so a required question
                // emptied by the rider fails validation instead of submitting
                // what they deleted.
                if text.isEmpty {
                    viewModel.clearAnswer(for: question)
                } else {
                    viewModel.updateAnswer(for: question, answer: text)
                }
            }

        case .externalSurvey:
            Text(question.content.labelText)
            Button(OBALoc("survey_vc.open_external_survey_button", value: "Open Survey", comment: "Button that opens an external survey in the browser"), action: openExternalSurvey)
        }
    }

    private var prompt: some View {
        Text(question.content.labelText)
            .font(.body.bold())
    }
}

/// A tappable option with a trailing checkmark when selected.
private struct CheckmarkRow: View {
    let title: String
    let isChecked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(Color.primary)
                Spacer()
                if isChecked {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .accessibilityAddTraits(isChecked ? .isSelected : [])
    }
}
