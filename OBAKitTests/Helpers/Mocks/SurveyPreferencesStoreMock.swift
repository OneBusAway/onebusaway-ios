//
//  SurveyPreferencesStoreMock.swift
//  OBAKitTests
//
//  Created by Mohamed Sliem on 09/12/2025.
//

import Foundation
import OBAKitCore

class SurveyPreferencesStoreMock: NSObject, SurveyPreferencesStore {

    var appLaunch: Int = 0

    var completedSurveys: Set<Int> {
        return preferences.completedSurveyIDs
    }

    var skippedSurveys: Set<Int> {
        return preferences.skippedSurveyIDs
    }

    var userSurveyId: String = ""

    private var preferences: SurveyPreferences = .init()

    private var response: SurveySubmissionResponse = .init(id: "", updatePath: "", userIdentifier: "")

    func setSurveyPreferences(_ preferences: SurveyPreferences) {
        self.preferences = preferences
    }

    func surveyPreferences() -> SurveyPreferences {
        return preferences
    }

    func getSurveyResponse() -> SurveySubmissionResponse? {
        return response
    }

    func setSurveyResponse(_ submissionResponse: SurveySubmissionResponse) {
        self.response = submissionResponse
    }

    func setAppLaunchCount(_ count: Int) {
        self.appLaunch = count
    }

}
