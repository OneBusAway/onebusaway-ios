//
//  ExternalSurveyLauncherTests.swift
//  OBAKitTests
//

import XCTest
import Nimble
@testable import OBAKit
@testable import OBAKitCore

final class ExternalSurveyLauncherTests: OBATestCase {

    nonisolated(unsafe) private var testUserDefaults: UserDefaults!
    nonisolated(unsafe) private var store: UserDefaultsStore!
    nonisolated(unsafe) private var context: MockSurveyURLApplicationContext!
    nonisolated(unsafe) private var service: SurveyService!

    override func setUp() async throws {
        try await super.setUp()
        testUserDefaults = buildUserDefaults(suiteName: "\(userDefaultsSuiteName).launcher")
        testUserDefaults.removePersistentDomain(forName: "\(userDefaultsSuiteName).launcher")
        store = UserDefaultsStore(userDefaults: testUserDefaults)
        store.surveyUserIdentifier = "u-1"
        context = MockSurveyURLApplicationContext()
        service = SurveyService(apiService: nil, userDataStore: store, application: context)
    }

    override func tearDown() async throws {
        testUserDefaults.removePersistentDomain(forName: "\(userDefaultsSuiteName).launcher")
        try await super.tearDown()
    }

    private func externalSurvey(id: Int = 1, url: String?, fields: [String] = []) -> Survey {
        SurveysTestHelpers.makeSurvey(id: id, questions: [
            SurveysTestHelpers.makeSurveyQuestion(type: .externalSurvey, url: url, embeddedDataFields: fields)
        ])
    }

    private func isCompleted(_ id: Int) -> Bool {
        store.isSurveyCompleted(surveyId: id, userIdentifier: "u-1")
    }

    func test_launch_opensExactURL_marksCompleted_callsOnSuccess() {
        let survey = externalSurvey(url: "https://oba.co/s")
        var opened: URL?
        var succeeded = false
        var failed = false
        var launcher = ExternalSurveyLauncher(surveyService: service)
        launcher.urlOpener = { url, completion in opened = url; completion(true) }

        let attempted = launcher.launch(survey: survey, stop: nil,
                                        onSuccess: { succeeded = true },
                                        onFailure: { failed = true })

        expect(attempted).to(beTrue())
        expect(opened?.absoluteString).to(equal("https://oba.co/s"))
        expect(succeeded).to(beTrue())
        expect(failed).to(beFalse())
        expect(self.isCompleted(1)).to(beTrue())
    }

    func test_launch_appendsStopID_whenStopProvided() {
        let survey = externalSurvey(url: "https://oba.co/s", fields: ["stop_id"])
        let stop = SurveysTestHelpers.makeStop(id: "1_99")
        var opened: URL?
        var launcher = ExternalSurveyLauncher(surveyService: service)
        launcher.urlOpener = { url, completion in opened = url; completion(true) }

        launcher.launch(survey: survey, stop: stop, onSuccess: {}, onFailure: {})

        let items = URLComponents(url: opened!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        expect(items.first { $0.name == "stop_id" }?.value).to(equal("1_99"))
    }

    func test_launch_nilURL_doesNotOpen_doesNotComplete_callsOnFailure() {
        let survey = externalSurvey(url: nil)
        var openerCalled = false
        var failed = false
        var launcher = ExternalSurveyLauncher(surveyService: service)
        launcher.urlOpener = { _, _ in openerCalled = true }

        let attempted = launcher.launch(survey: survey, stop: nil,
                                        onSuccess: {},
                                        onFailure: { failed = true })

        expect(attempted).to(beFalse())
        expect(openerCalled).to(beFalse())
        expect(failed).to(beTrue())
        expect(self.isCompleted(1)).to(beFalse())
    }

    func test_launch_openFailure_doesNotComplete_callsOnFailure() {
        let survey = externalSurvey(url: "https://oba.co/s")
        var succeeded = false
        var failed = false
        var launcher = ExternalSurveyLauncher(surveyService: service)
        launcher.urlOpener = { _, completion in completion(false) }

        launcher.launch(survey: survey, stop: nil,
                        onSuccess: { succeeded = true },
                        onFailure: { failed = true })

        expect(succeeded).to(beFalse())
        expect(failed).to(beTrue())
        expect(self.isCompleted(1)).to(beFalse())
    }
}
