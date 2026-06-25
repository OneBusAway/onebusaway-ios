//
//  SurveyOrchestrator.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import OBAKitCore

/// Shared façade over `SurveyService`.
///
/// Owns the survey primitives that are identical across screens: eligibility
/// gate, refresh, hero submission + outcome decision, mark-completed,
/// dismiss-with-reminder, and the post-present reminder advance. Held by
/// `MapViewModel` (prompt flow) and `StopViewModel` (inline hero card) so
/// neither VM has to reimplement the bookkeeping. The façade itself carries
/// no per-screen instance state, but `submitHero`, `dismiss`, and
/// `noteReminderAndAdvanceSession` mutate persistent reminder/completion
/// state on `SurveyService` — it is not side-effect free.
@MainActor
final class SurveyOrchestrator {

    /// Outcome of `submitHero(survey:answer:stopID:stopLocation:)`. Tells the
    /// caller whether the survey is fully done or whether the remaining
    /// questions need to be presented in the full survey screen.
    enum HeroSubmissionOutcome {
        case completed
        case needsRemainingQuestions(heroResponseID: String)
    }

    enum OrchestratorError: Error {
        /// `submitHero` was called for a survey whose `heroQuestion` is nil.
        /// Callers guard before calling, but `Survey` is decoded from the
        /// network so the shape is defensible rather than impossible.
        case missingHeroQuestion(surveyID: Int)
    }

    private let surveyService: SurveyService

    nonisolated init(surveyService: SurveyService) {
        self.surveyService = surveyService
    }

    /// Whether a survey should be shown right now (launch-count cooldown,
    /// reminder date, global toggle).
    func isEligible() -> Bool {
        surveyService.shouldShowSurvey()
    }

    /// Refreshes the survey list. Failures are recorded on `lastError` rather
    /// than thrown; callers gate off it when they need to avoid acting on a
    /// stale cached list.
    func refreshSurveys() async {
        await surveyService.fetchSurveys()
    }

    /// The most recent fetch error, or `nil` if the last `refreshSurveys()`
    /// succeeded. Cleared on the next successful refresh, not on a cooldown
    /// skip — so a value here means the *last actual fetch* failed.
    var lastError: Error? {
        surveyService.lastError
    }

    /// Submits the hero question and advances the reminder. On success, either
    /// marks the survey completed (no remaining questions) or returns the
    /// submission ID so the caller can present the rest in the full survey
    /// screen.
    ///
    /// Throws `OrchestratorError.missingHeroQuestion` if `survey.heroQuestion`
    /// is nil. Callers are expected to guard before calling, but the throw
    /// keeps us from crashing on malformed server data.
    func submitHero(
        survey: Survey,
        answer: String,
        stopID: String?,
        stopLocation: CLLocationCoordinate2D?
    ) async throws -> HeroSubmissionOutcome {
        guard let heroQuestion = survey.heroQuestion else {
            throw OrchestratorError.missingHeroQuestion(surveyID: survey.id)
        }

        let heroResponse = SurveyService.createQuestionResponse(question: heroQuestion, answer: answer)

        let submission = try await surveyService.submitHeroQuestion(
            survey: survey,
            heroQuestionResponse: heroResponse,
            stopID: stopID,
            stopLocation: stopLocation
        )

        surveyService.setNextReminderDate()

        if survey.remainingQuestions.isEmpty {
            surveyService.markSurveyCompleted(survey)
            return .completed
        }

        return .needsRemainingQuestions(heroResponseID: submission.id)
    }

    /// User dismissed the survey card. Records the dismissal and pushes the
    /// next reminder out.
    func dismiss(_ survey: Survey) {
        surveyService.dismissSurvey(survey)
        surveyService.setNextReminderDate()
    }

    /// Pushes the next reminder out. Called by the map prompt after a
    /// successful present so the same session doesn't re-prompt.
    func noteReminderAndAdvanceSession() {
        surveyService.setNextReminderDate()
    }

    /// The survey to show on the map right now, or `nil` if none applies.
    func findMapSurvey() -> Survey? {
        surveyService.findSurveyForMap()
    }

    /// The survey to show for the given stop right now, or `nil` if none applies.
    func findStopSurvey(stopID: String, routeIDs: [String]) -> Survey? {
        surveyService.findSurveyForStop(stopID: stopID, routeIDs: routeIDs)
    }
}
