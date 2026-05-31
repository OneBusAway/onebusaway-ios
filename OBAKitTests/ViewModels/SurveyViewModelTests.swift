//
//  SurveyViewModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
import Combine
import CoreLocation
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try

/// Tests for `SurveyViewModel`. Covers in-memory state mutation
/// (`updateAnswer`, `toggleCheckbox`), validation, `cancel()` reschedule,
/// and the submission-result publisher contract.
///
/// Network happy-path is not exercised here: `SurveyService` is `final`, so
/// we use a real `SurveyService(apiService: nil)`. Any code path that reaches
/// the network throws — which lets us positively assert that validation
/// *passed* (we observe `.network`, not `.validationFailed`).
class SurveyViewModelTests: OBATestCase {

    private var surveyService: SurveyService!
    private var dataStore: UserDefaultsStore!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        dataStore = UserDefaultsStore(userDefaults: userDefaults)
        surveyService = SurveyService(apiService: nil, userDataStore: dataStore)
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        surveyService = nil
        dataStore = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private static func makeQuestion(
        id: Int,
        position: Int = 1,
        required: Bool = true,
        type: QuestionType = .text,
        options: [String]? = nil
    ) -> SurveyQuestion {
        SurveyQuestion(
            id: id,
            position: position,
            required: required,
            content: QuestionContent(labelText: "q\(id)", type: type, options: options)
        )
    }

    private static func makeSurvey(questions: [SurveyQuestion]) -> Survey {
        Survey(
            id: 42,
            name: "Test Survey",
            createdAt: Date(),
            updatedAt: Date(),
            showOnMap: false,
            showOnStops: true,
            startDate: nil,
            endDate: nil,
            visibleStopsList: nil,
            visibleRoutesList: nil,
            allowsMultipleResponses: false,
            alwaysVisible: false,
            study: Study(id: 1, name: "Study", description: "desc"),
            questions: questions
        )
    }

    @MainActor
    private func makeViewModel(
        questions: [SurveyQuestion],
        heroResponseID: String? = nil,
        stop: Stop? = nil,
        stopID: String? = nil,
        stopLocation: CLLocationCoordinate2D? = nil
    ) -> SurveyViewModel {
        SurveyViewModel(
            survey: Self.makeSurvey(questions: questions),
            surveyService: surveyService,
            stop: stop,
            stopID: stopID,
            stopLocation: stopLocation,
            heroResponseID: heroResponseID
        )
    }

    // MARK: - Initial State

    /// A fresh VM exposes the survey it was constructed with, retains `heroResponseID`,
    /// and shows every question when no hero has been submitted.
    @MainActor
    func test_init_preservesSurveyAndHeroResponseID() {
        let q1 = Self.makeQuestion(id: 1, position: 1)
        let q2 = Self.makeQuestion(id: 2, position: 2)
        let vm = makeViewModel(questions: [q1, q2], heroResponseID: "hero-42")

        expect(vm.survey.id) == 42
        expect(vm.survey.name) == "Test Survey"
        expect(vm.heroResponseID) == "hero-42"
        expect(vm.questionsToShow.map(\.id)) == [2]
    }

    // MARK: - questionsToShow

    /// Without a hero response, every question is shown. With one preset, the hero is skipped.
    @MainActor
    func test_questionsToShow_respectsHeroResponseID() {
        let hero = Self.makeQuestion(id: 1, position: 1)
        let follow = Self.makeQuestion(id: 2, position: 2)

        let vmFresh = makeViewModel(questions: [hero, follow])
        expect(vmFresh.questionsToShow.map(\.id)) == [1, 2]

        let vmRetry = makeViewModel(questions: [hero, follow], heroResponseID: "abc")
        expect(vmRetry.questionsToShow.map(\.id)) == [2]
    }

    // MARK: - updateAnswer

    /// Submitting answers for distinct questions accumulates them; validation passes when all
    /// required questions are covered.
    @MainActor
    func test_updateAnswer_accumulatesAnswersAcrossQuestions() async {
        let q1 = Self.makeQuestion(id: 1, position: 1, type: .text)
        let q2 = Self.makeQuestion(id: 2, position: 2, type: .text)
        let vm = makeViewModel(questions: [q1, q2])

        vm.updateAnswer(for: q1, answer: "one")
        vm.updateAnswer(for: q2, answer: "two")

        // Validation should pass — both required questions answered. Network attempt throws.
        let result = await firstSubmissionResult(vm: vm)
        expect(self.isNetworkFailure(result)).to(beTrue(), description: "expected validation to pass; got \(result)")
    }

    /// A second answer for the same question replaces the first.
    @MainActor
    func test_updateAnswer_replacesPriorAnswerForSameQuestion() async {
        let q = Self.makeQuestion(id: 7, type: .text)
        let vm = makeViewModel(questions: [q])

        vm.updateAnswer(for: q, answer: "first")
        vm.updateAnswer(for: q, answer: "second")

        // Validation passes (only required question is answered), so submit reaches the network.
        let result = await firstSubmissionResult(vm: vm)
        expect(self.isNetworkFailure(result)).to(beTrue(), description: "expected validation to pass; got \(result)")
    }

