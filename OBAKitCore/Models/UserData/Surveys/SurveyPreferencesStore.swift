//
//  SurveyPreferencesStore.swift
//  OBAKitCore
//
//  Created by Mohamed Sliem on 28/11/2025.
//

import Foundation

public protocol SurveyPreferencesStore: NSObjectProtocol {

    var appLaunch: Int { get }

    var completedSurveys: Set<Int> { get }

    var skippedSurveys: Set<Int> { get }

    var userSurveyId: String { get }

    func setSurveyPreferences(_ preferences: SurveyPreferences)

    func surveyPreferences() -> SurveyPreferences

    func getSurveyResponse() -> SurveySubmissionResponse?

    func setSurveyResponse(_ submissionResponse: SurveySubmissionResponse)

}
