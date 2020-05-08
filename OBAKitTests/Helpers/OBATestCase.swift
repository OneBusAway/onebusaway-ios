//
//  OBATestCase.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 10/14/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import OBAKit
@testable import OBAKitCore

open class OBATestCase: XCTestCase {

    var userDefaults: UserDefaults!

    open override func setUp() {
        super.setUp()
        NSTimeZone.default = NSTimeZone(forSecondsFromGMT: 0) as TimeZone
        userDefaults = UserDefaults(suiteName: userDefaultsSuiteName)!
        userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)

        networkQueue = OperationQueue()

        regionsAPIService = RegionsAPIService(baseURL: regionsURL, apiKey: "org.onebusaway.iphone.test", uuid: "12345-12345-12345-12345-12345", appVersion: "2018.12.31", networkQueue: networkQueue, dataLoader: MockDataLoader())

        obacoService = ObacoAPIService(baseURL: obacoURL, apiKey: apiKey, uuid: uuid, appVersion: appVersion, regionID: obacoRegionID, networkQueue: networkQueue, delegate: nil, dataLoader: MockDataLoader())

        restService = RESTAPIService(baseURL: baseURL, apiKey: apiKey, uuid: uuid, appVersion: appVersion, networkQueue: networkQueue, dataLoader: MockDataLoader())
    }

    open override func tearDown() {
        super.tearDown()
        networkQueue.cancelAllOperations()
        NSTimeZone.resetSystemTimeZone()
        userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)
    }

    var userDefaultsSuiteName: String {
        return String(describing: self)
    }

    // MARK: - API Service Data

    let apiKey = "org.onebusaway.iphone.test"
    let uuid = "12345-12345-12345-12345-12345"
    let appVersion = "2018.12.31"

    // MARK: - Network

    var networkQueue: OperationQueue!

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

    // MARK: - Network/REST API Service

    var host: String { "www.example.com" }

    var baseURL: URL { URL(string: "https://\(host)")! }

    var restService: RESTAPIService!

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

    var bundledRegionsPath: String {
        let bundle = Bundle.main
        let path = bundle.path(forResource: "regions", ofType: "json")
        return path!
    }

    var regionsAPIPath: String {
        "/regions-v3.json"
    }
}
