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

public protocol OperationTest { }
public extension OperationTest where Self: XCTestCase {

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
        return OHHTTPStubsResponse(
            fileAtPath: OHPathForFile(name, type(of: self))!,
            statusCode: 200,
            headers: ["Content-Type": "application/octet-stream"]
        )
    }

    public func JSONFile(named name: String) -> OHHTTPStubsResponse {
        return OHHTTPStubsResponse(
            fileAtPath: OHPathForFile(name, type(of: self))!,
            statusCode: 200,
            headers: ["Content-Type":"application/json"]
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
