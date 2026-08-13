//
//  ExternalSurveyURLBuilderTests.swift
//  OBAKit
//
//  Created by Mohamed Sliem on 19/02/2026.
//

import Foundation
import Testing
import MapKit
import CoreLocation
@testable import OBAKitCore

@Suite(.serialized)
final class ExternalSurveyURLBuilderTests: OBATestCase {

    var userDefaultsStore: UserDefaultsStore!
    var applicationContext: MockSurveyURLApplicationContext!
    var builder: ExternalSurveyURLBuilder!

    let testUserID = "test-user-123"

    // MARK: - Setup

    override init() async throws {
        try await super.init()

        userDefaultsStore = UserDefaultsStore(userDefaults: userDefaults)
        applicationContext = MockSurveyURLApplicationContext()

        builder = ExternalSurveyURLBuilder(
            userStore: userDefaultsStore,
            userID: testUserID,
            application: applicationContext
        )
    }

    // MARK: - buildURL

    @Test func `Build URL returns nil when survey has no questions`() {
        let survey = SurveysTestHelpers.makeSurvey(questions: [])
        #expect(self.builder.buildURL(for: survey, stop: nil) == nil)
    }

    @Test func `Build URL returns nil when base URL is invalid`() {
        let survey = SurveysTestHelpers.makeSurvey(questions: [
            SurveysTestHelpers.makeSurveyQuestion(url: "not a valid url %%")
        ])
        #expect(self.builder.buildURL(for: survey, stop: nil) == nil)
    }

    @Test func `Build URL returns valid URL when no embedded data fields`() {
        let survey = SurveysTestHelpers.makeSurvey(questions: [
            SurveysTestHelpers.makeSurveyQuestion(url: "https://oba.co/survey")
        ])

        let url = builder.buildURL(for: survey, stop: nil)

        #expect(url != nil)
        #expect(url?.host == "oba.co")
        #expect(url?.path == "/survey")
        #expect(url?.absoluteString == "https://oba.co/survey")
    }

    @Test func `Build URL preserves existing query items`() {
        let survey = SurveysTestHelpers.makeSurvey(questions: [
            SurveysTestHelpers.makeSurveyQuestion(url: "https://oba.co/survey?source=app")
        ])

        let url = builder.buildURL(for: survey, stop: nil)

        #expect(url?.absoluteString.contains("source=app") == true)
    }

    // MARK: - user_id

