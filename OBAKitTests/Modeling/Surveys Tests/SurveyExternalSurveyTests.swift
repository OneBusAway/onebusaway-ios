//
//  SurveyExternalSurveyTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
@testable import OBAKitCore

/// Tests for `Survey.isExternalSurvey`, which keys off the hero question
/// (the question at `position == 1`).
@MainActor
@Suite(.serialized)
final class SurveyExternalSurveyTests {

    // Positive: the hero question is an external survey.
    @Test func `Is external survey when hero question is external returns true`() {
        let hero = SurveysTestHelpers.makeSurveyQuestion(
            position: 1,
            type: .externalSurvey,
            url: "https://example.com/survey"
        )
        let survey = SurveysTestHelpers.makeSurvey(questions: [hero])

        #expect(survey.isExternalSurvey)
    }

    // Negative: the hero question exists but is an in-app question type.
    @Test func `Is external survey when hero question is not external returns false`() {
        let hero = SurveysTestHelpers.makeSurveyQuestion(
            position: 1,
            type: .radio,
            options: ["Yes", "No"]
        )
        let survey = SurveysTestHelpers.makeSurvey(questions: [hero])

        #expect(!survey.isExternalSurvey)
    }

    // Nil along the line: questions exist but none is at position 1, so
    // `heroQuestion` is nil and the optional chain yields false. Using a
    // non-empty list (with an external question at a non-hero position) locks
    // in the `position == 1` lookup that `isExternalSurvey` depends on, rather
    // than only exercising the empty-array path.
    @Test func `Is external survey when no hero question returns false`() {
        let nonHero = SurveysTestHelpers.makeSurveyQuestion(
            position: 2,
            type: .externalSurvey,
            url: "https://example.com/survey"
        )
        let survey = SurveysTestHelpers.makeSurvey(questions: [nonHero])

        #expect(survey.heroQuestion == nil)
        #expect(!survey.isExternalSurvey)
    }
}
