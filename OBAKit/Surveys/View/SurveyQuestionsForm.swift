//
//  SurveyQuestionsForm.swift
//  OBAKit
//
//  Created by Mohamed Sliem on 30/12/2025.
//

import SwiftUI
import OBAKitCore

struct SurveyQuestionsForm: View {

    @Environment(\.dismiss) private var dismiss

    @Bindable var viewModel: SurveysViewModel

    var onDismiss: (() -> Void)?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    surveyStudyInfo
                    questionsList
                    submitButton
                }

            }
            .overlay {
                loadingView
            }
            .disabled(viewModel.isLoading)
            .background(Color(uiColor: ThemeColors.shared.groupedTableBackground))
            .toast(toast: viewModel.toast, isPresented: $viewModel.showToastMessage)
            .toolbar {
                closeButton
                answeredQuestionProgress
                submitToolbarButton
            }
            .onChange(of: viewModel.showFullSurveyQuestions) { _, isShown in
                if isShown == false {
                    dismiss()
                }
            }
        }
        .onDisappear {
            viewModel.onAction(.dismissFullQuestionsForm)
            onDismiss?()
        }
    }

    @ViewBuilder
    private var surveyStudyInfo: some View {
        if let study = viewModel.study {
            VStack(alignment: .leading, spacing: 12) {
                Text(study.name)
                    .font(.headline)
                    .fontWeight(.bold)
                    .lineLimit(2)
                    .lineSpacing(4)

                Text(study.description ?? "")
                    .font(.footnote)
                    .fontWeight(.medium)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
    }

    @ToolbarContentBuilder
    private var closeButton: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                viewModel.onAction(.onCloseQuestionsForm)
            } label: {
                Image(systemName: "xmark")
                    .resizable()
                    .fontWeight(.bold)
                    .frame(width: 14, height: 14)
                    .foregroundStyle(Color(uiColor: UIColor.label))
            }
            .buttonStyle(.plain)
        }
    }

    @ToolbarContentBuilder
    private var submitToolbarButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                viewModel.onAction(.onSubmitQuestions)
            } label: {
                Text(Strings.submit)
                    .font(.body)
                    .fontWeight(.bold)
                    .foregroundStyle(Color(uiColor: ThemeColors.shared.brand))
            }
        }
    }

    private var questionsList: some View {
        VStack(spacing: 18) {
            ForEach(viewModel.questions, id: \.id) { question in
                if question.content.type == .label {
                    SurveyLabelView(textContent: "\(question.position). \(question.content.labelText)")
                } else {
                    let showError = viewModel.incompleteQuestionIDs.contains(question.id)
                    SurveyQuestionView(
                        question: question,
                        isHeroQuestion: false,
                        showError: showError
                    ) { answer in
                        viewModel.onAction(.onUpdateQuestion(answer: answer, id: question.id))
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
    }

    private var submitButton: some View {
        Button {
            viewModel.onAction(.onSubmitQuestions)
        } label: {
            submitButtonLabel
        }
    }

    @ViewBuilder
    private var submitButtonLabel: some View {
        Group {
            if #available(iOS 26.0, *) {
                submitButtonLabelText
                    .glassEffect(
                        .regular
                            .tint(Color(uiColor: ThemeColors.shared.brand))
                            .interactive()
                    )
            } else {
                submitButtonLabelText
                    .background(Color(uiColor: ThemeColors.shared.brand))
            }
        }
        .clipShape(.rect(cornerRadius: 8))
        .padding(.horizontal, 16)
    }

    private var submitButtonLabelText: some View {
        Text(Strings.submit)
            .font(.body)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)

    }

    @ViewBuilder
    private var loadingView: some View {
        if viewModel.isLoading {
            Rectangle()
                .fill(Color(uiColor: ThemeColors.shared.gray).opacity(0.4))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    ProgressView()
                        .scaleEffect(1.5)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    @ToolbarContentBuilder
    private var answeredQuestionProgress: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            let value = viewModel.answeredQuestionCount
            let total = viewModel.answerableQuestionCount

            ProgressView("(\(value) / \(total))", value: Double(value), total: Double(total))
                .progressViewStyle(.linear)
                .padding(.horizontal, 16)
        }
    }
}
