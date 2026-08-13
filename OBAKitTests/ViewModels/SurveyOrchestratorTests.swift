//
//  SurveyOrchestratorTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
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
@Suite(.serialized)
final class SurveyOrchestratorTests: OBATestCase {

    private var surveyService: SurveyService!
    private var dataStore: UserDefaultsStore!
    private var orchestrator: SurveyOrchestrator!

    override init() async throws {
        try await super.init()

        dataStore = UserDefaultsStore(userDefaults: userDefaults)
        surveyService = SurveyService(apiService: nil, userDataStore: dataStore)
        let service = surveyService!
        let defaults = userDefaults!
        orchestrator = await MainActor.run {
            SurveyOrchestrator(
                surveyService: service,
                promptCoordinator: PromptCoordinator(userDefaults: defaults)
            )
        }
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
    @Test @MainActor
    func `Is eligible is false when surveys disabled`() {
        dataStore.isSurveyEnabled = false
        #expect(!self.orchestrator.isEligible())
    }

    /// `alwaysShowSurveysOnStops` opens the gate regardless of launch count / reminder.
    @Test @MainActor
    func `Is eligible is true with always show flag`() {
        dataStore.isSurveyEnabled = true
        dataStore.alwaysShowSurveysOnStops = true
        #expect(self.orchestrator.isEligible())
    }

    // MARK: - submitHero

    /// Without an `apiService`, the submission throws and the orchestrator does
    /// not flip mark-completed or reminder.
    ///
    /// Also pins that a thrown submission does NOT record survey engagement —
    /// `noteSurveyEngaged()` sits after the network call succeeds, so a throw
    /// here must leave the coordinator's review-prompt gate untouched.
    @Test @MainActor
    func `Submit hero throws without API service`() async {
        let hero = Self.makeQuestion(id: 1)
        let survey = Self.makeSurvey(questions: [hero])
        let coordinator = PromptCoordinator(userDefaults: userDefaults)
        let throwingOrchestrator = SurveyOrchestrator(surveyService: surveyService, promptCoordinator: coordinator)

        do {
            _ = try await throwingOrchestrator.submitHero(
                survey: survey, answer: "yes", stopID: "1_TEST", stopLocation: nil
            )
            Issue.record("Expected submitHero to throw without an apiService")
        } catch {
            // Expected — apiService is nil.
        }

        #expect(!self.dataStore.isSurveyCompleted(surveyId: survey.id, userIdentifier: self.dataStore.surveyUserIdentifier))
        #expect(self.dataStore.nextSurveyReminderDate == nil)
        #expect(coordinator.canShowReviewPrompt(), "a failed submission must not start the engagement cooldown")
    }

    /// Hero submit with no remaining questions returns `.completed`, marks the
    /// survey completed, and sets the reminder.
    ///
    /// Also pins that a successful submission is a survey engagement: it must
    /// start the coordinator's 14-day cooldown that gates the review prompt.
    @Test @MainActor
    func `Submit hero returns completed when no remaining questions`() async throws {
        let hero = Self.makeQuestion(id: 1, position: 1)
        let survey = Self.makeSurvey(questions: [hero])
        let (service, _) = Self.buildLiveSurveyService(testName: name, userDataStore: dataStore)
        let coordinator = PromptCoordinator(userDefaults: userDefaults)
        let liveOrchestrator = SurveyOrchestrator(surveyService: service, promptCoordinator: coordinator)

        #expect(coordinator.canShowReviewPrompt())

        let outcome = try await liveOrchestrator.submitHero(
            survey: survey, answer: "yes", stopID: "1_TEST", stopLocation: nil
        )

        guard case .completed = outcome else {
            Issue.record("Expected .completed; got \(outcome)")
            return
        }
        let userID = dataStore.surveyUserIdentifier
        #expect(self.dataStore.isSurveyCompleted(surveyId: survey.id, userIdentifier: userID))
        #expect(self.dataStore.nextSurveyReminderDate != nil)
        #expect(!coordinator.canShowReviewPrompt(), "a successful submission is an engagement and starts the 14-day cooldown")
    }

    /// Hero submit on a survey with remaining questions returns
    /// `.needsRemainingQuestions(heroResponseID:)`, advances the reminder, but
    /// does NOT mark the survey completed.
    ///
    /// Also pins that this outcome is still a survey engagement — it must
    /// start the coordinator's 14-day cooldown just like `.completed` does.
    @Test @MainActor
    func `Submit hero returns needs remaining when followups exist`() async throws {
        let hero = Self.makeQuestion(id: 1, position: 1)
        let follow = Self.makeQuestion(id: 2, position: 2, required: false)
        let survey = Self.makeSurvey(questions: [hero, follow])
        let (service, _) = Self.buildLiveSurveyService(testName: name, userDataStore: dataStore)
        let coordinator = PromptCoordinator(userDefaults: userDefaults)
        let liveOrchestrator = SurveyOrchestrator(surveyService: service, promptCoordinator: coordinator)

        #expect(coordinator.canShowReviewPrompt())

        let outcome = try await liveOrchestrator.submitHero(
            survey: survey, answer: "yes", stopID: "1_TEST", stopLocation: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)
        )

        switch outcome {
        case .completed:
            Issue.record("Expected .needsRemainingQuestions; got .completed")
        case .needsRemainingQuestions(let heroResponseID):
            #expect(!heroResponseID.isEmpty)
        }
        let userID = dataStore.surveyUserIdentifier
        #expect(!self.dataStore.isSurveyCompleted(surveyId: survey.id, userIdentifier: userID))
        #expect(self.dataStore.nextSurveyReminderDate != nil)
        #expect(!coordinator.canShowReviewPrompt(), "a successful submission is an engagement and starts the 14-day cooldown")
    }

