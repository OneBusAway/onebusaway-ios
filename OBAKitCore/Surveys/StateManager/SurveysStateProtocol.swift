//
//  SurveysStateProtocol.swift
//  OBAKitCore
//
//  Created by Mohamed Sliem on 28/11/2025.
//

import Foundation

public protocol SurveysStateProtocol {

    var surveyStore: SurveyPreferencesStore { get set }

    func shouldShowSurvey() -> Bool

    func setNextReminderDate()

    func setSurveyCompleted(_ surveyID: Int)

    func setSurveySkipped(_ surveyID: Int)

}
