//
//  SurveyServiceExternalURLTests.swift
//  OBAKitTests
//

import Foundation
import Testing
@testable import OBAKitCore

@Suite(.serialized)
final class SurveyServiceExternalURLTests: OBATestCase {

    nonisolated(unsafe) private var testUserDefaults: UserDefaults!
    nonisolated(unsafe) private var store: UserDefaultsStore!
    nonisolated(unsafe) private var context: MockSurveyURLApplicationContext!
    nonisolated(unsafe) private var service: SurveyService!

    override init() async throws {
        try await super.init()

        testUserDefaults = buildUserDefaults(suiteName: "\(userDefaultsSuiteName).exturl")
        testUserDefaults.removePersistentDomain(forName: "\(userDefaultsSuiteName).exturl")
        store = UserDefaultsStore(userDefaults: testUserDefaults)
        store.surveyUserIdentifier = "test-user-123"
        context = MockSurveyURLApplicationContext()
        service = SurveyService(apiService: nil, userDataStore: store, application: context)
    }

    isolated deinit {
        testUserDefaults.removePersistentDomain(forName: "\(userDefaultsSuiteName).exturl")
    }

    @Test func `External survey URL wires builder appending user ID and region`() {
        context.currentRegionIdentifier = 7
        let survey = SurveysTestHelpers.makeSurvey(questions: [
            SurveysTestHelpers.makeSurveyQuestion(url: "https://oba.co/s", embeddedDataFields: ["user_id", "region_id"])
        ])

        let url = service.externalSurveyURL(for: survey, stop: nil)
        #expect(url != nil)
        guard let url else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        #expect(items.first { $0.name == "user_id" }?.value == "test-user-123")
        #expect(items.first { $0.name == "region_id" }?.value == "7")
    }

    @Test func `External survey URL builds without context omitting only context fields`() {
        // No application context: the URL still builds, but the context-dependent
        // embedded fields (region_id, current_location) are omitted while
        // non-context fields (user_id) are still appended.
        let svc = SurveyService(apiService: nil, userDataStore: store, application: nil)
        let survey = SurveysTestHelpers.makeSurvey(questions: [
            SurveysTestHelpers.makeSurveyQuestion(url: "https://oba.co/s", embeddedDataFields: ["user_id", "region_id"])
        ])

        let url = svc.externalSurveyURL(for: survey, stop: nil)
        #expect(url != nil)
        guard let url else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        #expect(items.first { $0.name == "user_id" }?.value == "test-user-123")
        #expect(!items.contains { $0.name == "region_id" })
    }
}
