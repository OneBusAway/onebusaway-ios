//
//  ExternalSurveyLauncherTests.swift
//  OBAKitTests
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class ExternalSurveyLauncherTests: OBATestCase {

    nonisolated(unsafe) private var testUserDefaults: UserDefaults!
    nonisolated(unsafe) private var store: UserDefaultsStore!
    nonisolated(unsafe) private var context: MockSurveyURLApplicationContext!
    nonisolated(unsafe) private var service: SurveyService!

    override init() async throws {
        try await super.init()

        testUserDefaults = buildUserDefaults(suiteName: "\(userDefaultsSuiteName).launcher")
        testUserDefaults.removePersistentDomain(forName: "\(userDefaultsSuiteName).launcher")
        store = UserDefaultsStore(userDefaults: testUserDefaults)
        store.surveyUserIdentifier = "u-1"
        context = MockSurveyURLApplicationContext()
        service = SurveyService(apiService: nil, userDataStore: store, application: context)
    }

    isolated deinit {
        testUserDefaults.removePersistentDomain(forName: "\(userDefaultsSuiteName).launcher")
    }

    private func externalSurvey(id: Int = 1, url: String?, fields: [String] = []) -> Survey {
        SurveysTestHelpers.makeSurvey(id: id, questions: [
            SurveysTestHelpers.makeSurveyQuestion(type: .externalSurvey, url: url, embeddedDataFields: fields)
        ])
    }

    private func isCompleted(_ id: Int) -> Bool {
        store.isSurveyCompleted(surveyId: id, userIdentifier: "u-1")
    }

    @Test func `Launch opens exact URL marks completed calls on success`() {
        let survey = externalSurvey(url: "https://oba.co/s")
        var opened: URL?
        var succeeded = false
        var failed = false
        var launcher = ExternalSurveyLauncher(surveyService: service)
        launcher.urlOpener = { url, completion in opened = url; completion(true) }

        let attempted = launcher.launch(survey: survey, stop: nil,
                                        onSuccess: { succeeded = true },
                                        onFailure: { failed = true })

        #expect(attempted)
        #expect(opened?.absoluteString == "https://oba.co/s")
        #expect(succeeded)
        #expect(!failed)
        #expect(self.isCompleted(1))
    }

    @Test func `Launch appends stop ID when stop provided`() {
        let survey = externalSurvey(url: "https://oba.co/s", fields: ["stop_id"])
        let stop = SurveysTestHelpers.makeStop(id: "1_99")
        var opened: URL?
        var launcher = ExternalSurveyLauncher(surveyService: service)
        launcher.urlOpener = { url, completion in opened = url; completion(true) }

        launcher.launch(survey: survey, stop: stop, onSuccess: {}, onFailure: {})

        let items = URLComponents(url: opened!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.first { $0.name == "stop_id" }?.value == "1_99")
    }

    @Test func `Launch nil URL does not open does not complete calls on failure`() {
        let survey = externalSurvey(url: nil)
        var openerCalled = false
        var failed = false
        var launcher = ExternalSurveyLauncher(surveyService: service)
        launcher.urlOpener = { _, _ in openerCalled = true }

        let attempted = launcher.launch(survey: survey, stop: nil,
                                        onSuccess: {},
                                        onFailure: { failed = true })

        #expect(!attempted)
        #expect(!openerCalled)
        #expect(failed)
        #expect(!self.isCompleted(1))
    }

    @Test func `Launch open failure does not complete calls on failure`() {
        let survey = externalSurvey(url: "https://oba.co/s")
        var succeeded = false
        var failed = false
        var launcher = ExternalSurveyLauncher(surveyService: service)
        launcher.urlOpener = { _, completion in completion(false) }

        launcher.launch(survey: survey, stop: nil,
                        onSuccess: { succeeded = true },
                        onFailure: { failed = true })

        #expect(!succeeded)
        #expect(failed)
        #expect(!self.isCompleted(1))
    }
}