    /// A survey whose only question isn't at `position == 1` has `heroQuestion == nil`.
    /// `submitHero` must throw `.missingHeroQuestion` rather than crash on the force-unwrap
    /// of optional hero data. `Survey` is decoded from the network, so this shape is
    /// defensible.
    @Test @MainActor
    func `Submit hero throws missing hero question when no position one question`() async {
        let follow = Self.makeQuestion(id: 2, position: 2, type: .text)
        let survey = Self.makeSurvey(questions: [follow])
        // Sanity check the fixture: this survey genuinely has no hero.
        #expect(survey.heroQuestion == nil)
        let coordinator = PromptCoordinator(userDefaults: userDefaults)
        let throwingOrchestrator = SurveyOrchestrator(surveyService: surveyService, promptCoordinator: coordinator)

        do {
            _ = try await throwingOrchestrator.submitHero(
                survey: survey, answer: "yes", stopID: nil, stopLocation: nil
            )
            Issue.record("Expected submitHero to throw .missingHeroQuestion")
        } catch let SurveyOrchestrator.OrchestratorError.missingHeroQuestion(surveyID) {
            #expect(surveyID == survey.id)
        } catch {
            Issue.record("Expected .missingHeroQuestion; got \(error)")
        }

        // No bookkeeping should advance when the guard fires.
        let userID = dataStore.surveyUserIdentifier
        #expect(!self.dataStore.isSurveyCompleted(surveyId: survey.id, userIdentifier: userID))
        #expect(self.dataStore.nextSurveyReminderDate == nil)
        #expect(coordinator.canShowReviewPrompt(), "a guard-clause throw must not start the engagement cooldown")
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
    @Test @MainActor
    func `Dismiss sets reminder and marks completed`() {
        let survey = Self.makeSurvey(questions: [Self.makeQuestion(id: 1)])
        let userID = dataStore.surveyUserIdentifier
        #expect(self.dataStore.nextSurveyReminderDate == nil)

        orchestrator.dismiss(survey)

        #expect(self.dataStore.nextSurveyReminderDate != nil)
        #expect(self.dataStore.isSurveyCompleted(surveyId: survey.id, userIdentifier: userID))
    }

    /// `dismiss(_:)` is a survey engagement, so it must start the coordinator's
    /// 14-day cooldown that gates the review prompt — otherwise a rider who
    /// just interacted with a survey card could be asked for a review in the
    /// same sitting.
    @Test @MainActor
    func `Dismiss records survey engagement`() {
        let coordinator = PromptCoordinator(userDefaults: userDefaults)
        let orchestrator = SurveyOrchestrator(
            surveyService: surveyService,
            promptCoordinator: coordinator
        )

        #expect(coordinator.canShowReviewPrompt())
        orchestrator.dismiss(Self.makeSurvey(questions: [Self.makeQuestion(id: 1)]))
        #expect(!coordinator.canShowReviewPrompt(), "engagement starts the 14-day cooldown")
    }

    // MARK: - lastError accessor

    /// `lastError` is `nil` before any refresh runs. The gate in
    /// `MapViewModel.checkForSurveyPrompt` relies on this so the very first
    /// session check doesn't get short-circuited by a stale value.
    @Test @MainActor
    func `Last error is nil before refresh`() {
        #expect(self.orchestrator.lastError == nil)
    }

    /// `lastError` proxies the underlying `SurveyService.lastError`. With
    /// `apiService: nil`, `fetchSurveys` records `APIError.surveyServiceNotConfigured`
    /// rather than throwing — this verifies the orchestrator surfaces it so
    /// `MapViewModel.checkForSurveyPrompt` can gate on it.
    @Test @MainActor
    func `Last error reflects underlying service after fetch failure`() async {
        #expect(self.orchestrator.lastError == nil)

        await orchestrator.refreshSurveys()

        guard let error = orchestrator.lastError as? APIError else {
            Issue.record("Expected APIError; got \(String(describing: orchestrator.lastError))")
            return
        }
        switch error {
        case .surveyServiceNotConfigured:
            break  // expected
        default:
            Issue.record("Expected .surveyServiceNotConfigured; got \(error)")
        }
    }

    // MARK: - noteReminderAndAdvanceSession

    /// `noteReminderAndAdvanceSession()` advances the reminder by ~3 days.
    @Test @MainActor
    func `Note reminder and advance session sets reminder about three days out`() {
        let before = Date()
        orchestrator.noteReminderAndAdvanceSession()
        let after = Date()

        guard let reminder = dataStore.nextSurveyReminderDate else {
            Issue.record("nextSurveyReminderDate not set")
            return
        }
        #expect(reminder >= before.addingTimeInterval(3 * 86400 - 60))
        #expect(reminder <= after.addingTimeInterval(3 * 86400 + 60))
    }
}
