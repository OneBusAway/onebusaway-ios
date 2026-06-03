//
//  SurveyServiceExternalURLTests.swift
//  OBAKitTests
//

import XCTest
import Nimble
@testable import OBAKitCore

@MainActor
final class SurveyServiceExternalURLTests: OBATestCase {

    nonisolated(unsafe) private var testUserDefaults: UserDefaults!
    nonisolated(unsafe) private var store: UserDefaultsStore!
    nonisolated(unsafe) private var context: MockSurveyURLApplicationContext!
    nonisolated(unsafe) private var service: SurveyService!

    override func setUp() {
        super.setUp()
        testUserDefaults = buildUserDefaults(suiteName: "\(userDefaultsSuiteName).exturl")
        testUserDefaults.removePersistentDomain(forName: "\(userDefaultsSuiteName).exturl")
        store = UserDefaultsStore(userDefaults: testUserDefaults)
        store.surveyUserIdentifier = "test-user-123"
        context = MockSurveyURLApplicationContext()
        service = SurveyService(apiService: nil, userDataStore: store, application: context)
    }

    override func tearDown() {
        testUserDefaults.removePersistentDomain(forName: "\(userDefaultsSuiteName).exturl")
        super.tearDown()
    }

    func test_externalSurveyURL_wiresBuilder_appendingUserIDAndRegion() {
        context.currentRegionIdentifier = 7
        let survey = SurveysTestHelpers.makeSurvey(questions: [
            SurveysTestHelpers.makeSurveyQuestion(url: "https://oba.co/s", embeddedDataFields: ["user_id", "region_id"])
        ])

        let url = service.externalSurveyURL(for: survey, stop: nil)
        expect(url).toNot(beNil())
        guard let url else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        expect(items.first { $0.name == "user_id" }?.value).to(equal("test-user-123"))
        expect(items.first { $0.name == "region_id" }?.value).to(equal("7"))
    }

    func test_externalSurveyURL_returnsNil_whenNoContext() {
        let svc = SurveyService(apiService: nil, userDataStore: store, application: nil)
        let survey = SurveysTestHelpers.makeSurvey(questions: [
            SurveysTestHelpers.makeSurveyQuestion(url: "https://oba.co/s")
        ])
        expect(svc.externalSurveyURL(for: survey, stop: nil)).to(beNil())
    }
}
