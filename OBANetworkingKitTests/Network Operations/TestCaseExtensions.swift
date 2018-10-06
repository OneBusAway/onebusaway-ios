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
    public var host: String {
        return "www.example.com"
    }

    public var baseURLString: String {
        return "https://\(host)"
    }

    public var builder: NetworkRequestBuilder {
        return NetworkRequestBuilder(baseURL: URL(string: baseURLString)!)
    }

    public func JSONFile(named name: String) -> OHHTTPStubsResponse{
        return OHHTTPStubsResponse(
            fileAtPath: OHPathForFile(name, type(of: self))!,
            statusCode: 200,
            headers: ["Content-Type":"application/json"]
        )
    }
}
