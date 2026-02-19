//
//  MockSurveyStateManager.swift
//  OBAKitTests
//
//  Created by Mohamed Sliem on 18/02/2026.
//

import OBAKitCore

final class MockSurveyStateManager: SurveyStateProtocol {
    var surveyStore: SurveyPreferencesStore = SurveyPreferencesStoreMock()
    var shouldShowSurveyReturnValue = true

    var setSurveyCompletedCallCount = 0
    var lastCompletedSurveyID: Int?

    var setSurveySkippedCallCount = 0
    var lastSkippedSurveyID: Int?

    var setNextReminderDateCallCount = 0

    func shouldShowSurvey() -> Bool { shouldShowSurveyReturnValue }

    func setNextReminderDate() {
        setNextReminderDateCallCount += 1
    }

    func setSurveyCompleted(_ surveyID: Int) {
        setSurveyCompletedCallCount += 1
        lastCompletedSurveyID = surveyID
    }

    func setSurveySkipped(_ surveyID: Int) {
        setSurveySkippedCallCount += 1
        lastSkippedSurveyID = surveyID
    }
}
