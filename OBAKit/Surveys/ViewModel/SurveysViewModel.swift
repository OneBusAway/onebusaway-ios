//
//  SurveysViewModel.swift
//  OBAKit
//
//  Created by Mohamed Sliem on 28/12/2025.
//

import Foundation
import Observation
import OBAKitCore

@Observable
final public class SurveysViewModel {

    /// Dependancies
    private let service: SurveyServiceProtocol
    private let prioritizer: SurveyPrioritizing
    private var stateManager: SurveyStateProtocol
    private let externalLinkBuilder: ExternalSurveyURLBuilder

    /// Toast Message
    public var showToastMessage: Bool = false
    public var toastMessage: String = ""
    public var toastType: Toast.ToastType = .success

    /// Error State
    public var error: Error?

    /// Loading State
    public var isLoading: Bool = false

    /// Surveys Show/Hide  state variables
    public var showHeroQuestion: Bool = false
    public var showFullSurveyQuestions: Bool = false
    public var showSurveyDismissSheet: Bool = false
    public var openExternalSurvey: Bool = false

    /// Survey Study
    public var study: Study?

    /// Hero Question Content
    public var heroQuestion: SurveyQuestion?

    public var heroQuestionAnswer: SurveyQuestionAnswer?

    /// Surveys full question
    public var questions: [SurveyQuestion] = []

    public var incompleteQuestionIDs: [Int] = []

    public var externalSurveyURL: URL?

    /// Full survey questions answers  state
    public var answerableQuestionCount: Int {
        questions.filter { $0.content.type != .label }.count
    }

    public var answeredQuestionCount: Int {
        questionsAnswers.filter { !$0.value.stringValue.isEmpty }.count
    }

    private var questionsAnswers: [Int: SurveyQuestionAnswer] = [:]

    private var stop: Stop?

    private var survey: Survey?

    private let stopContext: Bool

    private var activeSurvey: Bool {
        !questions.isEmpty || heroQuestion != nil
    }

    public init(
        stopContext: Bool = false,
        stop: Stop? = nil,
        stateManager: SurveyStateProtocol,
        service: SurveyServiceProtocol,
        prioritizer: SurveyPrioritizing,
        externalLinkBuilder: ExternalSurveyURLBuilder
    ) {
        self.stopContext = stopContext
        self.service = service
        self.prioritizer = prioritizer
        self.stateManager = stateManager
        self.stop = stop
        self.externalLinkBuilder = externalLinkBuilder
    }

    func onAction(_ action: SurveysAction) {
        switch action {

        case .onAppear:
            onAppear()

        case .updateHeroAnswer(let answer):
            heroQuestionAnswer = answer

        case .onTapNextHeroQuestion:
            handleHeroQuestionNextAction()

        case .onCloseSurveyHeroQuestion:
            showSurveyDismissSheet = true

        case .onRemindLater:
            postponeSurvey()

        case .onSkipSurvey:
            skipSurvey()

        case .onCloseQuestionsForm:
            showFullSurveyQuestions = false
            isLoading = false // incase user is actively submitting a questions answers
            removeSurvey()

        case .onUpdateQuestion(let answer, let id):
            updateQuestionAnswer(answer, id: id)

        case .onSubmitQuestions:
            submitSurveyQuestionsAnswers()
        }
    }

    private func onAppear() {
        guard stateManager.shouldShowSurvey() else { return }
        fetchSurveys()
    }

    private func fetchSurveys() {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.service.fetchSurveys()
                if !self.service.surveys.isEmpty {
                    self.getNextSurvey()
                }
            } catch {
                print(error)
            }
        }
    }

    func updateCurrentStop(_ stop: Stop) {
        self.stop = stop
        if !activeSurvey {
            getNextSurvey()
        }
    }

    private func getNextSurvey() {
        let surveyIndex = prioritizer.nextSurveyIndex(service.surveys, visibleOnStop: stopContext, stop: stop)
        if surveyIndex != -1 {
            self.survey = service.surveys[surveyIndex]
            setHeroQuestion()
        }
    }

    private func showToastMessage(_ message: String, type: Toast.ToastType) {
        toastMessage = message
        toastType = type
        showToastMessage = true
    }

    private func removeSurvey() {
        survey = nil
        questions = []
    }
}

// MARK: - Hero Question
extension SurveysViewModel {

    /// Should Refactor this 
    private func setHeroQuestion() {
        guard let survey else { return }
        let firstQuestion = survey.getQuestions().first { $0.content.type != .label }
        self.heroQuestion = firstQuestion
        self.showHeroQuestion = true
    }

    private func handleHeroQuestionNextAction() {
        if heroQuestion?.content.type == .externalSurvey {
            handleOpenExternalSurvey()
        } else {
            submitHeroQuestionAnswer()
        }
    }

    private func validateHeroQuestionAnswer() -> Bool {
        guard let heroQuestionAnswer, !heroQuestionAnswer.stringValue.isEmpty else {
            showToastMessage(Strings.surveyHeroQuestionAnswerError, type: .error)
            return false
        }

        return true
    }

