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

public extension OBATestCase {

    // MARK: - Obaco Model Service

    public var obacoModelService: ObacoModelService {
        return ObacoModelService(apiService: obacoService, dataQueue: OperationQueue())
    }

    // MARK: - Obaco API Service

    public var obacoRegionID: String {
        return "1"
    }

    public var obacoHost: String {
        return "alerts.example.com"
    }

    public var obacoURLString: String {
        return "https://\(obacoHost)"
    }

    public var obacoURL: URL {
        return URL(string: obacoURLString)!
    }

    public var obacoService: ObacoService {
        return ObacoService(baseURL: obacoURL, apiKey: "org.onebusaway.iphone.test", uuid: "12345-12345-12345-12345-12345", appVersion: "2018.12.31", regionID: obacoRegionID, networkQueue: OperationQueue())
    }
}

public extension OBATestCase {

    // MARK: - REST Model Service

    public var restModelService: RESTAPIModelService {
        return RESTAPIModelService(apiService: restService, dataQueue: OperationQueue())
    }

    // MARK: - REST API Service

    public var host: String {
        return "www.example.com"
    }

    public var baseURLString: String {
        return "https://\(host)"
    }

    public var baseURL: URL {
        return URL(string: baseURLString)!
    }

    public var restService: RESTAPIService {
        let url = URL(string: baseURLString)!
        return RESTAPIService(baseURL: url, apiKey: "org.onebusaway.iphone.test", uuid: "12345-12345-12345-12345-12345", appVersion: "2018.12.31")
    }
}

public extension OBATestCase {
    public var regionsModelService: RegionsModelService {
        return RegionsModelService(apiService: regionsAPIService, dataQueue: OperationQueue())
    }

    public var regionsAPIService: RegionsAPIService {
        return RegionsAPIService(baseURL: regionsURL, apiKey: "org.onebusaway.iphone.test", uuid: "12345-12345-12345-12345-12345", appVersion: "2018.12.31")
    }
}

public extension Date {
    public static func fromComponents(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) -> Date {
        let timeZone = TimeZone(secondsFromGMT: 0)
        let components = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: timeZone, era: nil, year: year, month: month, day: day, hour: hour, minute: minute, second: second, nanosecond: nil, weekday: nil, weekdayOrdinal: nil, quarter: nil, weekOfMonth: nil, weekOfYear: nil, yearForWeekOfYear: nil)
        return components.date!
    }
}

public extension XCTestCase {
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
    /// - Returns: A decoded array of models.
    /// - Throws: Errors in case of a decoding failure.
    func decodeModels<T>(type: T.Type, json: [String: Any]) throws -> [T] where T: Decodable {
        guard let data = json["data"] as? [String: Any] else {
            throw ModelDecodingError.invalidData
        }

        guard let references = data["references"] as? [String: Any] else {
            throw ModelDecodingError.invalidReferences
        }

        let decodedReferences = try References.decodeReferences(references)

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

// MARK: - Data Loading
public extension OBATestCase {
    public func dataFile(named name: String) -> OHHTTPStubsResponse {
        return file(named: name, contentType: "application/octet-stream")
    }

    public func JSONFile(named name: String) -> OHHTTPStubsResponse {
        return file(named: name, contentType: "application/json")
    }

    public func file(named name: String, contentType: String, statusCode: Int = 200) -> OHHTTPStubsResponse {
        return OHHTTPStubsResponse(
            fileAtPath: OHPathForFile(name, type(of: self))!,
            statusCode: Int32(statusCode),
            headers: ["Content-Type": contentType]
        )
    }
}

// MARK: - Regions API Service
public extension OBATestCase {
    public var regionsHost: String {
        return "regions.example.com"
    }

    public var regionsURLString: String {
        return "https://\(regionsHost)"
    }

    public var regionsURL: URL {
        return URL(string: regionsURLString)!
    }
}

public extension URLComponents {
    public func queryItemValueMatching(name: String) -> String? {
        guard let queryItems = queryItems else {
            return nil
        }

        return queryItems.filter({$0.name == name}).first?.value
    }
}
