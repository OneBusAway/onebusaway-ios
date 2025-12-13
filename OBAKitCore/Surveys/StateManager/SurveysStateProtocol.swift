//
//  SurveysStateProtocol.swift
//  OBAKitCore
//
//  Created by Mohamed Sliem on 28/11/2025.
//

import Foundation

protocol SurveysStateProtocol {

    func shouldShowSurvey() -> Bool

    func setNextReminderDate()

    func setSurveyCompleted(_ surveyID: Int)

    func setSurveySkipped(_ surveyID: Int)

}