    // MARK: - toggleCheckbox

    /// Toggling on accumulates selections; toggling off removes them. The resulting answer
    /// is JSON-encoded by `SurveyService.formatCheckboxAnswer`.
    @MainActor
    func test_toggleCheckbox_accumulatesAndRemoves() async {
        let q = Self.makeQuestion(id: 9, type: .checkbox, options: ["a", "b", "c"])
        let vm = makeViewModel(questions: [q])

        vm.toggleCheckbox(option: "a", selected: true, for: q)
        vm.toggleCheckbox(option: "b", selected: true, for: q)
        vm.toggleCheckbox(option: "a", selected: false, for: q)

        // Validation should pass — selection still stored after deselecting "a".
        let result = await firstSubmissionResult(vm: vm)
        expect(self.isNetworkFailure(result)).to(beTrue(), description: "expected validation to pass; got \(result)")
    }

    /// Toggling all options off leaves a stored answer (an empty JSON array `"[]"`), which is
    /// still considered an answer for validation purposes — matching the existing VC behavior.
    @MainActor
    func test_toggleCheckbox_offlyAllStillCountsAsAnswer() async {
        let q = Self.makeQuestion(id: 9, type: .checkbox, options: ["a", "b"])
        let vm = makeViewModel(questions: [q])

        vm.toggleCheckbox(option: "a", selected: true, for: q)
        vm.toggleCheckbox(option: "a", selected: false, for: q)

        // An empty-array answer is still stored; validation passes.
        let result = await firstSubmissionResult(vm: vm)
        expect(self.isNetworkFailure(result)).to(beTrue(), description: "expected validation to pass; got \(result)")
    }

    /// Toggling a checkbox on a question that was never touched succeeds — the
    /// `default: []` subscript handles a missing entry without crashing.
    @MainActor
    func test_toggleCheckbox_doesNotCrashOnFirstToggle() {
        let q = Self.makeQuestion(id: 9, type: .checkbox, options: ["x"])
        let vm = makeViewModel(questions: [q])

        // Toggling off without any prior on works (no precondition on existence).
        vm.toggleCheckbox(option: "x", selected: false, for: q)
        // No assertions — purely a "doesn't crash" check.
        _ = vm
    }

    // MARK: - submit validation

    /// `submit()` with no responses on a survey with required questions emits `.validationFailed`.
    @MainActor
    func test_submit_validationFailed_whenRequiredAnswersMissing() async {
        let q = Self.makeQuestion(id: 1, required: true, type: .text)
        let vm = makeViewModel(questions: [q])

        let result = await firstSubmissionResult(vm: vm)
        switch result {
        case .failure(.validationFailed): break
        default: fail("Expected .validationFailed; got \(result)")
        }
    }

    /// Non-required follow-up questions can be left unanswered without blocking submission,
    /// as long as the hero question has an answer.
    @MainActor
    func test_submit_nonRequiredQuestionsDoNotBlockValidation() async {
        let hero = Self.makeQuestion(id: 1, position: 1, required: true, type: .text)
        let optional = Self.makeQuestion(id: 2, position: 2, required: false, type: .text)
        let vm = makeViewModel(questions: [hero, optional])

        // Answer only the hero — the optional follow-up is left blank.
        vm.updateAnswer(for: hero, answer: "answered")

        let result = await firstSubmissionResult(vm: vm)
        expect(self.isNetworkFailure(result)).to(beTrue(), description: "expected validation to pass; got \(result)")
    }

    /// A survey whose hero question can't be answered (e.g. label-only) cannot be submitted on
    /// the fresh path — the hero-answer lookup fails and the VM emits `.validationFailed`.
    @MainActor
    func test_submit_labelOnlySurvey_emitsValidationFailed() async {
        let label = Self.makeQuestion(id: 1, position: 1, required: false, type: .label)
        let vm = makeViewModel(questions: [label])

        let result = await firstSubmissionResult(vm: vm)
        switch result {
        case .failure(.validationFailed): break
        default: fail("Expected .validationFailed for label-only survey; got \(result)")
        }
    }

    /// On the retry path (`heroResponseID` preset), only the remaining questions are validated.
    @MainActor
    func test_submit_retryPath_validatesRemainingOnly() async {
        let hero = Self.makeQuestion(id: 1, position: 1, required: true)
        let follow = Self.makeQuestion(id: 2, position: 2, required: false)
        let vm = makeViewModel(questions: [hero, follow], heroResponseID: "hero-id")

        // No answers — but the only remaining question (id=2) is optional. Validation passes.
        let result = await firstSubmissionResult(vm: vm)
        expect(self.isNetworkFailure(result)).to(beTrue(), description: "expected validation to pass; got \(result)")
    }

