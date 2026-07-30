//
//  OBATestCase.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import OBAKit
@testable import OBAKitCore

/// Pins the process to GMT once, for the lifetime of the test bundle.
///
/// This used to be set in `setUp` and undone in `tearDown`. `NSTimeZone.default`
/// is process-global, so under Swift Testing — which may run suites
/// concurrently — one suite's teardown could reset the zone out from under
/// another suite's running test. Setting it once and never resetting it removes
/// the race entirely, and is behaviourally identical for these tests: every
/// suite that inherited `OBATestCase` wanted GMT, and no test reads the
/// system zone (the Weather tests set their own calendar's zone explicitly).
private let pinnedToGMT: Void = {
    NSTimeZone.default = NSTimeZone(forSecondsFromGMT: 0) as TimeZone
}()

// Main-actor-isolated (inherited by every test suite that uses it): the
// frameworks under test are largely @MainActor, and this annotation makes the
// async initializer and any async test methods hop to main.
//
// This is a plain base class, not a suite in its own right — it declares no
// `@Test` methods. Swift Testing instantiates the *subclass* fresh for each of
// its test functions, so `init` runs per test exactly as `setUp` used to.
@MainActor
class OBATestCase {

    var userDefaults: UserDefaults!

    /// Replaces `setUp`. Swift Testing calls this once per test function.
    init() async throws {
        _ = pinnedToGMT

        userDefaults = buildUserDefaults()
        userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)

        regionsAPIService = buildRegionsAPIService()

        obacoService = buildObacoService()

