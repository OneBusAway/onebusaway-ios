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
@MainActor
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

    // Nil along the line: questions exist but none is at position 1, so
    // `heroQuestion` is nil and the optional chain yields false. Using a
    // non-empty list (with an external question at a non-hero position) locks
    // in the `position == 1` lookup that `isExternalSurvey` depends on, rather
    // than only exercising the empty-array path.
    func test_isExternalSurvey_whenNoHeroQuestion_returnsFalse() {
        let nonHero = SurveysTestHelpers.makeSurveyQuestion(
            position: 2,
            type: .externalSurvey,
            url: "https://example.com/survey"
        )
        let survey = SurveysTestHelpers.makeSurvey(questions: [nonHero])

        expect(survey.heroQuestion).to(beNil())
        expect(survey.isExternalSurvey).to(beFalse())
    }
}
