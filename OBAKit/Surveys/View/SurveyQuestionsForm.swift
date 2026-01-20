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

    @State var viewModel: SurveysViewModel

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
            .background(ThemeColors.shared.groupedTableBackground.toColor())
            .toast(message: viewModel.toastMessage, type: viewModel.toastType, isPresented: $viewModel.showToastMessage)
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
            onDismiss?()
        }
    }

    @ViewBuilder
    private var surveyStudyInfo: some View {
        if viewModel.study != nil {
            VStack(alignment: .leading, spacing: 12) {
                Text(viewModel.study?.name ?? "")
                    .font(.headline)
                    .fontWeight(.bold)
                    .lineLimit(2)
                    .lineSpacing(4)

                Text(viewModel.study?.description ?? "")
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
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .resizable()
                    .fontWeight(.bold)
                    .frame(width: 14, height: 14)
                    .foregroundStyle(UIColor.label.toColor())
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
                    .foregroundStyle(ThemeColors.shared.brand.toColor())
            }
        }
    }

    private var questionsList: some View {
        VStack(spacing: 18) {
            ForEach(viewModel.questions, id: \.id) { question in
                if question.content.type == .label {
                    SurveyLabelView(textContent: "\(question.position). \(question.content.labelText)")
                } else {
                    SurveyQuestionView(
                        question: question,
                        isHeroQuestion: false
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

        if #available(iOS 26.0, *) {
            Text(Strings.submit)
                .font(.body)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .clipShape(.rect(cornerRadius: 8))
                .glassEffect(.regular.tint(ThemeColors.shared.brand.toColor()).interactive())
                .padding(.horizontal, 16)

        } else {
            Text(Strings.submit)
                .font(.body)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(ThemeColors.shared.brand.toColor())
                .clipShape(.rect(cornerRadius: 8))
                .padding(.horizontal, 16)
        }

    }

    @ViewBuilder
    private var loadingView: some View {
        if viewModel.isLoading {
            Rectangle()
                .fill(ThemeColors.shared.gray.toColor().opacity(0.4))
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
