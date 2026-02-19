//
//  SurveysViewModelTests.swift
//  OBAKit
//
//  Created by Mohamed Sliem on 18/02/2026.
//

import XCTest
import Nimble
@testable import OBAKit
@testable import OBAKitCore

@MainActor
final class SurveysViewModelTests: XCTestCase {

    private typealias TestHelper = SurveysTestHelpers

    var service: MockSurveyService!
    var prioritizer: MockSurveyPrioritizer!
    var stateManager: MockSurveyStateManager!
    var externalLinkBuilder: MockExternalSurveyURLBuilder!
    var viewModel: SurveysViewModel!

    override func setUp() {
        super.setUp()
        service = MockSurveyService()
        prioritizer = MockSurveyPrioritizer()
        stateManager = MockSurveyStateManager()
        externalLinkBuilder = MockExternalSurveyURLBuilder()
        viewModel = makeViewModel()
    }

    private func makeViewModel(stopContext: Bool = false, stop: Stop? = nil) -> SurveysViewModel {
        SurveysViewModel(
            stopContext: stopContext,
            stop: stop,
            stateManager: stateManager,
            service: service,
            prioritizer: prioritizer,
            externalLinkBuilder: externalLinkBuilder
        )
    }

    // MARK: - Wait Helpers

    /// Generic poller: suspends until `condition()` returns `true` or `timeout` elapses.
    private func waitUntil(
        timeout: TimeInterval = 5.0,
        condition: () -> Bool
    ) async throws {
        let start = Date()
        while !condition() && Date().timeIntervalSince(start) < timeout {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    /// Waits until the mock records that `fetchSurveys` has fully returned
    /// (increments on both success and throw via `defer`).
    private func waitForFetchCompleted(expectedCount: Int = 1) async throws {
        try await waitUntil { self.service.fetchCompletedCallCount >= expectedCount }
    }

    /// Waits until the mock records that `submitSurveyResponse` has fully returned.
    private func waitForSubmitCompleted(expectedCount: Int = 1) async throws {
        try await waitUntil { self.service.submitCompletedCallCount >= expectedCount }
    }

    /// Waits until the mock records that `updateSurveyResponses` has fully returned.
    private func waitForUpdateCompleted(expectedCount: Int = 1) async throws {
        try await waitUntil { self.service.updateCompletedCallCount >= expectedCount }
    }

    /// Waits until the remaining-questions form appears.
    /// Covers the 1.5 s internal delay in `setRemainingSurveyQuestions` plus
    /// poller overhead — timeout is set well above 1.5 s.
    private func waitForFullSurveyForm() async throws {
        try await waitUntil(timeout: 8.0) { self.viewModel.showFullSurveyQuestions }
    }

    /// Waits until `heroQuestion` clears after a hero submit where no follow-up
    /// form will appear (e.g. only label questions remain).
    private func waitForHeroQuestionCleared() async throws {
        try await waitUntil { self.viewModel.heroQuestion == nil }
    }

    /// Waits until a toast message is shown on the view model.
    private func waitForToast() async throws {
        try await waitUntil { self.viewModel.showToastMessage }
    }

    /// Waits until `openExternalSurvey` becomes `true`.
    /// Used for external survey tests where no `submitSurveyResponse` call is made,
    /// so `waitForSubmitCompleted` would never resolve.
    private func waitForExternalSurveyOpened() async throws {
        try await waitUntil { self.viewModel.openExternalSurvey }
    }

    // MARK: - Convenience Setup

    /// Triggers `.onAppear` and waits until the internal fetch task has fully returned.
    private func loadSurveyAndWaitForFetch() async throws {
        viewModel.onAction(.onAppear)
        try await waitForFetchCompleted()
    }

    /// Sets a hero answer, taps next, and waits until the submit task has fully returned.
    private func submitHeroAnswer(_ answer: String = "Answer") async throws {
        viewModel.onAction(.updateHeroAnswer(.text(answer)))
        viewModel.onAction(.onTapNextHeroQuestion)
        try await waitForSubmitCompleted()
    }

    /// Sets a hero answer, taps next, and waits for the full-survey form to appear.
    /// Polls directly on `showFullSurveyQuestions` rather than chaining through
    /// the submit counter — the form appearing implies the submit succeeded AND
    /// the VM's 1.5 s internal delay has elapsed.
    private func submitHeroAnswerAndWaitForFullForm(_ answer: String = "Answer") async throws {
        viewModel.onAction(.updateHeroAnswer(.text(answer)))
        viewModel.onAction(.onTapNextHeroQuestion)
        try await waitForFullSurveyForm()
    }

    // MARK: - onAppear

    func test_onAppear_doesNotFetch_whenShouldShowSurveyIsFalse() async throws {
        stateManager.shouldShowSurveyReturnValue = false

        viewModel.onAction(.onAppear)
        // No fetch fires, so we yield execution briefly to let any
        // potential (unexpected) async work complete before asserting.
        try await Task.sleep(nanoseconds: 200_000_000)

        expect(self.service.fetchSurveysCallCount).to(equal(0))
    }

    func test_onAppear_fetchesSurveys_whenShouldShowSurveyIsTrue() async throws {
        service.surveys = [TestHelper.makeSurvey()]
        stateManager.shouldShowSurveyReturnValue = true

        viewModel.onAction(.onAppear)
        try await waitForFetchCompleted()

        expect(self.service.fetchSurveysCallCount).to(equal(1))
    }

    func test_onAppear_setsHeroQuestion_afterSuccessfulFetch() async throws {
        service.surveys = [TestHelper.makeSurvey(questions: [TestHelper.makeSurveyQuestion(id: 1, type: .text)])]
        stateManager.shouldShowSurveyReturnValue = true
        prioritizer.nextSurveyIndexReturnValue = 0

        try await loadSurveyAndWaitForFetch()

        expect(self.viewModel.heroQuestion).toNot(beNil())
        expect(self.viewModel.showHeroQuestion).to(beTrue())
    }

    func test_onAppear_showsErrorToast_onFetchFailure() async throws {
        service.fetchSurveysError = URLError(.notConnectedToInternet)
        stateManager.shouldShowSurveyReturnValue = true

        viewModel.onAction(.onAppear)
        try await waitForFetchCompleted()
        try await waitForToast()

        expect(self.viewModel.showToastMessage).to(beTrue())
        expect(self.viewModel.toast?.type).to(equal(.error))
    }

    // MARK: - Hero Question Setup

    func test_heroQuestion_isFirstNonLabelQuestion() async throws {
        service.surveys = [TestHelper.makeSurvey(questions: [
            TestHelper.makeSurveyQuestion(id: 1, type: .label, labelText: "Section Header"),
            TestHelper.makeSurveyQuestion(id: 2, type: .text)
        ])]
        stateManager.shouldShowSurveyReturnValue = true
        prioritizer.nextSurveyIndexReturnValue = 0

        try await loadSurveyAndWaitForFetch()

        expect(self.viewModel.heroQuestion?.id).to(equal(2))
    }

    func test_heroQuestion_notShown_whenAllQuestionsAreLabels() async throws {
        service.surveys = [TestHelper.makeSurvey(questions: [
            TestHelper.makeSurveyQuestion(id: 1, type: .label, labelText: "Info only")
        ])]
        stateManager.shouldShowSurveyReturnValue = true
        prioritizer.nextSurveyIndexReturnValue = 0

        try await loadSurveyAndWaitForFetch()

        expect(self.viewModel.heroQuestion).to(beNil())
        expect(self.viewModel.showHeroQuestion).to(beFalse())
    }

    // MARK: - Hero Question Answer Validation

    func test_nextHeroQuestion_showsError_whenAnswerIsEmpty() async throws {
        service.surveys = [TestHelper.makeSurvey(questions: [TestHelper.makeSurveyQuestion(id: 1, type: .text)])]
        stateManager.shouldShowSurveyReturnValue = true
        prioritizer.nextSurveyIndexReturnValue = 0

        try await loadSurveyAndWaitForFetch()
        viewModel.onAction(.onTapNextHeroQuestion)
        try await waitForToast()

        expect(self.service.submitResponseCallCount).to(equal(0))
        expect(self.viewModel.showToastMessage).to(beTrue())
        expect(self.viewModel.toast?.type).to(equal(.error))
    }

    func test_nextHeroQuestion_submits_whenAnswerIsProvided() async throws {
        service.surveys = [TestHelper.makeSurvey(id: 42, questions: [TestHelper.makeSurveyQuestion(id: 1, type: .text)])]
        stateManager.shouldShowSurveyReturnValue = true
        prioritizer.nextSurveyIndexReturnValue = 0

        try await loadSurveyAndWaitForFetch()
        try await submitHeroAnswer("My Answer")

        expect(self.service.submitResponseCallCount).to(equal(1))
        expect(self.service.lastSubmittedSurveyId).to(equal(42))
    }

    // MARK: - Submit Hero Answer

    func test_submitHeroAnswer_marksSurveyCompleted_onSuccess() async throws {
        service.surveys = [TestHelper.makeSurvey(id: 10, questions: [TestHelper.makeSurveyQuestion(id: 1, type: .text)])]
        stateManager.shouldShowSurveyReturnValue = true
        prioritizer.nextSurveyIndexReturnValue = 0

        try await loadSurveyAndWaitForFetch()
        try await submitHeroAnswer()
        try await waitForHeroQuestionCleared()

        expect(self.stateManager.setSurveyCompletedCallCount).to(equal(1))
        expect(self.stateManager.lastCompletedSurveyID).to(equal(10))
        expect(self.viewModel.heroQuestion).to(beNil())
        expect(self.viewModel.showHeroQuestion).to(beFalse())
    }

    func test_submitHeroAnswer_passesStopIdentifier_whenStopIsSet() async throws {
        let stop = TestHelper.makeStop(id: "stop-123")
        viewModel = makeViewModel(stopContext: true, stop: stop)

        service.surveys = [TestHelper.makeSurvey(showOnStops: true, questions: [TestHelper.makeSurveyQuestion(id: 1, type: .text)])]
        stateManager.shouldShowSurveyReturnValue = true
        prioritizer.nextSurveyIndexReturnValue = 0

        try await loadSurveyAndWaitForFetch()
        try await submitHeroAnswer()

        expect(self.service.lastSubmittedStopId).to(equal("stop-123"))
    }

    func test_submitHeroAnswer_showsErrorToast_onFailure() async throws {
        service.submitResponseError = URLError(.timedOut)
        service.surveys = [TestHelper.makeSurvey(questions: [TestHelper.makeSurveyQuestion(id: 1, type: .text)])]
        stateManager.shouldShowSurveyReturnValue = true
        prioritizer.nextSurveyIndexReturnValue = 0

        try await loadSurveyAndWaitForFetch()
        try await submitHeroAnswer()

        expect(self.viewModel.showToastMessage).to(beTrue())
        expect(self.viewModel.toast?.type).to(equal(.error))
        expect(self.stateManager.setSurveyCompletedCallCount).to(equal(0))
    }

    // MARK: - Remaining Questions

    func test_remainingQuestions_areSet_afterHeroAnswerSuccess() async throws {
        service.surveys = [TestHelper.makeSurvey(questions: [
            TestHelper.makeSurveyQuestion(id: 1, type: .text),
            TestHelper.makeSurveyQuestion(id: 2, type: .radio, options: ["Option A", "Option B"])
        ])]
        stateManager.shouldShowSurveyReturnValue = true
        prioritizer.nextSurveyIndexReturnValue = 0

        try await loadSurveyAndWaitForFetch()
        try await submitHeroAnswerAndWaitForFullForm()

        expect(self.viewModel.questions).to(haveCount(1))
        expect(self.viewModel.questions.first?.id).to(equal(2))
        expect(self.viewModel.questions.first?.content.type).to(equal(.radio))
        expect(self.viewModel.showFullSurveyQuestions).to(beTrue())
    }

    func test_fullSurveyForm_notShown_whenRemainingQuestionsAreAllLabels() async throws {
        service.surveys = [TestHelper.makeSurvey(questions: [
            TestHelper.makeSurveyQuestion(id: 1, type: .text),
            TestHelper.makeSurveyQuestion(id: 2, type: .label, labelText: "Thank you!")
        ])]
        stateManager.shouldShowSurveyReturnValue = true
        prioritizer.nextSurveyIndexReturnValue = 0

        try await loadSurveyAndWaitForFetch()
        try await submitHeroAnswer()
        try await waitForHeroQuestionCleared()

        expect(self.viewModel.showFullSurveyQuestions).to(beFalse())
    }

    // MARK: - Full Questions Validation

    func test_submitQuestions_showsError_whenNotAllAnswered() async throws {
        service.surveys = [TestHelper.makeSurvey(questions: [
            TestHelper.makeSurveyQuestion(id: 1, type: .text),
            TestHelper.makeSurveyQuestion(id: 2, type: .text),
            TestHelper.makeSurveyQuestion(id: 3, type: .text)
        ])]
        stateManager.shouldShowSurveyReturnValue = true
        prioritizer.nextSurveyIndexReturnValue = 0

        try await loadSurveyAndWaitForFetch()
        try await submitHeroAnswerAndWaitForFullForm()

        // Answer only q2, leaving q3 empty
        viewModel.onAction(.onUpdateQuestion(answer: .text("Answer 2"), id: 2))
        viewModel.onAction(.onSubmitQuestions)
        try await waitForUpdateCompleted()

        expect(self.service.updateResponseCallCount).to(equal(0))
        expect(self.viewModel.showToastMessage).to(beTrue())
        expect(self.viewModel.toast?.type).to(equal(.error))
        expect(self.viewModel.incompleteQuestionIDs).to(contain(3))
    }

    func test_submitQuestions_callsUpdate_whenAllAnswered() async throws {
        service.surveys = [TestHelper.makeSurvey(id: 99, questions: [
            TestHelper.makeSurveyQuestion(id: 1, type: .text),
            TestHelper.makeSurveyQuestion(id: 2, type: .text)
        ])]
        stateManager.shouldShowSurveyReturnValue = true
        prioritizer.nextSurveyIndexReturnValue = 0

        try await loadSurveyAndWaitForFetch()
        try await submitHeroAnswerAndWaitForFullForm()

        viewModel.onAction(.onUpdateQuestion(answer: .text("Answer 2"), id: 2))
        viewModel.onAction(.onSubmitQuestions)
        try await waitForUpdateCompleted()

        expect(self.service.updateResponseCallCount).to(equal(1))
        expect(self.service.lastUpdatedSurveyId).to(equal(99))
    }

    func test_submitQuestions_clearsSurveyAndShowsSuccess_onSuccess() async throws {
        service.surveys = [TestHelper.makeSurvey(questions: [
            TestHelper.makeSurveyQuestion(id: 1, type: .text),
            TestHelper.makeSurveyQuestion(id: 2, type: .text)
        ])]
        stateManager.shouldShowSurveyReturnValue = true
        prioritizer.nextSurveyIndexReturnValue = 0

        try await loadSurveyAndWaitForFetch()
        try await submitHeroAnswerAndWaitForFullForm()

        viewModel.onAction(.onUpdateQuestion(answer: .text("Answer 2"), id: 2))
        viewModel.onAction(.onSubmitQuestions)
        try await waitForUpdateCompleted()

        expect(self.viewModel.showFullSurveyQuestions).to(beFalse())
        expect(self.viewModel.questions).to(beEmpty())
        expect(self.viewModel.toast?.type).to(equal(.success))
    }

    func test_submitQuestions_showsError_onUpdateFailure() async throws {
        service.updateResponseError = URLError(.networkConnectionLost)
        service.surveys = [TestHelper.makeSurvey(questions: [
            TestHelper.makeSurveyQuestion(id: 1, type: .text),
            TestHelper.makeSurveyQuestion(id: 2, type: .text)
        ])]
        stateManager.shouldShowSurveyReturnValue = true
        prioritizer.nextSurveyIndexReturnValue = 0

        try await loadSurveyAndWaitForFetch()
        try await submitHeroAnswerAndWaitForFullForm()

        viewModel.onAction(.onUpdateQuestion(answer: .text("Answer 2"), id: 2))
        viewModel.onAction(.onSubmitQuestions)
        try await waitForUpdateCompleted()
        try await waitForToast()

        expect(self.viewModel.showToastMessage).to(beTrue())
        expect(self.viewModel.toast?.type).to(equal(.error))
        expect(self.viewModel.showFullSurveyQuestions).to(beTrue()) // Form stays visible
    }

    // MARK: - Skip Survey

    func test_skipSurvey_marksSurveySkipped_andClearsSurveyState() async throws {
        service.surveys = [TestHelper.makeSurvey(id: 7, questions: [TestHelper.makeSurveyQuestion(id: 1, type: .text)])]
        stateManager.shouldShowSurveyReturnValue = true
        prioritizer.nextSurveyIndexReturnValue = 0

        try await loadSurveyAndWaitForFetch()
        viewModel.onAction(.onSkipSurvey)

        expect(self.stateManager.setSurveySkippedCallCount).to(equal(1))
        expect(self.stateManager.lastSkippedSurveyID).to(equal(7))
        expect(self.viewModel.showHeroQuestion).to(beFalse())
        expect(self.viewModel.heroQuestion).to(beNil())
        expect(self.viewModel.questions).to(beEmpty())
    }

    // MARK: - Postpone Survey

    func test_postponeSurvey_setsNextReminderDate_andClearsSurveyState() async throws {
        service.surveys = [TestHelper.makeSurvey(questions: [TestHelper.makeSurveyQuestion(id: 1, type: .text)])]
        stateManager.shouldShowSurveyReturnValue = true
        prioritizer.nextSurveyIndexReturnValue = 0

        try await loadSurveyAndWaitForFetch()
        viewModel.onAction(.onRemindLater)

        expect(self.stateManager.setNextReminderDateCallCount).to(equal(1))
        expect(self.viewModel.showHeroQuestion).to(beFalse())
        expect(self.viewModel.heroQuestion).to(beNil())
    }

    // MARK: - External Survey

    func test_externalSurvey_opensURL_andMarksSurveyCompleted() async throws {
        service.surveys = [TestHelper.makeSurvey(id: 5, questions: [
            TestHelper.makeSurveyQuestion(id: 1, type: .externalSurvey, url: "https://example.com/survey")
        ])]
        stateManager.shouldShowSurveyReturnValue = true
        prioritizer.nextSurveyIndexReturnValue = 0

        try await loadSurveyAndWaitForFetch()
        // External surveys skip submitSurveyResponse entirely — wait on the
        // state the VM actually sets instead of a service completion counter.
        viewModel.onAction(.updateHeroAnswer(.text("any")))
        viewModel.onAction(.onTapNextHeroQuestion)
        try await waitForExternalSurveyOpened()

        expect(self.viewModel.openExternalSurvey).to(beTrue())
        expect(self.viewModel.externalSurveyURL).toNot(beNil())
        expect(self.stateManager.setSurveyCompletedCallCount).to(equal(1))
        expect(self.stateManager.lastCompletedSurveyID).to(equal(5))
        expect(self.externalLinkBuilder.buildURLCallCount).to(equal(1))
    }

    func test_externalSurvey_showsError_whenURLBuildingFails() async throws {
        externalLinkBuilder.urlToReturn = nil
        service.surveys = [TestHelper.makeSurvey(questions: [
            TestHelper.makeSurveyQuestion(id: 1, type: .externalSurvey)
        ])]
        stateManager.shouldShowSurveyReturnValue = true
        prioritizer.nextSurveyIndexReturnValue = 0

        try await loadSurveyAndWaitForFetch()
        // External surveys don't call submitSurveyResponse — wait on the toast
        // that the URL-building failure path shows synchronously.
        viewModel.onAction(.updateHeroAnswer(.text("any")))
        viewModel.onAction(.onTapNextHeroQuestion)
        try await waitForToast()

        expect(self.viewModel.openExternalSurvey).to(beFalse())
        expect(self.viewModel.showToastMessage).to(beTrue())
        expect(self.viewModel.toast?.type).to(equal(.error))
    }

    // MARK: - updateCurrentStop

    func test_updateCurrentStop_fetchesNextSurvey_whenNoActiveSurvey() async throws {
        stateManager.shouldShowSurveyReturnValue = true
        service.surveys = [TestHelper.makeSurvey(questions: [TestHelper.makeSurveyQuestion(id: 1, type: .text)])]
        prioritizer.nextSurveyIndexReturnValue = 0

        viewModel.updateCurrentStop(TestHelper.makeStop(id: "stop-456"))
        try await waitForFetchCompleted()

        expect(self.viewModel.heroQuestion).toNot(beNil())
    }

    func test_updateCurrentStop_doesNotRefetch_whenSurveyAlreadyActive() async throws {
        stateManager.shouldShowSurveyReturnValue = true
        service.surveys = [TestHelper.makeSurvey(questions: [TestHelper.makeSurveyQuestion(id: 1, type: .text)])]
        prioritizer.nextSurveyIndexReturnValue = 0

        try await loadSurveyAndWaitForFetch()
        let callCountAfterInitialLoad = prioritizer.nextSurveyIndexCallCount

        viewModel.updateCurrentStop(TestHelper.makeStop(id: "stop-789"))
        try await waitForFetchCompleted()

        expect(self.prioritizer.nextSurveyIndexCallCount).to(equal(callCountAfterInitialLoad))
    }

    // MARK: - Answer Update

    func test_updateQuestionAnswer_removesFromIncompleteIDs() async throws {
        service.surveys = [TestHelper.makeSurvey(questions: [
            TestHelper.makeSurveyQuestion(id: 1, type: .text),
            TestHelper.makeSurveyQuestion(id: 2, type: .text),
            TestHelper.makeSurveyQuestion(id: 3, type: .text)
        ])]
        stateManager.shouldShowSurveyReturnValue = true
        prioritizer.nextSurveyIndexReturnValue = 0

        try await loadSurveyAndWaitForFetch()
        try await submitHeroAnswerAndWaitForFullForm()

        // Trigger validation to populate incompleteQuestionIDs
        viewModel.onAction(.onSubmitQuestions)
        try await waitForUpdateCompleted()
        expect(self.viewModel.incompleteQuestionIDs).to(contain(2, 3))

        // Answering q2 removes it from incompleteQuestionIDs, leaving only q3
        viewModel.onAction(.onUpdateQuestion(answer: .text("Answer"), id: 2))

        expect(self.viewModel.incompleteQuestionIDs).toNot(contain(2))
        expect(self.viewModel.incompleteQuestionIDs).to(contain(3))
    }

    // MARK: - answerableQuestionCount

    func test_answerableQuestionCount_excludesLabels() async throws {
        service.surveys = [TestHelper.makeSurvey(questions: [
            TestHelper.makeSurveyQuestion(id: 1, type: .text),
            TestHelper.makeSurveyQuestion(id: 2, type: .label, labelText: "Section Header"),
            TestHelper.makeSurveyQuestion(id: 3, type: .text)
        ])]
        stateManager.shouldShowSurveyReturnValue = true
        prioritizer.nextSurveyIndexReturnValue = 0

        try await loadSurveyAndWaitForFetch()
        try await submitHeroAnswerAndWaitForFullForm()

        // Only q3 is answerable (label excluded, hero already submitted)
        expect(self.viewModel.answerableQuestionCount).to(equal(1))
    }

    // MARK: - Close / Dismiss Actions

    func test_closeQuestionsForm_hidesFormAndClearsSurvey() async throws {
        service.surveys = [TestHelper.makeSurvey(questions: [
            TestHelper.makeSurveyQuestion(id: 1, type: .text),
            TestHelper.makeSurveyQuestion(id: 2, type: .text)
        ])]
        stateManager.shouldShowSurveyReturnValue = true
        prioritizer.nextSurveyIndexReturnValue = 0

        try await loadSurveyAndWaitForFetch()
        try await submitHeroAnswerAndWaitForFullForm()
        viewModel.onAction(.onCloseQuestionsForm)

        expect(self.viewModel.showFullSurveyQuestions).to(beFalse())
        expect(self.viewModel.questions).to(beEmpty())
        expect(self.viewModel.isLoading).to(beFalse())
    }

    func test_closeSurveyHeroQuestion_showsDismissSheet() async throws {
        service.surveys = [TestHelper.makeSurvey(questions: [TestHelper.makeSurveyQuestion(id: 1, type: .text)])]
        stateManager.shouldShowSurveyReturnValue = true
        prioritizer.nextSurveyIndexReturnValue = 0

        try await loadSurveyAndWaitForFetch()
        viewModel.onAction(.onCloseSurveyHeroQuestion)

        expect(self.viewModel.showSurveyDismissSheet).to(beTrue())
    }

    func test_hideSurveyDismissSheet_hidesDismissSheet() {
        viewModel.onAction(.hideSurveyDismissSheet)
        expect(self.viewModel.showSurveyDismissSheet).to(beFalse())
    }

    func test_hideToastMessage_hidesToast() {
        viewModel.onAction(.hideToastMessage)
        expect(self.viewModel.showToastMessage).to(beFalse())
    }
}