    private func submitHeroQuestionAnswer() {
        guard let question = heroQuestion, validateHeroQuestionAnswer(), let heroQuestionAnswer else { return }

        let response = QuestionAnswerSubmission(
            questionId: question.id,
            questionType: question.content.type.rawValue,
            questionLabel: question.content.labelText,
            answer: heroQuestionAnswer.stringValue
        )

        self.isLoading = true

        Task { [weak self] in
            guard let self, let survey else { return }

            defer { self.isLoading = false }

            do {
                try await self.service.submitSurveyResponse(
                    surveyId: survey.id,
                    stopIdentifier: self.stop?.id,
                    stopLongitude: self.stop?.coordinate.longitude,
                    stopLatitude: self.stop?.coordinate.latitude,
                    response
                )

                self.showToastMessage(Strings.surveyAnswerSuccessfullySubmitted, type: .success)
                self.setRemainingSurveyQuestions()
            } catch {
                self.error = error
            }
        }

    }

    private func setRemainingSurveyQuestions() {
        guard let survey else { return }

        let heroQuestionID = heroQuestion?.id ?? -1

        // Mark survey as completed.
        stateManager.setSurveyCompleted(survey.id)

        // Clear hero question content
        self.heroQuestion = nil
        self.heroQuestionAnswer = nil
        self.showHeroQuestion = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            if survey.getQuestions().count > 1, heroQuestionID != -1 {
                self.setSurveysQuestions(heroQuestionID)
            }
        }
    }

}

// MARK: - External Survey
extension SurveysViewModel {

    private func handleOpenExternalSurvey() {
        guard let externalURL = getExternalURL(), let survey else { return }

        self.externalSurveyURL = externalURL
        self.openExternalSurvey = true

        stateManager.setSurveyCompleted(survey.id)

        clearExternalSurveyState()
    }

    private func getExternalURL() -> URL? {
        guard let survey else { return nil }
        return externalLinkBuilder.buildURL(for: survey, stop: stop)
    }

    private func clearExternalSurveyState() {
        Task { @MainActor [weak self] in
            try await Task.sleep(for: .seconds(2))
            self?.heroQuestion = nil
            self?.externalSurveyURL = nil
            self?.openExternalSurvey = false
            self?.removeSurvey()
        }
    }

}

// MARK: - Full Survey Questions

extension SurveysViewModel {

    private func setSurveysQuestions(_ heroQuestionId: Int) {
        let questions = survey?.getQuestions().filter { $0.id != heroQuestionId } ?? []

        if !questions.isEmpty {
            self.questions = questions

            // Set questions ids to answers dictionary
            questions.forEach { self.questionsAnswers[$0.id] = .text("") }

            self.showFullSurveyQuestions = true
        }
    }

    private func updateQuestionAnswer(_ answer: SurveyQuestionAnswer, id: Int) {
        questionsAnswers[id] = answer
        incompleteQuestionIDs.removeAll(where: { $0 == id })
    }

    private func validateQuestionsAnswers() -> Bool {
        let validAnswers = answerableQuestionCount == answeredQuestionCount
        if !validAnswers {
            showToastMessage(Strings.surveyRequiredRemainingQuestionsError, type: .error)
            computeInvalidQuestions()
            return false
        }
        return true
    }

    private func computeInvalidQuestions() {
        self.incompleteQuestionIDs = questionsAnswers.filter { $0.value.stringValue.isEmpty }.map { $0.key }
    }

    private func buildQuestionsAnswersModel() -> [QuestionAnswerSubmission] {
        return questionsAnswers.compactMap { id, answer in
            guard let question = questions.first(where: { $0.id == id }) else { return nil }
            return QuestionAnswerSubmission(
                questionId: id,
                questionType: question.content.type.rawValue,
                questionLabel: question.content.labelText,
                answer: answer.stringValue
            )
        }
    }

    private func submitSurveyQuestionsAnswers() {
        guard validateQuestionsAnswers(), let survey else { return }
        let responses = buildQuestionsAnswersModel()

        isLoading = true

        Task { [weak self] in
            guard let self else { return }

            defer { isLoading = false }

            do {
                try await service.updateSurveyResponses(
                    surveyId: survey.id,
                    stopIdentifier: stop?.id,
                    stopLongitude: stop?.coordinate.longitude,
                    stopLatitude: stop?.coordinate.latitude,
                    responses
                )

                self.onSubmitQuestionsAnswersSuccess()

            } catch {
                print(error)
                self.showToastMessage(error.localizedDescription, type: .error)
            }
        }

    }

    private func onSubmitQuestionsAnswersSuccess() {
        removeSurvey()
        self.showFullSurveyQuestions = false
        self.showToastMessage(Strings.surveyAnswerSuccessfullySubmitted, type: .success)
    }

}

// MARK: - Survey Dismiss
extension SurveysViewModel {

    private func skipSurvey() {
        showSurveyDismissSheet = false

        guard let survey else { return }
        stateManager.setSurveySkipped(survey.id)
        clearHeroQuestionState()
        removeSurvey()
    }

    private func postponeSurvey() {
        showSurveyDismissSheet = false

        guard survey != nil else { return }
        stateManager.setNextReminderDate()
        clearHeroQuestionState()
        removeSurvey()
    }

    private func clearHeroQuestionState() {
        showHeroQuestion = false
        heroQuestion = nil
    }

}
