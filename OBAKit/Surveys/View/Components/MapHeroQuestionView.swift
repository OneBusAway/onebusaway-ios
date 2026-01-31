//
//  MapHeroQuestionView.swift
//  OBAKit
//
//  Created by Mohamed Sliem on 25/01/2026.
//

import SwiftUI
import OBAKitCore

struct MapHeroQuestionView<ViewModel: SurveysViewModel>: View {

    let viewModel: ViewModel

    var body: some View {
        if let question = viewModel.heroQuestion {
            heroQuestionView(question)
        }
    }

    @ViewBuilder
    private func heroQuestionView(_ heroQuestion: SurveyQuestion) -> some View {
        if heroQuestion.content.type == .externalSurvey {
            ExternalSurveyView(question: heroQuestion) {
                viewModel.onAction(.onCloseSurveyHeroQuestion)
            } onSubmitAction: {
                viewModel.onAction(.onTapNextHeroQuestion)
            }
        } else {
            SurveyQuestionView(
                question: heroQuestion,
                isHeroQuestion: true
            ) { answer in
               viewModel.onAction(.updateHeroAnswer(answer))
            } onCloseAction: {
               viewModel.onAction(.onCloseSurveyHeroQuestion)
            } onSubmitAction: {
               viewModel.onAction(.onTapNextHeroQuestion)
            }
        }
    }

}
