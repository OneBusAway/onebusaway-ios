//
//  SurveyViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Combine
import CoreLocation
import Foundation
import OBAKitCore

/// Shared ViewModel for `SurveyViewController`.
///
/// Owns survey answer state, validation, and the two-stage submission flow
/// (hero question first, additional questions second). The VC keeps only
/// Eureka form layout and alert presentation.
@MainActor
final class SurveyViewModel: ObservableObject {

    enum SubmissionError: Error {
        /// User-recoverable: a required answer is missing.
        case validationFailed
        /// Programmer/data error: the survey itself has no answerable hero
        /// question on the fresh path. Distinct from `.validationFailed` so
        /// the VC can route to a "survey unavailable" alert + log line rather
        /// than blaming the user.
        case malformedSurveyData
        /// Anything thrown during the hero/additional submit (encoding,
        /// `APIError.surveyServiceNotConfigured`, decoding, network, …).
        /// Named `submissionFailed` rather than `network` because not every
        /// underlying failure is a transport issue.
        case submissionFailed(Error)
    }

    // MARK: - Public Inputs (VC reads for form layout)

    let survey: Survey

    /// The set of questions the form should render. When a hero response is already
    /// submitted (retry path), the hero question is skipped.
    var questionsToShow: [SurveyQuestion] {
        heroResponseID != nil ? survey.remainingQuestions : survey.questions
    }

    // MARK: - Outputs

    /// Emits the outcome of each `submit()` call.
    var submissionResult: AnyPublisher<Result<Void, SubmissionError>, Never> {
        submissionResultSubject.eraseToAnyPublisher()
    }
    private let submissionResultSubject = PassthroughSubject<Result<Void, SubmissionError>, Never>()

    /// `true` while a submit is in flight. Mirrors `submitInFlight` for VC binding so the
    /// submit button can be disabled and a spinner shown — without it, the in-flight guard
    /// silently drops a second tap on a slow network and the user sees nothing happen.
    @Published private(set) var isSubmitting: Bool = false

    // MARK: - Private State

    private let surveyService: SurveyService
    private let stop: Stop?
    private let stopID: String?
    private let stopLocation: CLLocationCoordinate2D?

    private lazy var externalSurveyLauncher = ExternalSurveyLauncher(surveyService: surveyService)

    private(set) var heroResponseID: String?
    private var responses: [SurveyQuestionResponse] = []
    private var checkboxSelections: [Int: Set<String>] = [:]
    private var submitInFlight = false

    // MARK: - Init

    init(
        survey: Survey,
        surveyService: SurveyService,
        stop: Stop? = nil,
        stopID: String? = nil,
        stopLocation: CLLocationCoordinate2D? = nil,
        heroResponseID: String? = nil
    ) {
        self.survey = survey
        self.surveyService = surveyService
        self.stop = stop
        self.stopID = stopID
        self.stopLocation = stopLocation
        self.heroResponseID = heroResponseID
    }

    // MARK: - Intent

    /// Replaces any prior response for `question` with the given answer.
    func updateAnswer(for question: SurveyQuestion, answer: String) {
        responses.removeAll { $0.questionId == question.id }
        responses.append(SurveyService.createQuestionResponse(question: question, answer: answer))
    }

    /// Updates checkbox selection state and stores the JSON-encoded array as the answer.
    ///
    /// `formatCheckboxAnswer` only encodes a `[String]` via `JSONEncoder`, which cannot
    /// realistically fail. The `try!` is a "we'd rather crash than silently desync" choice:
    /// if encoding ever did fail, a `try?` would leave the UI showing a checked row whose
    /// answer never landed in `responses`, and the user would submit a half-empty survey
    /// without knowing.
    func toggleCheckbox(option: String, selected: Bool, for question: SurveyQuestion) {
        if selected {
            checkboxSelections[question.id, default: []].insert(option)
        } else {
            checkboxSelections[question.id, default: []].remove(option)
        }

        let selections = Array(checkboxSelections[question.id, default: []])
        // swiftlint:disable:next force_try
        let jsonAnswer = try! SurveyService.formatCheckboxAnswer(selections)
        updateAnswer(for: question, answer: jsonAnswer)
    }

    /// User cancelled — reschedule the survey for later.
    func cancel() {
        surveyService.markSurveyForLater(survey)
        surveyService.setNextReminderDate()
    }

    /// Builds the external-survey URL and attempts to open it. The launcher marks the
    /// survey completed only when the system actually opens the URL.
    func launchExternalSurvey(onSuccess: @escaping () -> Void, onFailure: @escaping () -> Void) {
        externalSurveyLauncher.launch(
            survey: survey,
            stop: stop,
            onSuccess: onSuccess,
            onFailure: onFailure
        )
    }

    /// Validates required answers and runs the two-stage submission. Emits the outcome
    /// on `submissionResult`.
    func submit() async {
        guard !submitInFlight else { return }

        guard validateResponses() else {
            submissionResultSubject.send(.failure(.validationFailed))
            return
        }

        submitInFlight = true
        isSubmitting = true
        defer {
            submitInFlight = false
            isSubmitting = false
        }

        do {
            if let heroResponseID = heroResponseID {
                let additional = responses.filter { $0.questionId != survey.heroQuestion?.id }
                _ = try await surveyService.submitAdditionalQuestions(
                    responseID: heroResponseID,
                    additionalResponses: additional
                )
            } else {
                guard let heroQuestion = survey.heroQuestion,
                      let heroResponse = responses.first(where: { $0.questionId == heroQuestion.id }) else {
                    submissionResultSubject.send(.failure(.malformedSurveyData))
                    return
                }

                let submissionResponse = try await surveyService.submitHeroQuestion(
                    survey: survey,
                    heroQuestionResponse: heroResponse,
                    stopID: stopID,
                    stopLocation: stopLocation
                )

                // Save so a retry skips the hero submit.
                self.heroResponseID = submissionResponse.id

                let remainingResponses = responses.filter { $0.questionId != heroQuestion.id }
                if !remainingResponses.isEmpty {
                    _ = try await surveyService.submitAdditionalQuestions(
                        responseID: submissionResponse.id,
                        additionalResponses: remainingResponses
                    )
                }
            }

            surveyService.markSurveyCompleted(survey)
            submissionResultSubject.send(.success(()))
        } catch {
            Logger.error("Survey \(survey.id) submission failed: \(error)")
            submissionResultSubject.send(.failure(.submissionFailed(error)))
        }
    }

    // MARK: - Validation

    private func validateResponses() -> Bool {
        let answeredQuestionIDs = Set(responses.map { $0.questionId })
        return questionsToShow
            // External-survey questions are answered out-of-app (tapping "Open
            // Survey" launches the URL and dismisses this form), so they can
            // never be satisfied in-form. Exclude them from required checks.
            .filter { $0.required && $0.content.type != .externalSurvey }
            .allSatisfy { answeredQuestionIDs.contains($0.id) }
    }
}
