//
//  OBATestCase.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 10/14/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import OBAKit
import OHHTTPStubs

// swiftlint:disable force_cast force_try

open class OBATestCase: XCTestCase {

    var userDefaults: UserDefaults!

    open override func setUp() {
        super.setUp()
        NSTimeZone.default = NSTimeZone(forSecondsFromGMT: 0) as TimeZone
        userDefaults = UserDefaults(suiteName: userDefaultsSuiteName)!
        userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)
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

    var obacoRegionID: String {
        return "1"
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

    var obacoService: ObacoService {
        return ObacoService(baseURL: obacoURL, apiKey: "org.onebusaway.iphone.test", uuid: "12345-12345-12345-12345-12345", appVersion: "2018.12.31", regionID: obacoRegionID, networkQueue: OperationQueue(), delegate: nil)
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

// MARK: - Regions Services

public extension OBATestCase {
    var regionsHost: String {
        return "regions.example.com"
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
}

// MARK: - Data and Models

public extension OBATestCase {

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
        let path = OHPathForFile(file, type(of: self))!
        let data = NSData(contentsOfFile: path)!

        return data as Data
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
}
