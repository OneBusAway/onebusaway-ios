//
//  SurveyServiceExternalURLTests.swift
//  OBAKitTests
//

import XCTest
import Nimble
@testable import OBAKitCore

final class SurveyServiceExternalURLTests: OBATestCase {

    nonisolated(unsafe) private var testUserDefaults: UserDefaults!
    nonisolated(unsafe) private var store: UserDefaultsStore!
    nonisolated(unsafe) private var context: MockSurveyURLApplicationContext!
    nonisolated(unsafe) private var service: SurveyService!

    override func setUp() async throws {
        try await super.setUp()
        testUserDefaults = buildUserDefaults(suiteName: "\(userDefaultsSuiteName).exturl")
        testUserDefaults.removePersistentDomain(forName: "\(userDefaultsSuiteName).exturl")
        store = UserDefaultsStore(userDefaults: testUserDefaults)
        store.surveyUserIdentifier = "test-user-123"
        context = MockSurveyURLApplicationContext()
        service = SurveyService(apiService: nil, userDataStore: store, application: context)
    }

    override func tearDown() async throws {
        testUserDefaults.removePersistentDomain(forName: "\(userDefaultsSuiteName).exturl")
        try await super.tearDown()
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

    func test_externalSurveyURL_buildsWithoutContext_omittingOnlyContextFields() {
        // No application context: the URL still builds, but the context-dependent
        // embedded fields (region_id, current_location) are omitted while
        // non-context fields (user_id) are still appended.
        let svc = SurveyService(apiService: nil, userDataStore: store, application: nil)
        let survey = SurveysTestHelpers.makeSurvey(questions: [
            SurveysTestHelpers.makeSurveyQuestion(url: "https://oba.co/s", embeddedDataFields: ["user_id", "region_id"])
        ])

        let url = svc.externalSurveyURL(for: survey, stop: nil)
        expect(url).toNot(beNil())
        guard let url else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        expect(items.first { $0.name == "user_id" }?.value).to(equal("test-user-123"))
        expect(items.contains { $0.name == "region_id" }).to(beFalse())
    }
}
