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
import CoreLocation
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try

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

    override func setUp() async throws {
        try await super.setUp()
        dataStore = UserDefaultsStore(userDefaults: userDefaults)
        surveyService = SurveyService(apiService: nil, userDataStore: dataStore)
        orchestrator = SurveyOrchestrator(surveyService: surveyService)
    }

    override func tearDown() async throws {
        orchestrator = nil
        surveyService = nil
        dataStore = nil
        try await super.tearDown()
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

    /// Hero submit with no remaining questions returns `.completed`, marks the
    /// survey completed, and sets the reminder.
    @MainActor
    func test_submitHero_returnsCompletedWhenNoRemainingQuestions() async throws {
        let hero = Self.makeQuestion(id: 1, position: 1)
        let survey = Self.makeSurvey(questions: [hero])
        let (service, _) = Self.buildLiveSurveyService(testName: name, userDataStore: dataStore)
        let liveOrchestrator = SurveyOrchestrator(surveyService: service)

        let outcome = try await liveOrchestrator.submitHero(
            survey: survey, answer: "yes", stopID: "1_TEST", stopLocation: nil
        )

        guard case .completed = outcome else {
            fail("Expected .completed; got \(outcome)")
            return
        }
        let userID = dataStore.surveyUserIdentifier
        expect(self.dataStore.isSurveyCompleted(surveyId: survey.id, userIdentifier: userID)).to(beTrue())
        expect(self.dataStore.nextSurveyReminderDate).toNot(beNil())
    }

    /// Hero submit on a survey with remaining questions returns
    /// `.needsRemainingQuestions(heroResponseID:)`, advances the reminder, but
    /// does NOT mark the survey completed.
    @MainActor
    func test_submitHero_returnsNeedsRemainingWhenFollowupsExist() async throws {
        let hero = Self.makeQuestion(id: 1, position: 1)
        let follow = Self.makeQuestion(id: 2, position: 2, required: false)
        let survey = Self.makeSurvey(questions: [hero, follow])
        let (service, _) = Self.buildLiveSurveyService(testName: name, userDataStore: dataStore)
        let liveOrchestrator = SurveyOrchestrator(surveyService: service)

        let outcome = try await liveOrchestrator.submitHero(
            survey: survey, answer: "yes", stopID: "1_TEST", stopLocation: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)
        )

        switch outcome {
        case .completed:
            fail("Expected .needsRemainingQuestions; got .completed")
        case .needsRemainingQuestions(let heroResponseID):
            expect(heroResponseID).toNot(beEmpty())
        }
        let userID = dataStore.surveyUserIdentifier
        expect(self.dataStore.isSurveyCompleted(surveyId: survey.id, userIdentifier: userID)).to(beFalse())
        expect(self.dataStore.nextSurveyReminderDate).toNot(beNil())
    }

    /// A survey whose only question isn't at `position == 1` has `heroQuestion == nil`.
    /// `submitHero` must throw `.missingHeroQuestion` rather than crash on the force-unwrap
    /// of optional hero data. `Survey` is decoded from the network, so this shape is
    /// defensible.
    @MainActor
    func test_submitHero_throwsMissingHeroQuestionWhenNoPositionOneQuestion() async {
        let follow = Self.makeQuestion(id: 2, position: 2, type: .text)
        let survey = Self.makeSurvey(questions: [follow])
        // Sanity check the fixture: this survey genuinely has no hero.
        expect(survey.heroQuestion).to(beNil())

        do {
            _ = try await orchestrator.submitHero(
                survey: survey, answer: "yes", stopID: nil, stopLocation: nil
            )
            fail("Expected submitHero to throw .missingHeroQuestion")
        } catch let SurveyOrchestrator.OrchestratorError.missingHeroQuestion(surveyID) {
            expect(surveyID) == survey.id
        } catch {
            fail("Expected .missingHeroQuestion; got \(error)")
        }

        // No bookkeeping should advance when the guard fires.
        let userID = dataStore.surveyUserIdentifier
        expect(self.dataStore.isSurveyCompleted(surveyId: survey.id, userIdentifier: userID)).to(beFalse())
        expect(self.dataStore.nextSurveyReminderDate).to(beNil())
    }

    // MARK: - Live SurveyService builder (for happy-path network)

    /// Builds a real `SurveyService` whose `apiService` routes through a
    /// `MockDataLoader` stubbed to return the canned submit response. Used by
    /// the happy-path `submitHero` tests above so we exercise the real network
    /// branch + reminder/mark-completed bookkeeping in one shot.
    private static func buildLiveSurveyService(testName: String, userDataStore: UserDataStore) -> (SurveyService, MockDataLoader) {
        let mockLoader = MockDataLoader(testName: testName)
        let data = try! Data(contentsOf: Bundle(for: SurveyOrchestratorTests.self).url(forResource: "survey_submission_response", withExtension: "json")!)
        mockLoader.mock(data: data) { request in
            request.url?.path.contains("/api/v1/survey_responses") ?? false
        }

        let config = APIServiceConfiguration(
            baseURL: URL(string: "https://api.pugetsound.onebusaway.org/")!,
            apiKey: "org.onebusaway.iphone.test",
            uuid: "test-uuid",
            appVersion: "2018.12.31",
            regionIdentifier: 1,
            surveyBaseURL: URL(string: "https://onebusaway.co")!
        )
        let apiService = RESTAPIService(config, dataLoader: mockLoader)
        let service = SurveyService(apiService: apiService, userDataStore: userDataStore)
        return (service, mockLoader)
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

    // MARK: - lastError accessor

    /// `lastError` is `nil` before any refresh runs. The gate in
    /// `MapViewModel.checkForSurveyPrompt` relies on this so the very first
    /// session check doesn't get short-circuited by a stale value.
    @MainActor
    func test_lastError_isNilBeforeRefresh() {
        expect(self.orchestrator.lastError).to(beNil())
    }

    /// `lastError` proxies the underlying `SurveyService.lastError`. With
    /// `apiService: nil`, `fetchSurveys` records `APIError.surveyServiceNotConfigured`
    /// rather than throwing — this verifies the orchestrator surfaces it so
    /// `MapViewModel.checkForSurveyPrompt` can gate on it.
    @MainActor
    func test_lastError_reflectsUnderlyingService_afterFetchFailure() async {
        expect(self.orchestrator.lastError).to(beNil())

        await orchestrator.refreshSurveys()

        guard let error = orchestrator.lastError as? APIError else {
            fail("Expected APIError; got \(String(describing: orchestrator.lastError))")
            return
        }
        switch error {
        case .surveyServiceNotConfigured:
            break  // expected
        default:
            fail("Expected .surveyServiceNotConfigured; got \(error)")
        }
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