    @Test func `Build URL appends user ID`() {
        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["user_id"])])

        let url = builder.buildURL(for: survey, stop: nil)

        #expect(self.queryValue(in: url, for: "user_id") == testUserID)
    }

    @Test func `Build URL appends empty user ID when user ID is empty`() {
        builder = ExternalSurveyURLBuilder(
            userStore: userDefaultsStore,
            userID: "",
            application: applicationContext
        )

        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["user_id"])])
        let url = builder.buildURL(for: survey, stop: nil)

        #expect(self.queryValue(in: url, for: "user_id") == "")
    }

    // MARK: - region_id

    @Test func `Build URL appends region ID when region available`() {
        applicationContext.currentRegionIdentifier = 1

        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["region_id"])])
        let url = builder.buildURL(for: survey, stop: nil)

        #expect(self.queryValue(in: url, for: "region_id") == "1")
    }

    @Test func `Build URL omits region ID when no current region`() {
        applicationContext.currentRegionIdentifier = nil

        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["region_id"])])
        let url = builder.buildURL(for: survey, stop: nil)

        #expect(self.queryValue(in: url, for: "region_id") == nil)
    }

    // MARK: - stop_id

    @Test func `Build URL appends stop ID when stop provided`() {
        let stop = SurveysTestHelpers.makeStop(id: "1_75403")

        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["stop_id"])])
        let url = builder.buildURL(for: survey, stop: stop)

        #expect(self.queryValue(in: url, for: "stop_id") == "1_75403")
    }

    @Test func `Build URL omits stop ID when stop is nil`() {
        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["stop_id"])])

        let url = builder.buildURL(for: survey, stop: nil)

        #expect(self.queryValue(in: url, for: "stop_id") == nil)
    }

    // MARK: - route_id

    @Test func `Build URL appends route IDs when stop has routes`() {
        let stop = SurveysTestHelpers.makeStop(routeIDs: ["1_40", "1_44"])

        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["route_id"])])
        let url = builder.buildURL(for: survey, stop: stop)

        #expect(self.queryValue(in: url, for: "route_id") == "1_40,1_44")
    }

    @Test func `Build URL appends single route ID when stop has one route`() {
        let stop = SurveysTestHelpers.makeStop(routeIDs: ["1_40"])

        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["route_id"])])
        let url = builder.buildURL(for: survey, stop: stop)

        #expect(self.queryValue(in: url, for: "route_id") == "1_40")
        #expect(self.queryValue(in: url, for: "route_id")?.contains(",") == false)
    }

    @Test func `Build URL omits route ID when stop has no routes`() {
        let stop = SurveysTestHelpers.makeStop(routeIDs: [])

        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["route_id"])])
        let url = builder.buildURL(for: survey, stop: stop)

        #expect(self.queryValue(in: url, for: "route_id") == nil)
    }

    @Test func `Build URL omits route ID when stop is nil`() {
        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["route_id"])])

        let url = builder.buildURL(for: survey, stop: nil)

        #expect(self.queryValue(in: url, for: "route_id") == nil)
    }

    // MARK: - recent_stop_ids

    @Test func `Build URL appends recent stop IDs when available`() {
        let region = makeRegion()
        userDefaultsStore.addRecentStop(SurveysTestHelpers.makeStop(id: "1_75403"), region: region)
        userDefaultsStore.addRecentStop(SurveysTestHelpers.makeStop(id: "1_29270"), region: region)

        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["recent_stop_ids"])])
        let url = builder.buildURL(for: survey, stop: nil)

        #expect(self.queryValue(in: url, for: "recent_stop_ids")?.contains("1_75403") == true)
        #expect(self.queryValue(in: url, for: "recent_stop_ids")?.contains("1_29270") == true)
    }

    @Test func `Build URL appends single recent stop ID when one stop in store`() {
        let region = makeRegion()
        userDefaultsStore.addRecentStop(SurveysTestHelpers.makeStop(id: "1_75403"), region: region)

        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["recent_stop_ids"])])
        let url = builder.buildURL(for: survey, stop: nil)

        #expect(self.queryValue(in: url, for: "recent_stop_ids") == "1_75403")
        #expect(self.queryValue(in: url, for: "recent_stop_ids")?.contains(",") == false)
    }

    @Test func `Build URL omits recent stop IDs when list is empty`() {
        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["recent_stop_ids"])])

        let url = builder.buildURL(for: survey, stop: nil)

        #expect(self.queryValue(in: url, for: "recent_stop_ids") == nil)
    }

    // MARK: - current_location

    @Test func `Build URL appends current location when location available`() {
        applicationContext.currentCoordinate = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)

        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["current_location"])])
        let url = builder.buildURL(for: survey, stop: nil)

        #expect(self.queryValue(in: url, for: "current_location") == "47.6062,-122.3321")
    }

    @Test func `Build URL appends current location at zero coordinate`() {
        applicationContext.currentCoordinate = CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)

        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["current_location"])])
        let url = builder.buildURL(for: survey, stop: nil)

        #expect(self.queryValue(in: url, for: "current_location") == "0.0,0.0")
    }

    @Test func `Build URL appends current location with negative coordinates`() {
        applicationContext.currentCoordinate = CLLocationCoordinate2D(latitude: -33.8688, longitude: -70.6693)

        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["current_location"])])
        let url = builder.buildURL(for: survey, stop: nil)

        #expect(self.queryValue(in: url, for: "current_location") == "-33.8688,-70.6693")
    }

    @Test func `Build URL omits current location when location unavailable`() {
        applicationContext.currentCoordinate = nil

        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["current_location"])])
        let url = builder.buildURL(for: survey, stop: nil)

        #expect(self.queryValue(in: url, for: "current_location") == nil)
    }

    // MARK: - Unknown Keys

    @Test func `Build URL ignores unknown embedded fields`() {
        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["unknown_key", "another_unknown"])])

        let url = builder.buildURL(for: survey, stop: nil)
        let queryItemNames = URLComponents(url: url!, resolvingAgainstBaseURL: false)?
            .queryItems?.map(\.name) ?? []

        #expect(!queryItemNames.contains("unknown_key"))
        #expect(!queryItemNames.contains("another_unknown"))
    }

    // MARK: - Multiple Fields

    @Test func `Build URL appends multiple fields`() {
        let region = makeRegion()
        applicationContext.currentRegionIdentifier = 1
        userDefaultsStore.addRecentStop(SurveysTestHelpers.makeStop(id: "1_75403"), region: region)

        let stop = SurveysTestHelpers.makeStop(id: "1_29270")
        let survey = SurveysTestHelpers.makeSurvey(questions: [
            makeQuestionWithFields(["user_id", "region_id", "stop_id", "recent_stop_ids"])
        ])

        let url = builder.buildURL(for: survey, stop: stop)

        #expect(self.queryValue(in: url, for: "user_id") == testUserID)
        #expect(self.queryValue(in: url, for: "region_id") == "1")
        #expect(self.queryValue(in: url, for: "stop_id") == "1_29270")
        #expect(self.queryValue(in: url, for: "recent_stop_ids")?.contains("1_75403") == true)
    }

    @Test func `Build URL appends all six fields when all data available`() {
        let region = makeRegion()
        applicationContext.currentRegionIdentifier = 1
        applicationContext.currentCoordinate = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
        userDefaultsStore.addRecentStop(SurveysTestHelpers.makeStop(id: "1_75403"), region: region)

        let stop = SurveysTestHelpers.makeStop(id: "1_29270", routeIDs: ["1_40", "1_44"])
        let survey = SurveysTestHelpers.makeSurvey(questions: [
            makeQuestionWithFields(["user_id", "region_id", "stop_id", "route_id", "recent_stop_ids", "current_location"])
        ])

        let url = builder.buildURL(for: survey, stop: stop)

        #expect(self.queryValue(in: url, for: "user_id") == testUserID)
        #expect(self.queryValue(in: url, for: "region_id") == "1")
        #expect(self.queryValue(in: url, for: "stop_id") == "1_29270")
        #expect(self.queryValue(in: url, for: "route_id") == "1_40,1_44")
        #expect(self.queryValue(in: url, for: "recent_stop_ids")?.contains("1_75403") == true)
        #expect(self.queryValue(in: url, for: "current_location") == "47.6062,-122.3321")
    }

    // MARK: - Lifecycle

    @Test func `Builder does not retain application context`() {
        weak var weakContext: MockSurveyURLApplicationContext?
        let localBuilder: ExternalSurveyURLBuilder = {
            let ctx = MockSurveyURLApplicationContext()
            ctx.currentRegionIdentifier = 5
            weakContext = ctx
            return ExternalSurveyURLBuilder(
                userStore: userDefaultsStore,
                userID: "u",
                application: ctx
            )
        }()

        // ctx is released at the end of the closure. If the builder held a strong
        // reference, weakContext would still be non-nil.
        #expect(weakContext == nil)

        // And with the context gone, region_id resolves to nil instead of crashing.
        let survey = SurveysTestHelpers.makeSurvey(questions: [
            SurveysTestHelpers.makeSurveyQuestion(url: "https://oba.co/s", embeddedDataFields: ["region_id"])
        ])
        #expect(self.queryValue(in: localBuilder.buildURL(for: survey, stop: nil), for: "region_id") == nil)
    }

    // MARK: - Helpers

    private func makeQuestionWithFields(_ fields: [String], baseURL: String = "https://oba.co/survey") -> SurveyQuestion {
        SurveysTestHelpers.makeSurveyQuestion(url: baseURL, embeddedDataFields: fields)
    }

    private func makeRegion(id: Int = 1) -> Region {
        Region(
            name: "Puget Sound",
            OBABaseURL: URL(string: "https://api.pugetsound.onebusaway.org")!,
            coordinateRegion: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321),
                span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
            ),
            contactEmail: "contact@onebusaway.org",
            regionIdentifier: id
        )
    }

    private func queryValue(in url: URL?, for key: String) -> String? {
        guard let url else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == key })?
            .value
    }
}
