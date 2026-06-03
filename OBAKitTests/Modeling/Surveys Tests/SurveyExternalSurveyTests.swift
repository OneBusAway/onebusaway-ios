//
//  SurveyExternalSurveyTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
@testable import OBAKitCore

/// Tests for `Survey.isExternalSurvey`, which keys off the hero question
/// (the question at `position == 1`).
final class SurveyExternalSurveyTests: XCTestCase {

    // Positive: the hero question is an external survey.
    func test_isExternalSurvey_whenHeroQuestionIsExternal_returnsTrue() {
        let hero = SurveysTestHelpers.makeSurveyQuestion(
            position: 1,
            type: .externalSurvey,
            url: "https://example.com/survey"
        )
        let survey = SurveysTestHelpers.makeSurvey(questions: [hero])

        expect(survey.isExternalSurvey).to(beTrue())
    }

    // Negative: the hero question exists but is an in-app question type.
    func test_isExternalSurvey_whenHeroQuestionIsNotExternal_returnsFalse() {
        let hero = SurveysTestHelpers.makeSurveyQuestion(
            position: 1,
            type: .radio,
            options: ["Yes", "No"]
        )
        let survey = SurveysTestHelpers.makeSurvey(questions: [hero])

        expect(survey.isExternalSurvey).to(beFalse())
    }

    // Nil along the line: there is no hero question (no question at position 1),
    // so `heroQuestion` is nil and the optional chain yields false.
    func test_isExternalSurvey_whenNoHeroQuestion_returnsFalse() {
        let survey = SurveysTestHelpers.makeSurvey(questions: [])

        expect(survey.heroQuestion).to(beNil())
        expect(survey.isExternalSurvey).to(beFalse())
    }
}
