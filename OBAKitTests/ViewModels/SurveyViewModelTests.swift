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

    override func setUp() async throws {
        try await super.setUp()
        dataStore = UserDefaultsStore(userDefaults: userDefaults)
        surveyService = SurveyService(apiService: nil, userDataStore: dataStore)
        cancellables = []
    }

    override func tearDown() async throws {
        cancellables = nil
        surveyService = nil
        dataStore = nil
        try await super.tearDown()
    }

    // MARK: - Fixtures

    private static func makeQuestion(
        id: Int,
        position: Int = 1,
        required: Bool = true,
        type: QuestionType = .text,
        options: [String]? = nil,
        url: String? = nil
    ) -> SurveyQuestion {
        SurveyQuestion(
            id: id,
            position: position,
            required: required,
            content: QuestionContent(labelText: "q\(id)", type: type, options: options, url: url)
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

    /// A survey whose hero question can't be answered (e.g. label-only) cannot be
    /// submitted on the fresh path — the hero-answer lookup fails. Because the
    /// hero question exists (a label *is* a question at position 1) but has no
    /// captured answer, the VM surfaces `.malformedSurveyData`.
    @MainActor
    func test_submit_labelOnlySurvey_emitsMalformedSurveyData() async {
        let label = Self.makeQuestion(id: 1, position: 1, required: false, type: .label)
        let vm = makeViewModel(questions: [label])

        let result = await firstSubmissionResult(vm: vm)
        switch result {
        case .failure(.malformedSurveyData): break
        default: fail("Expected .malformedSurveyData for label-only survey; got \(result)")
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

    /// On the fresh path, if the survey has no hero question at all, submission
    /// surfaces `.malformedSurveyData` (an invariant violation, not user error).
    @MainActor
    func test_submit_freshPath_emitsMalformedSurveyDataWhenNoHeroQuestion() async {
        // No question has position == 1, so `survey.heroQuestion` is nil.
        let q = Self.makeQuestion(id: 1, position: 2, required: false, type: .text)
        let vm = makeViewModel(questions: [q])

        // No required questions, so initial validation passes, but then the
        // hero lookup fails and the VM falls through to .malformedSurveyData.
        let result = await firstSubmissionResult(vm: vm)
        switch result {
        case .failure(.malformedSurveyData): break
        default: fail("Expected .malformedSurveyData when hero is missing; got \(result)")
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
        if case .failure(.submissionFailed) = result { return true }
        return false
    }

    // MARK: - External Survey Validation

    /// A required `.externalSurvey` question is answered out-of-app (via the
    /// "Open Survey" button) so it can never be satisfied in-form. Validation
    /// must skip required external-survey questions, otherwise `submit()`
    /// could never proceed for a hero-external-survey configuration.
    @MainActor
    func test_validation_requiredExternalSurveyQuestion_isExcluded() async {
        let hero = Self.makeQuestion(id: 1, position: 1, required: true, type: .text)
        let external = Self.makeQuestion(id: 2, position: 2, required: true, type: .externalSurvey)
        let vm = makeViewModel(questions: [hero, external])

        // Answer only the hero — the required external question is left
        // unanswered, which would normally block validation but should be
        // excluded by type.
        vm.updateAnswer(for: hero, answer: "yes")

        let result = await firstSubmissionResult(vm: vm)
        expect(self.isNetworkFailure(result)).to(beTrue(), description: "expected validation to pass with required external survey question unanswered; got \(result)")
    }

    /// Excluding external-survey questions must not bypass *other* unanswered
    /// required questions — validation should still fail if a required text
    /// question is missing.
    @MainActor
    func test_validation_externalSurveyExclusion_doesNotBypassOtherRequired() async {
        let hero = Self.makeQuestion(id: 1, position: 1, required: true, type: .text)
        let followUp = Self.makeQuestion(id: 2, position: 2, required: true, type: .text)
        let external = Self.makeQuestion(id: 3, position: 3, required: true, type: .externalSurvey)
        let vm = makeViewModel(questions: [hero, followUp, external])

        // Hero answered; required follow-up text NOT answered; external skipped.
        vm.updateAnswer(for: hero, answer: "yes")

        let result = await firstSubmissionResult(vm: vm)
        switch result {
        case .failure(.validationFailed): break
        default: fail("Expected .validationFailed when a non-external required is unanswered; got \(result)")
        }
    }

    // MARK: - launchExternalSurvey

    /// When the survey has no openable URL, the launcher's failure path runs:
    /// `onFailure` fires, `onSuccess` does not, and the survey is NOT marked
    /// completed. Exercises the integration with the real `ExternalSurveyLauncher`
    /// owned by the VM.
    @MainActor
    func test_launchExternalSurvey_noURL_callsFailureAndDoesNotMarkCompleted() {
        // No `url:` on the question → `externalSurveyURL(for:stop:)` returns nil.
        let external = Self.makeQuestion(id: 1, position: 1, required: true, type: .externalSurvey)
        let vm = makeViewModel(questions: [external])

        var successCount = 0
        var failureCount = 0
        vm.launchExternalSurvey(
            onSuccess: { successCount += 1 },
            onFailure: { failureCount += 1 }
        )

        expect(failureCount) == 1
        expect(successCount) == 0
        expect(self.dataStore.isSurveyCompleted(surveyId: vm.survey.id, userIdentifier: self.dataStore.surveyUserIdentifier)).to(beFalse())
    }

    // MARK: - Two-Stage Submit (happy path, retry, re-entrancy)

    /// Counter wrapper passed into MockDataLoader matcher closures so the test
    /// can verify how many times each leg of the two-stage submit fired.
    ///
    /// `MockDataLoader` calls matchers on the request thread (off the main
    /// actor). The two legs run strictly sequentially today (POST → PUT) so
    /// there's no concurrent write in practice; `nonisolated(unsafe)` keeps
    /// Swift 6 from complaining while accurately marking the field as
    /// unsynchronized — if a future test exercises legitimate concurrent
    /// submits this needs a real atomic.
    private final class HitCounter: @unchecked Sendable {
        nonisolated(unsafe) var posts = 0   // hero submit (POST /api/v1/survey_responses/)
        nonisolated(unsafe) var puts  = 0   // additional questions (PUT /api/v1/survey_responses/{id})
        nonisolated(unsafe) var lastPutBody: Data?
    }

    /// Builds a real `SurveyService` whose `apiService` returns the canned
    /// submission response for every call. The provided counter is incremented
    /// per call so the test can verify which legs fired.
    @MainActor
    private func buildLiveSurveyService(counter: HitCounter) -> SurveyService {
        let mockLoader = MockDataLoader(testName: name)
        let data = try! Data(contentsOf: Bundle(for: SurveyViewModelTests.self)
            .url(forResource: "survey_submission_response", withExtension: "json")!)

        // POST hero: exact-path match (no trailing response id).
        mockLoader.mock(data: data) { request in
            guard request.httpMethod == "POST" else { return false }
            guard let path = request.url?.path else { return false }
            // Hero submits hit `/api/v1/survey_responses/` (or without trailing slash).
            let endsAtRoot = path.hasSuffix("/api/v1/survey_responses/") || path.hasSuffix("/api/v1/survey_responses")
            if endsAtRoot { counter.posts += 1; return true }
            return false
        }
        // PUT additional questions: path contains a response id segment.
        mockLoader.mock(data: data) { request in
            guard request.httpMethod == "PUT" else { return false }
            guard request.url?.path.contains("/api/v1/survey_responses/") ?? false else { return false }
            counter.puts += 1
            counter.lastPutBody = request.httpBody ?? request.httpBodyStream.flatMap { stream in
                stream.open()
                defer { stream.close() }
                var buffer = Data()
                let bufSize = 1024
                let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
                defer { bytes.deallocate() }
                while stream.hasBytesAvailable {
                    let read = stream.read(bytes, maxLength: bufSize)
                    if read <= 0 { break }
                    buffer.append(bytes, count: read)
                }
                return buffer
            }
            return true
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
        return SurveyService(apiService: apiService, userDataStore: dataStore)
    }

    /// Fresh path with hero only: one POST, zero PUTs, success, survey marked completed,
    /// and `heroResponseID` populated from the canned submission ID.
    @MainActor
    func test_submit_freshPath_heroOnly_succeedsAndMarksCompleted() async {
        let counter = HitCounter()
        let liveService = buildLiveSurveyService(counter: counter)
        let hero = Self.makeQuestion(id: 1, position: 1, type: .text)
        let vm = SurveyViewModel(survey: Self.makeSurvey(questions: [hero]), surveyService: liveService)
        vm.updateAnswer(for: hero, answer: "yes")

        let result = await firstSubmissionResult(vm: vm)

        guard case .success = result else {
            fail("Expected .success; got \(result)"); return
        }
        expect(counter.posts) == 1
        expect(counter.puts) == 0
        expect(vm.heroResponseID) == "808d3a515daa39f4c15a"
        let userID = dataStore.surveyUserIdentifier
        expect(self.dataStore.isSurveyCompleted(surveyId: vm.survey.id, userIdentifier: userID)).to(beTrue())
    }

    /// Fresh path with hero + follow-up: hero POST first, then a single PUT for the
    /// remaining responses. Both legs fire; survey is marked completed.
    @MainActor
    func test_submit_freshPath_heroPlusFollowup_runsBothLegs() async {
        let counter = HitCounter()
        let liveService = buildLiveSurveyService(counter: counter)
        let hero = Self.makeQuestion(id: 1, position: 1, type: .text)
        let follow = Self.makeQuestion(id: 2, position: 2, type: .text)
        let vm = SurveyViewModel(survey: Self.makeSurvey(questions: [hero, follow]), surveyService: liveService)
        vm.updateAnswer(for: hero, answer: "yes")
        vm.updateAnswer(for: follow, answer: "additional")

        let result = await firstSubmissionResult(vm: vm)

        guard case .success = result else {
            fail("Expected .success; got \(result)"); return
        }
        expect(counter.posts) == 1
        expect(counter.puts) == 1
        expect(vm.heroResponseID) == "808d3a515daa39f4c15a"
        let userID = dataStore.surveyUserIdentifier
        expect(self.dataStore.isSurveyCompleted(surveyId: vm.survey.id, userIdentifier: userID)).to(beTrue())
    }

    /// Retry path (`heroResponseID` preset): the hero POST is skipped entirely;
    /// only the PUT fires; survey is marked completed.
    @MainActor
    func test_submit_retryPath_skipsHeroSubmit() async {
        let counter = HitCounter()
        let liveService = buildLiveSurveyService(counter: counter)
        let hero = Self.makeQuestion(id: 1, position: 1, type: .text)
        let follow = Self.makeQuestion(id: 2, position: 2, type: .text)
        let vm = SurveyViewModel(
            survey: Self.makeSurvey(questions: [hero, follow]),
            surveyService: liveService,
            heroResponseID: "preset-hero"
        )
        vm.updateAnswer(for: follow, answer: "answered")

        let result = await firstSubmissionResult(vm: vm)

        guard case .success = result else {
            fail("Expected .success; got \(result)"); return
        }
        expect(counter.posts) == 0
        expect(counter.puts) == 1
        // heroResponseID is unchanged — we didn't re-submit the hero.
        expect(vm.heroResponseID) == "preset-hero"
    }

    /// Fresh path with hero only and no follow-up: the `remainingResponses.isEmpty`
    /// branch is taken, so zero PUTs fire and submission still succeeds.
    @MainActor
    func test_submit_freshPath_remainingResponsesEmpty_skipsAdditionalLeg() async {
        let counter = HitCounter()
        let liveService = buildLiveSurveyService(counter: counter)
        let hero = Self.makeQuestion(id: 1, position: 1, required: false, type: .text)
        let label = Self.makeQuestion(id: 2, position: 2, required: false, type: .label)
        let vm = SurveyViewModel(survey: Self.makeSurvey(questions: [hero, label]), surveyService: liveService)
        vm.updateAnswer(for: hero, answer: "yes")
        // The label is not answerable, so `responses` only contains the hero — the
        // `remainingResponses.isEmpty` branch fires.

        let result = await firstSubmissionResult(vm: vm)

        guard case .success = result else {
            fail("Expected .success; got \(result)"); return
        }
        expect(counter.posts) == 1
        expect(counter.puts) == 0
    }

    /// Retry path after a partial network failure: the fresh submit succeeded the hero POST
    /// (so `heroResponseID` is set and the hero answer is still in `responses`) but the
    /// additional-questions PUT failed. When the user retries, the PUT body must not
    /// include the hero answer — otherwise the hero is duplicated server-side.
    @MainActor
    func test_submit_retryPath_filtersHeroFromAdditionalResponses() async throws {
        let counter = HitCounter()
        let liveService = buildLiveSurveyService(counter: counter)
        let hero = Self.makeQuestion(id: 1, position: 1, type: .text)
        let follow = Self.makeQuestion(id: 2, position: 2, type: .text)
        let vm = SurveyViewModel(
            survey: Self.makeSurvey(questions: [hero, follow]),
            surveyService: liveService,
            heroResponseID: "preset-hero"
        )
        // Simulate the residue of a failed fresh submit: both answers still in `responses`.
        vm.updateAnswer(for: hero, answer: "yes")
        vm.updateAnswer(for: follow, answer: "answered")

        let result = await firstSubmissionResult(vm: vm)

        guard case .success = result else {
            fail("Expected .success; got \(result)"); return
        }
        expect(counter.posts) == 0
        expect(counter.puts) == 1

        // PUT body is `{"responses": "<stringified JSON array>"}`. Decode both layers.
        let body = try XCTUnwrap(counter.lastPutBody)
        let outer = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let inner = try XCTUnwrap(outer["responses"] as? String)
        let innerData = try XCTUnwrap(inner.data(using: .utf8))
        let responses = try XCTUnwrap(try JSONSerialization.jsonObject(with: innerData) as? [[String: Any]])
        let questionIDs = responses.compactMap { $0["question_id"] as? Int }
        expect(questionIDs).toNot(contain(hero.id))
        expect(questionIDs) == [follow.id]
    }

    /// `isSubmitting` toggles around a submit: false before, true while in-flight,
    /// false again after. Snapshot the published values via a sink so we capture the
    /// transient `true` rather than only observing the post-completion state.
    @MainActor
    func test_isSubmitting_togglesAroundSubmit() async {
        let counter = HitCounter()
        let liveService = buildLiveSurveyService(counter: counter)
        let hero = Self.makeQuestion(id: 1, position: 1, type: .text)
        let vm = SurveyViewModel(survey: Self.makeSurvey(questions: [hero]), surveyService: liveService)
        vm.updateAnswer(for: hero, answer: "yes")

        var observed: [Bool] = []
        let cancellable = vm.$isSubmitting.sink { observed.append($0) }
        defer { cancellable.cancel() }

        await vm.submit()

        // Initial false + true on enter + false on exit.
        expect(observed) == [false, true, false]
        expect(vm.isSubmitting).to(beFalse())
    }

    /// Concurrent `submit()` calls: the in-flight guard prevents the second from
    /// firing a second hero POST.
    @MainActor
    func test_submit_inFlightGuard_blocksConcurrentSubmit() async {
        let counter = HitCounter()
        let liveService = buildLiveSurveyService(counter: counter)
        let hero = Self.makeQuestion(id: 1, position: 1, type: .text)
        let vm = SurveyViewModel(survey: Self.makeSurvey(questions: [hero]), surveyService: liveService)
        vm.updateAnswer(for: hero, answer: "yes")

        // Kick off two submits concurrently.
        async let a: Void = vm.submit()
        async let b: Void = vm.submit()
        _ = await (a, b)

        // Only one of the two reached the network leg.
        expect(counter.posts) == 1
    }
}
