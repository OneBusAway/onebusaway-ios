//
//  MockExternalSurveyURLBuilder.swift
//  OBAKitTests
//
//  Created by Mohamed Sliem on 18/02/2026.
//

import OBAKitCore

final class MockExternalSurveyURLBuilder: ExternalSurveyURLBuilderProtocol {
    var urlToReturn: URL? = URL(string: "https://oba.com/survey")
    var buildURLCallCount = 0

    func buildURL(for survey: Survey, stop: Stop?) -> URL? {
        buildURLCallCount += 1
        return urlToReturn
    }
}
