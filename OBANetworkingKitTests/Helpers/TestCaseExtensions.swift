//
//  TestCaseExtensions.swift
//  OBANetworkingKitTests
//
//  Created by Aaron Brethorst on 10/5/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import OHHTTPStubs
import OBANetworkingKit

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
}

public protocol OperationTest { }
public extension OperationTest where Self: XCTestCase {

    // MARK: - REST Model Service

    public var restModelService: RESTAPIModelService {
        return RESTAPIModelService(apiService: restService, dataQueue: OperationQueue())
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

    // MARK: - Regions API Service

    public var regionsHost: String {
        return "regions.example.com"
    }

    public var regionsURLString: String {
        return "https://\(regionsHost)"
    }

    public var regionsURL: URL {
        return URL(string: regionsURLString)!
    }

    public var regionsService: RegionsService {
        return RegionsService(baseURL: regionsURL, apiKey: "org.onebusaway.iphone.test", uuid: "12345-12345-12345-12345-12345", appVersion: "2018.12.31")
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

    // MARK: - Data Loading

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

public extension URLComponents {
    public func queryItemValueMatching(name: String) -> String? {
        guard let queryItems = queryItems else {
            return nil
        }

        return queryItems.filter({$0.name == name}).first?.value
    }
}