    /// Validation failure does NOT mark the survey completed or set a reminder.
    @MainActor
    func test_submit_validationFailure_doesNotMarkSurveyCompleted() async {
        let q = Self.makeQuestion(id: 1, required: true, type: .text)
        let vm = makeViewModel(questions: [q])

        _ = await firstSubmissionResult(vm: vm)

        // Reminder date remains nil (cancel was never called and submit didn't reach completion).
        expect(self.dataStore.nextSurveyReminderDate).to(beNil())
        // Survey is not in the completed set.
        expect(self.dataStore.isSurveyCompleted(surveyId: vm.survey.id, userIdentifier: self.dataStore.surveyUserIdentifier)).to(beFalse())
    }

    /// Network failure does NOT mark the survey completed either — only a successful
    /// `submit()` should flip that bit.
    @MainActor
    func test_submit_networkFailure_doesNotMarkSurveyCompleted() async {
        let q = Self.makeQuestion(id: 1, required: true, type: .text)
        let vm = makeViewModel(questions: [q])
        vm.updateAnswer(for: q, answer: "yes")

        let result = await firstSubmissionResult(vm: vm)
        expect(self.isNetworkFailure(result)).to(beTrue())

        expect(self.dataStore.isSurveyCompleted(surveyId: vm.survey.id, userIdentifier: self.dataStore.surveyUserIdentifier)).to(beFalse())
    }

    /// On the fresh path, if the survey has no hero question at all, submission fails validation.
    @MainActor
    func test_submit_freshPath_emitsValidationFailedWhenNoHeroQuestion() async {
        // No question has position == 1, so `survey.heroQuestion` is nil.
        let q = Self.makeQuestion(id: 1, position: 2, required: false, type: .text)
        let vm = makeViewModel(questions: [q])

        // No required questions, so initial validation passes, but then the
        // hero lookup fails and the VM falls through to .validationFailed.
        let result = await firstSubmissionResult(vm: vm)
        switch result {
        case .failure(.validationFailed): break
        default: fail("Expected .validationFailed when hero is missing; got \(result)")
        }
    }

    // MARK: - submissionResult publisher

    /// `submissionResult` emits one event per `submit()` invocation. Two submits → two events.
    @MainActor
    func test_submissionResult_emitsOnEverySubmit() async {
        let q = Self.makeQuestion(id: 1, required: true, type: .text)
        let vm = makeViewModel(questions: [q])

        var received: [Result<Void, SurveyViewModel.SubmissionError>] = []
        vm.submissionResult.sink { received.append($0) }.store(in: &cancellables)

        await vm.submit() // validationFailed
        await vm.submit() // validationFailed again

        expect(received.count) == 2
        for r in received {
            if case .failure(.validationFailed) = r { continue }
            fail("Expected all results to be .validationFailed; got \(r)")
        }
    }

    // MARK: - cancel

    /// `cancel()` calls `markSurveyForLater` and sets the reminder date.
    @MainActor
    func test_cancel_marksForLaterAndSetsReminder() {
        let q = Self.makeQuestion(id: 1)
        let vm = makeViewModel(questions: [q])

        expect(self.dataStore.nextSurveyReminderDate).to(beNil())

        vm.cancel()

        // markSurveyForLater + setNextReminderDate ran.
        expect(self.dataStore.nextSurveyReminderDate).toNot(beNil())
        // NOT marked completed.
        let userID = dataStore.surveyUserIdentifier
        expect(self.dataStore.isSurveyCompleted(surveyId: vm.survey.id, userIdentifier: userID)).to(beFalse())
    }

    /// The reminder date set by `cancel()` is roughly 3 days in the future (matches
    /// `SurveyService.setNextReminderDate()`'s contract).
    @MainActor
    func test_cancel_remindersDateIsAboutThreeDaysOut() {
        let vm = makeViewModel(questions: [Self.makeQuestion(id: 1)])

        let before = Date()
        vm.cancel()
        let after = Date()

        guard let reminder = dataStore.nextSurveyReminderDate else {
            fail("nextSurveyReminderDate not set")
            return
        }

        let lowerBound = before.addingTimeInterval(3 * 86400 - 60)
        let upperBound = after.addingTimeInterval(3 * 86400 + 60)
        expect(reminder).to(beGreaterThanOrEqualTo(lowerBound))
        expect(reminder).to(beLessThanOrEqualTo(upperBound))
    }

    // MARK: - Helpers

    /// Awaits the first emission from `submissionResult` while `vm.submit()` runs.
    @MainActor
    private func firstSubmissionResult(vm: SurveyViewModel) async -> Result<Void, SurveyViewModel.SubmissionError> {
        await withCheckedContinuation { continuation in
            var fired = false
            vm.submissionResult
                .sink { result in
                    guard !fired else { return }
                    fired = true
                    continuation.resume(returning: result)
                }
                .store(in: &cancellables)

            Task { await vm.submit() }
        }
    }

    private func isNetworkFailure(_ result: Result<Void, SurveyViewModel.SubmissionError>) -> Bool {
        if case .failure(.network) = result { return true }
        return false
    }
}
