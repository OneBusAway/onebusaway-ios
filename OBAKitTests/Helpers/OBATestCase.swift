//
//  OBATestCase.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 10/14/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import OBAKit
import OBAKitCore
import OHHTTPStubs

// swiftlint:disable force_cast force_try

open class OBATestCase: XCTestCase {

    var userDefaults: UserDefaults!

    open override func setUp() {
        super.setUp()
        NSTimeZone.default = NSTimeZone(forSecondsFromGMT: 0) as TimeZone
        userDefaults = UserDefaults(suiteName: userDefaultsSuiteName)!
        userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)

        let testName = self.name

        OHHTTPStubs.onStubMissing { (request) in
            let errorMessage = "Missing Stub in \(testName): \(request.url!) — The unit test suite must not make live network requests!"
            print(errorMessage)
        }
    }

    open override func tearDown() {
        super.tearDown()
        OHHTTPStubs.removeAllStubs()
        NSTimeZone.resetSystemTimeZone()
        userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)
    }

    var userDefaultsSuiteName: String {
        return String(describing: self)
    }
}

// MARK: - Network

public extension OBATestCase {

    // MARK: - Obaco Model Service

    var obacoModelService: ObacoModelService {
        return ObacoModelService(apiService: obacoService, dataQueue: OperationQueue())
    }

    // MARK: - Obaco API Service

    var obacoRegionID: Int {
        return 1
    }

    var obacoHost: String {
        return "alerts.example.com"
    }

    var obacoURLString: String {
        return "https://\(obacoHost)"
    }

    var obacoURL: URL {
        return URL(string: obacoURLString)!
    }

    var obacoService: ObacoAPIService {
        return ObacoAPIService(baseURL: obacoURL, apiKey: "org.onebusaway.iphone.test", uuid: "12345-12345-12345-12345-12345", appVersion: "2018.12.31", regionID: obacoRegionID, networkQueue: OperationQueue(), delegate: nil)
    }
}

public extension OBATestCase {

    // MARK: - REST Model Service

    var restModelService: RESTAPIModelService {
        return RESTAPIModelService(apiService: restService, dataQueue: OperationQueue())
    }

    // MARK: - REST API Service

    var host: String {
        return "www.example.com"
    }

    var baseURLString: String {
        return "https://\(host)"
    }

    var baseURL: URL {
        return URL(string: baseURLString)!
    }

    var restService: RESTAPIService {
        let url = URL(string: baseURLString)!
        return RESTAPIService(baseURL: url, apiKey: "org.onebusaway.iphone.test", uuid: "12345-12345-12345-12345-12345", appVersion: "2018.12.31")
    }
}

// MARK: - Network Request Stubbing

public extension OBATestCase {

    func stubAgenciesWithCoverage(host: String) {
        stub(condition: { (request) -> Bool in
            guard let url = request.url else { return false }
            let hostMatches = url.host == host
            let pathMatches = url.path == "/api/where/agencies-with-coverage.json"

            return hostMatches && pathMatches
        }, response: { _ -> OHHTTPStubsResponse in
            return OHHTTPStubsResponse.JSONFile(named: "agencies_with_coverage.json")
        })
    }

    func stubRegions() {
        stub(condition: { (request) -> Bool in
            guard let url = request.url else { return false }
            let hostMatches = url.host == self.regionsHost
            let pathMatches = url.path == self.regionsPath

            return hostMatches && pathMatches
        }, response: { _ -> OHHTTPStubsResponse in
            return OHHTTPStubsResponse.JSONFile(named: "regions-v3.json")
        })
    }

    func stubRegionsJustPugetSound() {
        stub(condition: { (request) -> Bool in
            guard let url = request.url else { return false }
            let hostMatches = url.host == self.regionsHost
            let pathMatches = url.path == self.regionsPath

            return hostMatches && pathMatches
        }, response: { _ -> OHHTTPStubsResponse in
            return OHHTTPStubsResponse.JSONFile(named: "regions-just-puget-sound.json")
        })
    }
}

// MARK: - Regions Services

public extension OBATestCase {
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

    var regionsModelService: RegionsModelService {
        return RegionsModelService(apiService: regionsAPIService, dataQueue: OperationQueue())
    }

    var regionsAPIService: RegionsAPIService {
        return RegionsAPIService(baseURL: regionsURL, apiKey: "org.onebusaway.iphone.test", uuid: "12345-12345-12345-12345-12345", appVersion: "2018.12.31")
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

// MARK: - Data and Models

public extension OBATestCase {

    /// Returns the path to the specified file in the test bundle.
    /// - Parameter fileName: The file name, e.g. "regions.json"
    func path(to fileName: String) -> String {
        Bundle(for: type(of: self)).path(forResource: fileName, ofType: nil)!
    }

    /// Encodes and decodes the provided `Codable` object. Useful for testing roundtripping.
    /// - Parameter type: The object type.
    /// - Parameter model: The object or objects.
    func roundtripCodable<T>(type: T.Type, model: T) throws -> T where T: Codable {
        let encoded = try PropertyListEncoder().encode(model)
        let decoded = try PropertyListDecoder().decode(type, from: encoded)
        return decoded
    }

    /// Loads data from the specified file name, searching within the test bundle.
    /// - Parameter file: The file name to load data from. Example: `stop_data.pb`.
    func loadData(file: String) -> Data {
        NSData(contentsOfFile: path(to: file))! as Data
    }

    /// Loads JSON (as `[String: Any]`) from the specified file name, searching within the test bundle.
    /// - Parameter file: The file name to load data from. Example: `stop_data.json`.
    func loadJSONDictionary(file: String) -> [String: Any] {
        let data = loadData(file: file)
        let json = try! JSONSerialization.jsonObject(with: data, options: [])

        return (json as! [String: Any])
    }
}

// MARK: - Fixture Loading

public extension OBATestCase {

    func loadAlarm(id: String = "1234567890", region: String = "1") throws -> Alarm {
        let dict = ["url": String(format: "http://alerts.example.com/regions/%@/alarms/%@", region, id)]
        return try DictionaryDecoder().decode(Alarm.self, from: dict)
    }

    func loadSomeStops() throws -> [Stop] {
        return try Stop.decodeFromFile(named: "stops_for_location_seattle.json", in: Bundle(for: type(of: self)))
    }

    func loadSomeRegions() throws -> [Region] {
        return try Region.decodeFromFile(named: "regions-v3.json", in: Bundle(for: type(of: self)), skipReferences: true)
    }

    var customMinneapolisRegion: Region {
        let coordinateRegion = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 44.9778, longitude: -93.2650), latitudinalMeters: 1000.0, longitudinalMeters: 1000.0)

        return Region(name: "Custom Region", OBABaseURL: URL(string: "http://www.example.com")!, coordinateRegion: coordinateRegion, contactEmail: "contact@example.com")
    }

    var pugetSoundRegion: Region {
        let regions = try! loadSomeRegions()
        return regions[1]
    }

    var tampaRegion: Region {
        let regions = try! loadSomeRegions()
        return regions[0]
    }
}
