//
//  SurveyViewControllerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Covers the submit affordance driven by `isSubmitting` (#1169 item 3):
/// "Submitting…" while in flight, idle title otherwise, Cancel stays enabled.
/// The disabling itself is `SurveyView`'s `.disabled(viewModel.isSubmitting)`.
@Suite(.serialized)
@MainActor
final class SurveyViewControllerTests: OBATestCase {

    private var surveyService: SurveyService!
    private var dataStore: UserDefaultsStore!

    override init() async throws {
        try await super.init()
        dataStore = UserDefaultsStore(userDefaults: userDefaults)
        surveyService = SurveyService(apiService: nil, userDataStore: dataStore)
    }

    private func makeLoadedController() -> SurveyViewController {
        let survey = SurveysTestHelpers.makeSurvey(
            questions: [SurveysTestHelpers.makeSurveyQuestion(id: 1, type: .text)]
        )
        let controller = SurveyViewController(
            viewModel: SurveyViewModel(survey: survey, surveyService: surveyService)
        )
        controller.loadViewIfNeeded()
        return controller
    }

    // Titles use the English `value:` fallbacks from SurveyView — OBALoc is
    // defined in both OBAKit and OBAKitCore, so calling it from a dual-import test
    // target is ambiguous under `@testable`.
    private let submitTitle = "Submit Survey"
    private let submittingTitle = "Submitting…"

    @Test func `Controller is titled after the survey with Cancel enabled`() {
        let controller = makeLoadedController()

        #expect(controller.title == controller.rootView.viewModel.survey.name)
        #expect(controller.navigationItem.leftBarButtonItem?.isEnabled == true)
    }

    @Test func `Submit title reads Submitting while a submit is in flight`() {
        #expect(SurveyView.submitTitle(isSubmitting: false) == submitTitle)
        #expect(SurveyView.submitTitle(isSubmitting: true) == submittingTitle)
    }
}
