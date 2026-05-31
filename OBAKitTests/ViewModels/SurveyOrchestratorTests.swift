//
//  SurveyOrchestratorTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
@testable import OBAKit
@testable import OBAKitCore

/// Tests for `SurveyOrchestrator`. Covers the shared primitives once so the
/// `MapViewModel` / `StopViewModel` survey tests can stay narrow.
///
/// Network paths are exercised against `SurveyService(apiService: nil)` — any
/// call that reaches the network throws, which lets us positively assert that
/// the caller's guards executed before the network branch.
class SurveyOrchestratorTests: OBATestCase {

    private var surveyService: SurveyService!
    private var dataStore: UserDefaultsStore!
    private var orchestrator: SurveyOrchestrator!

    override func setUp() {
        super.setUp()
        dataStore = UserDefaultsStore(userDefaults: userDefaults)
        surveyService = SurveyService(apiService: nil, userDataStore: dataStore)
        orchestrator = SurveyOrchestrator(surveyService: surveyService)
    }

    override func tearDown() {
        orchestrator = nil
        surveyService = nil
        dataStore = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private static func makeQuestion(
        id: Int,
        position: Int = 1,
        required: Bool = true,
        type: QuestionType = .text
    ) -> SurveyQuestion {
        SurveyQuestion(
            id: id,
            position: position,
            required: required,
            content: QuestionContent(labelText: "q\(id)", type: type)
        )
    }

    private static func makeSurvey(questions: [SurveyQuestion]) -> Survey {
        Survey(
            id: 99,
            name: "Orchestrator Test Survey",
            createdAt: Date(),
            updatedAt: Date(),
            showOnMap: false,
            showOnStops: true,
            startDate: nil,
            endDate: nil,
            visibleStopsList: nil,
            visibleRoutesList: nil,
            allowsMultipleResponses: false,
            alwaysVisible: true,
            study: Study(id: 1, name: "Study", description: "desc"),
            questions: questions
        )
    }

    // MARK: - isEligible

    /// When the global toggle is off, the gate is closed.
    @MainActor
    func test_isEligible_isFalseWhenSurveysDisabled() {
        dataStore.isSurveyEnabled = false
        expect(self.orchestrator.isEligible()).to(beFalse())
    }

    /// `alwaysShowSurveysOnStops` opens the gate regardless of launch count / reminder.
    @MainActor
    func test_isEligible_isTrueWithAlwaysShowFlag() {
        dataStore.isSurveyEnabled = true
        dataStore.alwaysShowSurveysOnStops = true
        expect(self.orchestrator.isEligible()).to(beTrue())
    }

    // MARK: - submitHero

    /// Without an `apiService`, the submission throws and the orchestrator does
    /// not flip mark-completed or reminder.
    @MainActor
    func test_submitHero_throwsWithoutAPIService() async {
        let hero = Self.makeQuestion(id: 1)
        let survey = Self.makeSurvey(questions: [hero])

        do {
            _ = try await orchestrator.submitHero(
                survey: survey, answer: "yes", stopID: "1_TEST", stopLocation: nil
            )
            fail("Expected submitHero to throw without an apiService")
        } catch {
            // Expected — apiService is nil.
        }

        expect(self.dataStore.isSurveyCompleted(surveyId: survey.id, userIdentifier: self.dataStore.surveyUserIdentifier)).to(beFalse())
        expect(self.dataStore.nextSurveyReminderDate).to(beNil())
    }

    // MARK: - dismiss

    /// `dismiss(_:)` sets the reminder date. The dismissal is recorded via
    /// `markSurveyCompleted` (which `SurveyService.dismissSurvey` calls).
    @MainActor
    func test_dismiss_setsReminderAndMarksCompleted() {
        let survey = Self.makeSurvey(questions: [Self.makeQuestion(id: 1)])
        let userID = dataStore.surveyUserIdentifier
        expect(self.dataStore.nextSurveyReminderDate).to(beNil())

        orchestrator.dismiss(survey)

        expect(self.dataStore.nextSurveyReminderDate).toNot(beNil())
        expect(self.dataStore.isSurveyCompleted(surveyId: survey.id, userIdentifier: userID)).to(beTrue())
    }

    // MARK: - markCompleted

    /// `markCompleted(_:)` records the survey as done for the current user.
    @MainActor
    func test_markCompleted_recordsForCurrentUser() {
        let survey = Self.makeSurvey(questions: [Self.makeQuestion(id: 1)])
        let userID = dataStore.surveyUserIdentifier

        orchestrator.markCompleted(survey)

        expect(self.dataStore.isSurveyCompleted(surveyId: survey.id, userIdentifier: userID)).to(beTrue())
    }

    // MARK: - noteReminderAndAdvanceSession

    /// `noteReminderAndAdvanceSession()` advances the reminder by ~3 days.
    @MainActor
    func test_noteReminderAndAdvanceSession_setsReminderAboutThreeDaysOut() {
        let before = Date()
        orchestrator.noteReminderAndAdvanceSession()
        let after = Date()

        guard let reminder = dataStore.nextSurveyReminderDate else {
            fail("nextSurveyReminderDate not set")
            return
        }
        expect(reminder).to(beGreaterThanOrEqualTo(before.addingTimeInterval(3 * 86400 - 60)))
        expect(reminder).to(beLessThanOrEqualTo(after.addingTimeInterval(3 * 86400 + 60)))
    }
}
