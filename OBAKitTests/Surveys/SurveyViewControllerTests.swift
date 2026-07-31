//
//  SurveyViewControllerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Eureka
import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Covers the Eureka submit-row affordance driven by `$isSubmitting` (#1169 item 3):
/// disable + "Submitting…" title while in flight, restore on idle, Cancel stays enabled.
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

    private func submitRow(_ controller: SurveyViewController) throws -> ButtonRow {
        try #require(controller.form.rowBy(tag: "submit") as? ButtonRow)
    }

    // Titles use the English `value:` fallbacks from SurveyViewController — OBALoc is
    // defined in both OBAKit and OBAKitCore, so calling it from a dual-import test
    // target is ambiguous under `@testable`.
    private let submitTitle = "Submit Survey"
    private let submittingTitle = "Submitting…"

    /// After load, the sink fires with `isSubmitting == false`: idle title, enabled submit,
    /// Cancel (nav close) still enabled.
    @Test func `Submit row starts idle with Cancel enabled`() throws {
        let controller = makeLoadedController()
        let row = try submitRow(controller)

        #expect(row.title == submitTitle)
        #expect(!row.isDisabled)
        #expect(controller.navigationItem.leftBarButtonItem?.isEnabled == true)
    }

    /// In-flight: submit disables and swaps to "Submitting…"; Cancel must stay tappable so
    /// a hung submit can still be dismissed (matches modal-sheet convention in the comment).
    @Test func `Update submit row disables and retitles while submitting`() throws {
        let controller = makeLoadedController()
        controller.updateSubmitRow(isSubmitting: true)

        let row = try submitRow(controller)
        #expect(row.title == submittingTitle)
        #expect(row.isDisabled)
        #expect(controller.navigationItem.leftBarButtonItem?.isEnabled == true)
    }

    /// Leaving the in-flight state restores the idle title and re-enables submit without
    /// touching Cancel.
    @Test func `Update submit row restores idle state after submitting`() throws {
        let controller = makeLoadedController()
        controller.updateSubmitRow(isSubmitting: true)
        controller.updateSubmitRow(isSubmitting: false)

        let row = try submitRow(controller)
        #expect(row.title == submitTitle)
        #expect(!row.isDisabled)
        #expect(controller.navigationItem.leftBarButtonItem?.isEnabled == true)
    }
}
