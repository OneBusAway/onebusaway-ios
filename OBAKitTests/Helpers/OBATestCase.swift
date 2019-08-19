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

    func roundtripCodable<T>(type: T.Type, model: T) throws -> T where T: Codable {
        let encoded = try PropertyListEncoder().encode(model)
        let decoded = try PropertyListDecoder().decode(type, from: encoded)
        return decoded
    }

    func loadData(file: String) -> Data {
        let path = OHPathForFile(file, type(of: self))!
        let data = NSData(contentsOfFile: path)!

        return data as Data
    }

    func loadJSONDictionary(file: String) -> [String: Any] {
        let data = loadData(file: file)
        let json = try! JSONSerialization.jsonObject(with: data, options: [])

        return (json as! [String: Any])
    }

    /// Decodes models of type T from the supplied JSON. The JSON should be the full contents of a server response, including References.
    ///
    /// - Parameters:
    ///   - type: The model type
    ///   - json: The JSON data to decode from.
    ///   - skipReferences: Don't try decoding references. Used for Regions.
    /// - Returns: A decoded array of models.
    /// - Throws: Errors in case of a decoding failure.
    func decodeModels<T>(type: T.Type, json: [String: Any], skipReferences: Bool = false) throws -> [T] where T: Decodable {
        guard let data = json["data"] as? [String: Any] else {
            throw ModelDecodingError.invalidData
        }

        let decodedReferences: References?

        if skipReferences {
            decodedReferences = nil
        }
        else {
            guard let references = data["references"] as? [String: Any] else {
                throw ModelDecodingError.invalidReferences
            }

            decodedReferences = try References.decodeReferences(references)
        }

        let modelDicts: [[String: Any]]
        if let list = data["list"] as? [[String: Any]] {
            modelDicts = list
        }
        else if let entry = data["entry"] as? [String: Any] {
            modelDicts = [entry]
        }
        else {
            throw ModelDecodingError.invalidModelList
        }

        let models = try DictionaryDecoder.decodeModels(modelDicts, references: decodedReferences, type: type)

        return models
    }
}

// MARK: - Fixture Loading

public extension OBATestCase {
    func loadSomeStops() throws -> [Stop] {
        let json = loadJSONDictionary(file: "stops_for_location_seattle.json")
        return try decodeModels(type: Stop.self, json: json)
    }

    func loadSomeRegions() throws -> [Region] {
        let json = loadJSONDictionary(file: "regions-v3.json")
        return try decodeModels(type: Region.self, json: json, skipReferences: true)
    }

    var customMinneapolisRegion: Region {
        let coordinateRegion = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 44.9778, longitude: -93.2650), latitudinalMeters: 1000.0, longitudinalMeters: 1000.0)

        return Region(name: "Custom Region", OBABaseURL: URL(string: "http://www.example.com")!, coordinateRegion: coordinateRegion, contactEmail: "contact@example.com")
    }
}
