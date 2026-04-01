//
//  ExternalSurveyURLBuilderTests.swift
//  OBAKit
//
//  Created by Mohamed Sliem on 19/02/2026.
//

import XCTest
import Nimble
import MapKit
import CoreLocation
@testable import OBAKitCore

final class ExternalSurveyURLBuilderTests: OBATestCase {

    var userDefaultsStore: UserDefaultsStore!
    var applicationContext: MockSurveyURLApplicationContext!
    var builder: ExternalSurveyURLBuilder!

    let testUserID = "test-user-123"

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        userDefaultsStore = UserDefaultsStore(userDefaults: userDefaults)
        applicationContext = MockSurveyURLApplicationContext()

        builder = ExternalSurveyURLBuilder(
            userStore: userDefaultsStore,
            userID: testUserID,
            application: applicationContext
        )
    }

    override func tearDown() {
        builder = nil
        applicationContext = nil
        userDefaultsStore = nil
        super.tearDown()
    }

    // MARK: - buildURL

    func test_buildURL_returnsNil_whenSurveyHasNoQuestions() {
        let survey = SurveysTestHelpers.makeSurvey(questions: [])
        expect(self.builder.buildURL(for: survey, stop: nil)).to(beNil())
    }

    func test_buildURL_returnsNil_whenBaseURLIsInvalid() {
        let survey = SurveysTestHelpers.makeSurvey(questions: [
            SurveysTestHelpers.makeSurveyQuestion(url: "not a valid url %%")
        ])
        expect(self.builder.buildURL(for: survey, stop: nil)).to(beNil())
    }

    func test_buildURL_returnsValidURL_whenNoEmbeddedDataFields() {
        let survey = SurveysTestHelpers.makeSurvey(questions: [
            SurveysTestHelpers.makeSurveyQuestion(url: "https://oba.co/survey")
        ])

        let url = builder.buildURL(for: survey, stop: nil)

        expect(url).toNot(beNil())
        expect(url?.host).to(equal("oba.co"))
        expect(url?.path).to(equal("/survey"))
    }

    func test_buildURL_preservesExistingQueryItems() {
        let survey = SurveysTestHelpers.makeSurvey(questions: [
            SurveysTestHelpers.makeSurveyQuestion(url: "https://oba.co/survey?source=app")
        ])

        let url = builder.buildURL(for: survey, stop: nil)

        expect(url?.absoluteString).to(contain("source=app"))
    }

    // MARK: - user_id

    func test_buildURL_appendsUserID() {
        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["user_id"])])

        let url = builder.buildURL(for: survey, stop: nil)

        expect(self.queryValue(in: url, for: "user_id")).to(equal(testUserID))
    }

    func test_buildURL_appendsEmptyUserID_whenUserIDIsEmpty() {
        builder = ExternalSurveyURLBuilder(
            userStore: userDefaultsStore,
            userID: "",
            application: applicationContext
        )

        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["user_id"])])
        let url = builder.buildURL(for: survey, stop: nil)

        expect(self.queryValue(in: url, for: "user_id")).to(equal(""))
    }

    // MARK: - region_id

    func test_buildURL_appendsRegionID_whenRegionAvailable() {
        applicationContext.currentRegionIdentifier = 1

        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["region_id"])])
        let url = builder.buildURL(for: survey, stop: nil)

        expect(self.queryValue(in: url, for: "region_id")).to(equal("1"))
    }

    func test_buildURL_omitsRegionID_whenNoCurrentRegion() {
        applicationContext.currentRegionIdentifier = nil

        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["region_id"])])
        let url = builder.buildURL(for: survey, stop: nil)

        expect(self.queryValue(in: url, for: "region_id")).to(beNil())
    }

    // MARK: - stop_id

    func test_buildURL_appendsStopID_whenStopProvided() {
        let stop = SurveysTestHelpers.makeStop(id: "1_75403")

        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["stop_id"])])
        let url = builder.buildURL(for: survey, stop: stop)

        expect(self.queryValue(in: url, for: "stop_id")).to(equal("1_75403"))
    }

    func test_buildURL_omitsStopID_whenStopIsNil() {
        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["stop_id"])])

        let url = builder.buildURL(for: survey, stop: nil)

        expect(self.queryValue(in: url, for: "stop_id")).to(beNil())
    }

    // MARK: - route_id

    func test_buildURL_appendsRouteIDs_whenStopHasRoutes() {
        let stop = SurveysTestHelpers.makeStop(routeIDs: ["1_40", "1_44"])

        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["route_id"])])
        let url = builder.buildURL(for: survey, stop: stop)

        expect(self.queryValue(in: url, for: "route_id")).to(equal("1_40,1_44"))
    }

    func test_buildURL_appendsSingleRouteID_whenStopHasOneRoute() {
        let stop = SurveysTestHelpers.makeStop(routeIDs: ["1_40"])

        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["route_id"])])
        let url = builder.buildURL(for: survey, stop: stop)

        expect(self.queryValue(in: url, for: "route_id")).to(equal("1_40"))
        expect(self.queryValue(in: url, for: "route_id")).toNot(contain(","))
    }

    func test_buildURL_omitsRouteID_whenStopHasNoRoutes() {
        let stop = SurveysTestHelpers.makeStop(routeIDs: [])

        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["route_id"])])
        let url = builder.buildURL(for: survey, stop: stop)

        expect(self.queryValue(in: url, for: "route_id")).to(beNil())
    }

    func test_buildURL_omitsRouteID_whenStopIsNil() {
        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["route_id"])])

        let url = builder.buildURL(for: survey, stop: nil)

        expect(self.queryValue(in: url, for: "route_id")).to(beNil())
    }

    // MARK: - recent_stop_ids

    func test_buildURL_appendsRecentStopIDs_whenAvailable() {
        let region = makeRegion()
        userDefaultsStore.addRecentStop(SurveysTestHelpers.makeStop(id: "1_75403"), region: region)
        userDefaultsStore.addRecentStop(SurveysTestHelpers.makeStop(id: "1_29270"), region: region)

        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["recent_stop_ids"])])
        let url = builder.buildURL(for: survey, stop: nil)

        expect(self.queryValue(in: url, for: "recent_stop_ids")).to(contain("1_75403"))
        expect(self.queryValue(in: url, for: "recent_stop_ids")).to(contain("1_29270"))
    }

    func test_buildURL_appendsSingleRecentStopID_whenOneStopInStore() {
        let region = makeRegion()
        userDefaultsStore.addRecentStop(SurveysTestHelpers.makeStop(id: "1_75403"), region: region)

        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["recent_stop_ids"])])
        let url = builder.buildURL(for: survey, stop: nil)

        expect(self.queryValue(in: url, for: "recent_stop_ids")).to(equal("1_75403"))
        expect(self.queryValue(in: url, for: "recent_stop_ids")).toNot(contain(","))
    }

    func test_buildURL_omitsRecentStopIDs_whenListIsEmpty() {
        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["recent_stop_ids"])])

        let url = builder.buildURL(for: survey, stop: nil)

        expect(self.queryValue(in: url, for: "recent_stop_ids")).to(beNil())
    }

    // MARK: - current_location

    func test_buildURL_appendsCurrentLocation_whenLocationAvailable() {
        applicationContext.currentCoordinate = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)

        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["current_location"])])
        let url = builder.buildURL(for: survey, stop: nil)

        expect(self.queryValue(in: url, for: "current_location")).to(equal("47.6062,-122.3321"))
    }

    func test_buildURL_appendsCurrentLocation_atZeroCoordinate() {
        applicationContext.currentCoordinate = CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)

        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["current_location"])])
        let url = builder.buildURL(for: survey, stop: nil)

        expect(self.queryValue(in: url, for: "current_location")).to(equal("0.0,0.0"))
    }

    func test_buildURL_appendsCurrentLocation_withNegativeCoordinates() {
        applicationContext.currentCoordinate = CLLocationCoordinate2D(latitude: -33.8688, longitude: -70.6693)

        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["current_location"])])
        let url = builder.buildURL(for: survey, stop: nil)

        expect(self.queryValue(in: url, for: "current_location")).to(equal("-33.8688,-70.6693"))
    }

    func test_buildURL_omitsCurrentLocation_whenLocationUnavailable() {
        applicationContext.currentCoordinate = nil

        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["current_location"])])
        let url = builder.buildURL(for: survey, stop: nil)

        expect(self.queryValue(in: url, for: "current_location")).to(beNil())
    }

    // MARK: - Unknown Keys

    func test_buildURL_ignoresUnknownEmbeddedFields() {
        let survey = SurveysTestHelpers.makeSurvey(questions: [makeQuestionWithFields(["unknown_key", "another_unknown"])])

        let url = builder.buildURL(for: survey, stop: nil)
        let queryItemNames = URLComponents(url: url!, resolvingAgainstBaseURL: false)?
            .queryItems?.map(\.name) ?? []

        expect(queryItemNames).toNot(contain("unknown_key"))
        expect(queryItemNames).toNot(contain("another_unknown"))
    }

    // MARK: - Multiple Fields

    func test_buildURL_appendsMultipleFields() {
        let region = makeRegion()
        applicationContext.currentRegionIdentifier = 1
        userDefaultsStore.addRecentStop(SurveysTestHelpers.makeStop(id: "1_75403"), region: region)

        let stop = SurveysTestHelpers.makeStop(id: "1_29270")
        let survey = SurveysTestHelpers.makeSurvey(questions: [
            makeQuestionWithFields(["user_id", "region_id", "stop_id", "recent_stop_ids"])
        ])

        let url = builder.buildURL(for: survey, stop: stop)

        expect(self.queryValue(in: url, for: "user_id")).to(equal(testUserID))
        expect(self.queryValue(in: url, for: "region_id")).to(equal("1"))
        expect(self.queryValue(in: url, for: "stop_id")).to(equal("1_29270"))
        expect(self.queryValue(in: url, for: "recent_stop_ids")).to(contain("1_75403"))
    }

    func test_buildURL_appendsAllSixFields_whenAllDataAvailable() {
        let region = makeRegion()
        applicationContext.currentRegionIdentifier = 1
        applicationContext.currentCoordinate = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
        userDefaultsStore.addRecentStop(SurveysTestHelpers.makeStop(id: "1_75403"), region: region)

        let stop = SurveysTestHelpers.makeStop(id: "1_29270", routeIDs: ["1_40", "1_44"])
        let survey = SurveysTestHelpers.makeSurvey(questions: [
            makeQuestionWithFields(["user_id", "region_id", "stop_id", "route_id", "recent_stop_ids", "current_location"])
        ])

        let url = builder.buildURL(for: survey, stop: stop)

        expect(self.queryValue(in: url, for: "user_id")).to(equal(testUserID))
        expect(self.queryValue(in: url, for: "region_id")).to(equal("1"))
        expect(self.queryValue(in: url, for: "stop_id")).to(equal("1_29270"))
        expect(self.queryValue(in: url, for: "route_id")).to(equal("1_40,1_44"))
        expect(self.queryValue(in: url, for: "recent_stop_ids")).to(contain("1_75403"))
        expect(self.queryValue(in: url, for: "current_location")).to(equal("47.6062,-122.3321"))
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
