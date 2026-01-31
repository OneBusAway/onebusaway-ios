//
//  SurveysAction.swift
//  OBAKit
//
//  Created by Mohamed Sliem on 29/12/2025.
//

enum SurveysAction {

    case onAppear

    // Hero Question
    case updateHeroAnswer(_ answer: SurveyQuestionAnswer)

    case onTapNextHeroQuestion

    // Cancellation actions
    case onCloseSurveyHeroQuestion

    case hideSurveyDismissSheet

    case onRemindLater

    case onSkipSurvey

    case hideToastMessage

    // Questions Form

    case onCloseQuestionsForm

    case onUpdateQuestion(answer: SurveyQuestionAnswer, id: Int)

    case onSubmitQuestions

    case dismissFullQuestionsForm

}