        restService = buildRESTService()
    }

    /// Replaces `tearDown`. Deliberately `nonisolated` and reading only
    /// `nonisolated` stored state, so it needs no `isolated deinit`.
    deinit {
        UserDefaults.standard.removePersistentDomain(forName: userDefaultsSuiteName)
    }

    // MARK: - Test identity

    /// The running test's name. Stands in for `XCTestCase.name`, which the many
    /// `MockDataLoader(testName: name)` call sites used to get a label for
    /// unmocked-URL failure messages.
    nonisolated var name: String {
        Test.current?.name ?? "OBAKitTests"
    }

    // MARK: - User Defaults

    func buildUserDefaults(suiteName: String? = nil) -> UserDefaults {
        UserDefaults(suiteName: suiteName ?? userDefaultsSuiteName)!
    }

    /// A defaults domain unique to this instance — and therefore, since Swift
    /// Testing builds a fresh instance per test, unique to each test.
    ///
    /// It was previously `String(describing: self)`, i.e. one domain shared by
    /// every test in a class. That was safe only because XCTest ran them one at
    /// a time; a per-instance domain holds regardless of how tests are
    /// scheduled. Suites that derive their own domains from this one (the
    /// Survey tests append `.state`, `.prioritization`, …) keep working, since
    /// this is a stored constant rather than a freshly computed value.
    nonisolated let userDefaultsSuiteName = "OBAKitTests.\(UUID().uuidString)"

    // MARK: - API Service Data

    let apiKey = "org.onebusaway.iphone.test"
    let uuid = "12345-12345-12345-12345-12345"
    let appVersion = "2018.12.31"

    // MARK: - Network/Obaco

    var obacoRegionID: Int {
        return 1
    }

    var obacoHost: String {
        return "alerts.example.com"
    }

    var obacoURL: URL {
        return URL(string: "https://\(obacoHost)")!
    }

    var obacoService: ObacoAPIService!

    func buildObacoService(networkQueue: OperationQueue? = nil, dataLoader: MockDataLoader? = nil) -> ObacoAPIService {
        let config = APIServiceConfiguration(baseURL: obacoURL, apiKey: apiKey, uuid: uuid, appVersion: appVersion, regionIdentifier: obacoRegionID)
        return ObacoAPIService(regionID: obacoRegionID, delegate: nil, configuration: config, dataLoader: dataLoader ?? MockDataLoader(testName: name))
    }

    // MARK: - Network/REST API Service

    let pugetSoundRegionIdentifier = 1

    var host: String { "www.example.com" }

    var baseURL: URL { URL(string: "https://\(host)")! }

    var surveyBaseURL: URL { URL(string: "https://onebusaway.co")! }

    var restService: RESTAPIService!

    func buildRESTService(dataLoader: MockDataLoader? = nil) -> RESTAPIService {
        let config = APIServiceConfiguration(baseURL: baseURL, apiKey: apiKey, uuid: uuid, appVersion: appVersion, regionIdentifier: pugetSoundRegionIdentifier, surveyBaseURL: surveyBaseURL)
        return RESTAPIService(config, dataLoader: dataLoader ?? MockDataLoader(testName: name))
    }

    // MARK: - Network Request Stubbing

    func stubAgenciesWithCoverage(dataLoader: MockDataLoader, baseURL: URL? = nil) {

        let host = baseURL?.absoluteString ?? "https://www.example.com/"

        dataLoader.mock(
            URLString: "\(host)api/where/agencies-with-coverage.json",
            with: Fixtures.loadData(file: "agencies_with_coverage.json")
        )
    }

    func stubRegions(dataLoader: MockDataLoader, fixtureFile: String = "regions-v3.json") {
        dataLoader.mock(
            URLString: "https://regions.example.com/regions-v3.json",
            with: Fixtures.loadData(file: fixtureFile)
        )
    }

    func stubRegionsJustPugetSound(dataLoader: MockDataLoader) {
        dataLoader.mock(
            URLString: "https://regions.example.com/regions-v3.json",
            with: Fixtures.loadData(file: "regions-just-puget-sound.json")
        )
    }

    // MARK: - Regions Services

    var regionsHost: String {
        return "regions.example.com"
    }

    var regionsPath: String {
        return "/regions-v3.json"
    }

    var regionsURLString: String {
        return "https://\(regionsHost)"
    }

    var regionsURL: URL {
        return URL(string: regionsURLString)!
    }

    var regionsAPIService: RegionsAPIService!

    func buildRegionsAPIService(dataLoader: MockDataLoader? = nil) -> RegionsAPIService {
        let configuration = APIServiceConfiguration(
            baseURL: regionsURL,
            apiKey: "org.onebusaway.iphone.test",
            uuid: "12345-12345-12345-12345-12345",
            appVersion: "2018.12.31",
            regionIdentifier: nil
        )

        return RegionsAPIService(
            configuration,
            dataLoader: dataLoader ?? MockDataLoader(testName: name)
        )
    }

    var bundledRegionsPath: String {
        let bundle = Bundle.main
        let path = bundle.path(forResource: "regions", ofType: "json")
        return path!
    }

    var regionsAPIPath: String {
        "/regions-v3.json"
    }

    // MARK: - Application

    /// Builds a fully-wired `Application` against stubbed regions +
    /// agencies-with-coverage for tests that need the real object graph
    /// (e.g. anything that constructs a view controller which reads
    /// `application.regionsService` / stores at init time).
    ///
    /// Test suites still own their own `queue` because a per-suite queue keeps
    /// `cancelAllOperations()` scoped to one test — Swift Testing builds a fresh
    /// suite instance per test function and releases it afterwards, so the
    /// cancellation lands in that instance's `deinit`.
    func buildApplication(queue: OperationQueue, dataLoader: MockDataLoader) -> Application {
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)

        let locManager = MockAuthorizedLocationManager(
            updateLocation: TestData.mockSeattleLocation,
            updateHeading: TestData.mockHeading
        )
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)

        let config = AppConfig(
            regionsBaseURL: regionsURL,
            apiKey: apiKey,
            appVersion: appVersion,
            userDefaults: userDefaults,
            analytics: AnalyticsMock(),
            queue: queue,
            locationService: locationService,
            bundledRegionsFilePath: bundledRegionsPath,
            regionsAPIPath: regionsAPIPath,
            dataLoader: dataLoader,
            fixedRegionName: Fixtures.pugetSoundRegion.name
        )

        return Application(config: config)
    }

    // MARK: - Surveys

    @MainActor
    func buildSurveyService(dataLoader: MockDataLoader? = nil) -> SurveyService {
        let config = APIServiceConfiguration(
            baseURL: baseURL,
            apiKey: apiKey,
            uuid: uuid,
            appVersion: appVersion,
            regionIdentifier: pugetSoundRegionIdentifier,
            surveyBaseURL: surveyBaseURL
        )
        let apiService = RESTAPIService(config, dataLoader: dataLoader ?? MockDataLoader(testName: name))
        let store = UserDefaultsStore(userDefaults: buildUserDefaults())
        return SurveyService(apiService: apiService, userDataStore: store)
    }

}
