//
//  MockSurveyPrioritizer.swift
//  OBAKitTests
//
//  Created by Mohamed Sliem on 18/02/2026.
//

import OBAKitCore

final class MockSurveyPrioritizer: SurveyPrioritizing {
    var surveyStore: SurveyPreferencesStore = SurveyPreferencesStoreMock()
    var nextSurveyIndexReturnValue: Int = 0
    var nextSurveyIndexCallCount: Int = 0

    func nextSurveyIndex(_ surveys: [Survey], visibleOnStop: Bool, stop: Stop?) -> Int {
        nextSurveyIndexCallCount += 1
        return nextSurveyIndexReturnValue
    }
}
