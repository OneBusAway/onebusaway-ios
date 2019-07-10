//
//  TestCaseExtensions.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 11/19/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import XCTest
import OHHTTPStubs
@testable import OBAKit

// swiftlint:disable force_cast force_try

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
        return ObacoService(baseURL: obacoURL, apiKey: "org.onebusaway.iphone.test", uuid: "12345-12345-12345-12345-12345", appVersion: "2018.12.31", regionID: obacoRegionID, networkQueue: OperationQueue())
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

public extension OBATestCase {
    var regionsModelService: RegionsModelService {
        return RegionsModelService(apiService: regionsAPIService, dataQueue: OperationQueue())
    }

    var regionsAPIService: RegionsAPIService {
        return RegionsAPIService(baseURL: regionsURL, apiKey: "org.onebusaway.iphone.test", uuid: "12345-12345-12345-12345-12345", appVersion: "2018.12.31")
    }
}

public extension Date {
    static func fromComponents(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) -> Date {
        let timeZone = TimeZone(secondsFromGMT: 0)
        let components = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: timeZone, era: nil, year: year, month: month, day: day, hour: hour, minute: minute, second: second, nanosecond: nil, weekday: nil, weekdayOrdinal: nil, quarter: nil, weekOfMonth: nil, weekOfYear: nil, yearForWeekOfYear: nil)
        return components.date!
    }
}

public extension XCTestCase {

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

// MARK: - Data Loading
public extension OBATestCase {
    func dataFile(named name: String) -> OHHTTPStubsResponse {
        return file(named: name, contentType: "application/octet-stream")
    }

    func JSONFile(named name: String) -> OHHTTPStubsResponse {
        return file(named: name, contentType: "application/json")
    }

    func file(named name: String, contentType: String, statusCode: Int = 200) -> OHHTTPStubsResponse {
        return OHHTTPStubsResponse(
            fileAtPath: OHPathForFile(name, type(of: self))!,
            statusCode: Int32(statusCode),
            headers: ["Content-Type": contentType]
        )
    }
}

// MARK: - Regions API Service
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
}

public extension URLComponents {
    func queryItemValueMatching(name: String) -> String? {
        guard let queryItems = queryItems else {
            return nil
        }

        return queryItems.filter({$0.name == name}).first?.value
    }
}
