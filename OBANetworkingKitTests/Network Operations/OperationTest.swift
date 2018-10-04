//
//  OperationTest.swift
//  OBANetworkingKitTests
//
//  Created by Aaron Brethorst on 10/4/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Quick
import Nimble
import OHHTTPStubs
@testable import OBANetworkingKit

class OperationTest: QuickSpec {
    public let host = "www.example.com"
    public lazy var baseURLString = "https://\(host)"
    public lazy var builder = NetworkRequestBuilder(baseURL: URL(string: baseURLString)!)

    public func JSONFile(named name: String) -> OHHTTPStubsResponse{
        return OHHTTPStubsResponse(
            fileAtPath: OHPathForFile(name, type(of: self))!,
            statusCode: 200,
            headers: ["Content-Type":"application/json"]
        )
    }
}
