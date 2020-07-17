//
//  OBATestCase.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import OBAKit
@testable import OBAKitCore

open class OBATestCase: XCTestCase {

    var userDefaults: UserDefaults!

    open override func setUp() {
        super.setUp()
        NSTimeZone.default = NSTimeZone(forSecondsFromGMT: 0) as TimeZone
        userDefaults = buildUserDefaults()
        userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)

        regionsAPIService = buildRegionsAPIService()

        obacoService = buildObacoService()

        restService = buildRESTService()
    }

    open override func tearDown() {
        super.tearDown()
        regionsAPIService.networkQueue.cancelAllOperations()
        obacoService.networkQueue.cancelAllOperations()
        restService.networkQueue.cancelAllOperations()
        NSTimeZone.resetSystemTimeZone()
        userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)
    }

    // MARK: - User Defaults

    func buildUserDefaults(suiteName: String? = nil) -> UserDefaults {
        UserDefaults(suiteName: suiteName ?? userDefaultsSuiteName)!
    }

    var userDefaultsSuiteName: String {
        return String(describing: self)
    }

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
        ObacoAPIService(
            baseURL: obacoURL,
            apiKey: apiKey,
            uuid: uuid,
            appVersion: appVersion,
            regionID: obacoRegionID,
            networkQueue: networkQueue ?? OperationQueue(),
            delegate: nil,
            dataLoader: dataLoader ?? MockDataLoader(testName: name)
        )
    }

    // MARK: - Network/REST API Service

    var host: String { "www.example.com" }

    var baseURL: URL { URL(string: "https://\(host)")! }

    var restService: RESTAPIService!

    func buildRESTService(networkQueue: OperationQueue? = nil, dataLoader: MockDataLoader? = nil) -> RESTAPIService {
        RESTAPIService(
            baseURL: baseURL,
            apiKey: apiKey,
            uuid: uuid,
            appVersion: appVersion,
            networkQueue: networkQueue ?? OperationQueue(),
            dataLoader: dataLoader ?? MockDataLoader(testName: name)
        )
    }

    // MARK: - Network Request Stubbing

    func stubAgenciesWithCoverage(dataLoader: MockDataLoader, baseURL: URL? = nil) {

        let host = baseURL?.absoluteString ?? "https://www.example.com/"

        dataLoader.mock(
            URLString: "\(host)api/where/agencies-with-coverage.json",
            with: Fixtures.loadData(file: "agencies_with_coverage.json")
        )
    }

    func stubRegions(dataLoader: MockDataLoader) {
        dataLoader.mock(
            URLString: "https://regions.example.com/regions-v3.json",
            with: Fixtures.loadData(file: "regions-v3.json")
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

    func buildRegionsAPIService(networkQueue: OperationQueue? = nil, dataLoader: MockDataLoader? = nil) -> RegionsAPIService {
        RegionsAPIService(
            baseURL: regionsURL,
            apiKey: "org.onebusaway.iphone.test",
            uuid: "12345-12345-12345-12345-12345",
            appVersion: "2018.12.31",
            networkQueue: networkQueue ?? OperationQueue(),
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
}
